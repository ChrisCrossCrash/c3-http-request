# C3HTTPRequest Benchmark

Comparison of `C3HTTPRequest` against Godot's native `HTTPRequest` node across three scenarios: single-request latency, concurrent request throughput, and large file downloads.

Both clients are built on the same transport: Godot's `HTTPClient`, a non-blocking state machine you drive by calling `poll()` repeatedly to advance it through its stages — resolving the host, connecting, sending the request, then reading the response body one chunk at a time. Neither client blocks a thread waiting on the network; instead each runs a **polling loop** that calls `poll()` over and over until the response is complete. Perhaps the most important design consideration regarding speed for each client is _how often, and on which thread, that loop gets to run._

Each scenario tests two polling modes. In **cooperative** mode (the default for both clients), the polling loop yields back to the scene tree whenever it has to wait, resuming on the next frame — so the frame rate bounds how often it can resume to make progress. How much work each client does within a single resume varies, and that is exactly where the two differ on downloads, below. This cadence ties timing to the frame rate throughout, so the latency scenario varies the frame cap directly (uncapped, 120, 60, and 30 fps) to isolate its effect. In **threaded** mode, the request runs on a background thread that polls at OS speed, decoupling it from the frame rate entirely. Each client opts in through its own setting: `Options.use_threads = true` for C3HTTPRequest, and the native node's own `use_threads` property for `HTTPRequest`. The four-column tables below report both modes for each client side by side.

**Test environment:**

|                  |                                                                                                                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Machine          | AMD Ryzen 5 7600, Windows 11                                                                                                                                                                                                |
| Godot            | 4.6.2-stable (official)                                                                                                                                                                                                     |
| Renderer         | forward_plus (Vulkan)                                                                                                                                                                                                       |
| Server           | Django/Daphne/Nginx on Amazon Lightsail (Ubuntu, 2 vCPUs, 512 MB RAM, Virginia Zone A) — [source](https://github.com/ChrisCrossCrash/chriskumm.com_django/blob/5c287dc02169d61a161ea12264c9641892b9dea5/benchmark/views.py) |
| Benchmark script | [`examples/benchmark/`](examples/benchmark/)                                                                                                                                                                                |
| Run command      | `godot --path . --no-debug examples/benchmark/benchmark.tscn`                                                                                                                                                               |

All results are medians, so a request occasionally slowed by system noise doesn't skew the numbers. The client machine was in Minneapolis, MN; the server in Virginia (AWS us-east-1), roughly 1,300 miles away.

---

## Latency

### Methodology

100 requests per variant, interleaved across variants so any slow drift in machine load is spread evenly. Warmup requests (not counted) prime the connection and DNS cache beforehand. Sweep runs at four frame caps: uncapped (headless default), 120 fps, 60 fps, and 30 fps.

### Results

| Frame rate | C3 cooperative | C3 threaded | native cooperative | native threaded |
| ---------- | -------------- | ----------- | ------------------ | --------------- |
| uncapped   | 165.82 ms      | 168.58 ms   | 168.48 ms          | 171.57 ms       |
| 120 fps    | 174.97 ms      | 174.88 ms   | 183.32 ms          | 174.90 ms       |
| 60 fps     | 183.30 ms      | 183.20 ms   | 199.98 ms          | 183.21 ms       |
| 30 fps     | 199.97 ms      | 199.86 ms   | 233.32 ms          | 199.85 ms       |

### Analysis

**The baseline is ~166–172 ms.** Running uncapped or in threaded mode removes all per-frame polling overhead, leaving just the network round-trip time. Both clients land in the same ~166–172 ms band — confirming this is a network constant, not a code difference.

**In cooperative mode, C3HTTPRequest resolves ~1 frame sooner than native.** Each frame adds one cooperative poll. The difference between C3 and native at each capped rate matches almost exactly one additional frame period:

- 120 fps (8.3 ms/frame): native is 8.4 ms slower than C3 — one frame
- 60 fps (16.7 ms/frame): native is 16.7 ms slower than C3 — one frame
- 30 fps (33.3 ms/frame): native is 33.4 ms slower than C3 — one frame

The native node requires one more cooperative poll per request than C3HTTPRequest, regardless of frame rate. The mechanism is visible in [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/4.6.2-stable/scene/main/http_request.cpp): the `STATUS_CONNECTED` case sends the request and immediately `return false`, which defers the next poll to the following frame:

```cpp
case HTTPClient::STATUS_CONNECTED: {
    // ...
    Error err = client->request(method, request_string, headers, ...);
    request_sent = true;
    return false; // come back next frame
} break;
```

C3HTTPRequest sends the request and then polls in a tight loop before deciding whether to yield — if the response has already arrived, it proceeds without waiting a frame. At a capped frame rate, `Options.use_threads = true` eliminates that overhead for both clients.

---

## Concurrency

### Methodology

Median wall-clock time for N simultaneous requests to complete, across 25 repetitions per concurrency level, at 60 fps. Concurrency levels: 1, 2, 4, 8.

For C3HTTPRequest, all N requests are launched as detached coroutines and share the same per-frame poll — they advance in parallel within a single scene-tree tick.

For native `HTTPRequest`, N nodes are created (required, since each node handles one request at a time), each fired immediately. Timers stop when the last completion callback fires.

### Results

| N   | C3 cooperative | native cooperative | C3 threaded | native threaded |
| --- | -------------- | ------------------ | ----------- | --------------- |
| 1   | 183.36 ms      | 216.57 ms          | 183.10 ms   | 183.29 ms       |
| 2   | 183.43 ms      | 216.54 ms          | 183.12 ms   | 183.31 ms       |
| 4   | 200.19 ms      | 233.19 ms          | 199.71 ms   | 199.96 ms       |
| 8   | 233.35 ms      | 266.48 ms          | 232.73 ms   | 217.23 ms       |

### Analysis

**C3HTTPRequest scales smoothly.** Wall-clock time grows modestly as concurrency rises: an extra ~16–33 ms per doubling (roughly one frame per additional serialized poll round). For C3 the threaded and cooperative variants are nearly identical at every level — its cooperative loop already advances all ready coroutines within a single frame, so polling at OS speed buys almost nothing here.

**Native cooperative trails by ~2 frames.** The same modest growth pattern applies, but native cooperative sits a steady ~33 ms (two 60 fps frames) behind C3 cooperative at every level — one frame more than the single-request gap. The extra frame is node lifecycle overhead in the concurrent harness (each request needs its own `HTTPRequest` node added to the tree), not a difference in the transfer itself.

**Threaded mode closes the native gap.** Removing the per-frame polls drops native threaded to roughly C3's level. At N=8 native threaded (217 ms) even edges about one frame ahead of C3 (233 ms): each native request runs on its own dedicated node and thread, whereas C3's gains here are limited by its already-efficient cooperative draining. In short, at high concurrency the two threaded clients land within a frame of each other.

---

## File Download

### Methodology

Stream a body to disk using a 64 KB chunk size (`Options.download_chunk_size`). Median of 25 runs per variant, at 60 fps. A warmup run (not counted) runs before timing begins. Body sizes: 1 MB, 8 MB.

### Results

| Body size | C3 cooperative | C3 threaded | native cooperative | native threaded |
| --------- | -------------- | ----------- | ------------------ | --------------- |
| 1 MB      | 350.23 ms      | 349.66 ms   | 500.12 ms          | 349.81 ms       |
| 8 MB      | 617.65 ms      | 594.54 ms   | 2366.71 ms         | 616.41 ms       |

### Analysis

**Native cooperative throughput is capped by the frame rate.** This is verifiable in the engine source, not just inferred from the numbers. In [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/4.6.2-stable/scene/main/http_request.cpp) (4.6.2-stable), the body-reading state in `_update_connection()` calls `client->read_response_body_chunk()` exactly once and then returns — there is no loop draining the socket within a single call:

```cpp
case HTTPClient::STATUS_BODY: {
    // ...
    client->poll();
    if (client->get_status() != HTTPClient::STATUS_BODY) {
        return false;
    }

    PackedByteArray chunk;
    if (decompressor.is_null()) {
        // Chunk can be read directly.
        chunk = client->read_response_body_chunk();
        downloaded.add(chunk.size());
    }
    // ...
    return false;
} break;
```

In cooperative mode `_update_connection()` runs once per frame (driven by `NOTIFICATION_INTERNAL_PROCESS`), so the node reads at most one chunk per frame. Each chunk is bounded by `download_chunk_size`, which the node passes straight to the client (`set_download_chunk_size()` → `client->set_read_chunk_size()`). The effective bandwidth ceiling is therefore `download_chunk_size × frame_rate`. At 60 fps with 65,536-byte chunks that is ~3.93 MB/s — regardless of how fast the connection actually delivers data. An 8 MB body therefore takes roughly 8 MB / 3.93 MB/s ≈ 2.04 s, which matches the measured 2.37 s closely (the remainder is the request round-trip plus disk writes).

The slowness was first reported in 2019 as [godot#32807](https://github.com/godotengine/godot/issues/32807), but note that the issue documents the _symptom_ (slow downloads), not this mechanism. The maintainers attributed it to the small default `read_chunk_size` and resolved the issue by exposing `download_chunk_size` as a tunable, later raising its default to 64 KiB. That lifts the ceiling but does not remove the one-chunk-per-frame gate — which is the deeper cause, and which the verbatim source above shows is still present in 4.6.2. (The per-frame structure was correctly identified by a commenter in that thread, but it was never the basis of the fix.) So the claim here rests on the engine source, not on the issue.

**C3HTTPRequest drains all available chunks per frame in cooperative mode.** For small bodies that arrive within a single frame's worth of network data, there's no difference. For larger bodies (8 MB), C3HTTPRequest reads everything the connection delivers each frame, so time tracks bandwidth rather than polling cadence — about 4× faster at 60 fps for an 8 MB body.

**Threaded mode equalizes both clients.** With `use_threads = true`, both poll at OS speed and deliver the full link bandwidth. The small difference between C3 (595 ms) and native (616 ms) for 8 MB is within the noise of 25 repetitions over a remote connection.

A side effect worth noting: when V-Sync is enabled the frame rate locks to the monitor's refresh rate, so download throughput is directly proportional to it — a 144 Hz monitor yields a ~9.44 MB/s ceiling and a 240 Hz monitor ~15.73 MB/s. In other words, **upgrading your monitor makes your downloads faster with the native `HTTPRequest` for cooperative (i.e., non-threaded) downloads**. `C3HTTPRequest` has no such ceiling because it drains all available chunks per frame, so its throughput is bottlenecked by the actual connection speed rather than the frame rate.

The cooperative advantage depends on body size relative to what the connection can deliver per frame. For bodies that fit in one or two frames of bandwidth (most API responses), the two clients are equivalent in cooperative mode. The gap is most pronounced for large downloads with a fast enough connection to deliver multiple chunks per frame.

---

## Summary

| Scenario                          | C3HTTPRequest                      | native HTTPRequest                  |
| --------------------------------- | ---------------------------------- | ----------------------------------- |
| Latency (cooperative)             | ~1 frame sooner at any capped rate | baseline                            |
| Latency (threaded)                | equal (RTT-limited)                | equal (RTT-limited)                 |
| Concurrent requests (cooperative) | smooth scaling                     | ~2 frames slower, otherwise smooth  |
| 8 MB download (cooperative)       | ~4× faster                         | frame-rate-gated throughput ceiling |
| 8 MB download (threaded)          | equal                              | equal                               |

For latency-sensitive or high-concurrency workloads on a capped frame rate, `Options.use_threads = true` is the practical recommendation for either client. For large cooperative downloads, C3HTTPRequest is the only option that doesn't hit the per-frame chunk ceiling.

---

## Raw Output

```
Godot Engine v4.6.2.stable.official.71f334935 - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070

C3HTTPRequest benchmark vs native HTTPRequest
commit a22941c
Godot 4.6.2-stable (official) | Windows | AMD Ryzen 5 7600 6-Core Processor | forward_plus renderer

== Single-request latency (median of 100 requests) ==

uncapped             cooperative   threaded
C3HTTPRequest:         165.82 ms    168.58 ms
native HTTPRequest:    168.48 ms    171.57 ms

120 fps              cooperative   threaded
C3HTTPRequest:         174.97 ms    174.88 ms
native HTTPRequest:    183.32 ms    174.90 ms

60 fps               cooperative   threaded
C3HTTPRequest:         183.30 ms    183.20 ms
native HTTPRequest:    199.98 ms    183.21 ms

30 fps               cooperative   threaded
C3HTTPRequest:         199.97 ms    199.86 ms
native HTTPRequest:    233.32 ms    199.85 ms

== Concurrency: wall-clock to complete N simultaneous requests (median of 25 batches, 60 fps) ==
    N   C3 coop      nat coop     C3 thread    nat thread
    1     183.36 ms     216.57 ms     183.10 ms     183.29 ms
    2     183.43 ms     216.54 ms     183.12 ms     183.31 ms
    4     200.19 ms     233.19 ms     199.71 ms     199.96 ms
    8     233.35 ms     266.48 ms     232.73 ms     217.23 ms

== File download to disk (median of 25 runs, 60 fps) ==
Target: https://api.chriskumm.com/api/benchmark/download/1048576/

1 MB                 cooperative   threaded
C3HTTPRequest:         350.23 ms    349.66 ms
native HTTPRequest:    500.12 ms    349.81 ms

8 MB                 cooperative   threaded
C3HTTPRequest:         617.65 ms    594.54 ms
native HTTPRequest:   2366.71 ms    616.41 ms

Done.
```
