# C3HTTPRequest Benchmark

Comparison of `C3HTTPRequest` against Godot's native `HTTPRequest` node across four scenarios: single-request latency, concurrent request throughput, small downloads (TCP slow-start behavior), and large file downloads.

Both clients are built on the same transport: Godot's `HTTPClient`, a non-blocking state machine you drive by calling `poll()` repeatedly to advance it through its stages — resolving the host, connecting, sending the request, then reading the response body one chunk at a time. Neither client blocks a thread waiting on the network; instead each runs a **polling loop** that calls `poll()` over and over until the response is complete. One of the important design consideration regarding speed for each client is _how often, and on which thread, that loop gets to run._

Each scenario tests two polling modes. In **cooperative** mode (the default for both clients), the polling loop yields back to the scene tree whenever it has to wait, resuming on the next frame — so the frame rate bounds how often it can resume to make progress. How much work each client does within a single resume varies, and that is exactly where the two differ on downloads, below. This cadence ties timing to the frame rate throughout, so the latency scenario varies the frame cap directly (uncapped, 120, 60, and 30 fps) to isolate its effect. In **threaded** mode, the request runs on a background thread that polls at OS speed, decoupling it from the frame rate entirely. Each client opts in through its own setting: `Options.use_threads = true` for C3HTTPRequest, and the native node's own `use_threads` property for `HTTPRequest`. The tables below report both modes for each client side by side. Every section also includes a `C3 (session)` variant that passes a shared `Session` object via `Options.session`, reusing the existing TLS/TCP connection across requests instead of opening a new one each time.

**Test environment:**

|                  |                                                                                                                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Machine          | AMD Ryzen 5 7600, Windows 11                                                                                                                                                                                                |
| Godot            | 4.7-stable (official)                                                                                                                                                                                                       |
| Renderer         | forward_plus (Vulkan), NVIDIA GeForce RTX 4070                                                                                                                                                                              |
| Server           | Django/Daphne/Nginx on Amazon Lightsail (Ubuntu, 2 vCPUs, 512 MB RAM, Virginia Zone A) — [source](https://github.com/ChrisCrossCrash/chriskumm.com_django/blob/5c287dc02169d61a161ea12264c9641892b9dea5/benchmark/views.py) |
| Benchmark script | [`examples/benchmark/`](examples/benchmark/)                                                                                                                                                                                |
| Run command      | `godot --path . --no-debug examples/benchmark/benchmark.tscn`                                                                                                                                                               |

All results are medians, so a request occasionally slowed by system noise doesn't skew the numbers. The client machine was in Minneapolis, MN; the server in Virginia (AWS us-east-1), roughly 1,300 miles away.

---

## Latency

### Methodology

25 requests per variant, interleaved across variants so any slow drift in machine load is spread evenly. Warmup requests (not counted) prime the connection and DNS cache beforehand. Sweep runs at four frame caps: uncapped (headless default), 120 fps, 60 fps, and 30 fps.

### Results

| Frame rate | C3 cooperative | C3 threaded | native cooperative | native threaded |
| ---------- | -------------- | ----------- | ------------------ | --------------- |
| uncapped   | 160.98 ms      | 163.26 ms   | 161.62 ms          | 164.16 ms       |
| 120 fps    | 174.93 ms      | 166.52 ms   | 183.33 ms          | 166.56 ms       |
| 60 fps     | 183.26 ms      | 166.52 ms   | 200.00 ms          | 166.56 ms       |
| 30 fps     | 199.93 ms      | 166.52 ms   | 233.33 ms          | 166.58 ms       |

#### Session (keep-alive)

| Frame rate | C3 session cooperative | C3 session threaded |
| ---------- | ---------------------- | ------------------- |
| uncapped   | 34.45 ms               | 35.43 ms            |
| 120 fps    | 41.69 ms               | 41.50 ms            |
| 60 fps     | 50.02 ms               | 49.83 ms            |
| 30 fps     | 66.69 ms               | 66.49 ms            |

### Analysis

**The baseline is ~161–164 ms.** Running uncapped removes per-frame polling overhead, leaving just the network round-trip time. Both clients land in the same ~161–164 ms band — confirming this is a network constant, not a code difference.

**Threaded mode is nearly flat across frame caps.** Both clients sit at ~161–164 ms uncapped and ~166.5 ms at every capped rate — they do _not_ climb with the frame cap the way cooperative mode does (compare native cooperative's 183 → 200 → 233 ms). The request runs on a background thread that completes the whole connection (resolve, connect, send, receive) in one shot at network speed, ~161 ms. The only frame-dependent cost left is delivery: the finished result is handed back to the awaiting main-thread coroutine on the next `process_frame`, so the measured time is the true network time rounded _up_ to the next frame boundary — at most one frame of overhead. That all three capped rates land on the same ~166.5 ms is a coincidence of the caps chosen: ~161 ms rounds up to 20 frames at 120 fps, 10 frames at 60 fps, and 5 frames at 30 fps, and all three products fall at ~166.7 ms. Unlike cooperative mode, threaded mode never accumulates per-frame polling latency, so it stays flat instead of rising as the cap drops.

**In cooperative mode, C3HTTPRequest resolves ~1 frame sooner than native.** The difference between C3 and native at each capped rate matches almost exactly one additional frame period:

- 120 fps (8.3 ms/frame): native is 8.4 ms slower than C3 — one frame
- 60 fps (16.7 ms/frame): native is 16.7 ms slower than C3 — one frame
- 30 fps (33.3 ms/frame): native is 33.4 ms slower than C3 — one frame

The native node burns one extra frame per request, regardless of frame rate, because of how its polling loop is structured. `HTTPRequest` runs one iteration of a `switch (client->get_status())` per frame, in [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/http_request.cpp#L415-L420). When `client->poll()` advances the status, that transition isn't acted on until the _next_ frame, when the switch is evaluated again. The `STATUS_REQUESTING` case shows it:

```cpp
case HTTPClient::STATUS_REQUESTING: {
    client->poll();   // headers may arrive here → status becomes STATUS_BODY
    return false;     // but we've already branched; bail and come back next frame
} break;
```

On the frame the headers arrive, `poll()` moves the client to `STATUS_BODY`, but the switch has already committed to the `STATUS_REQUESTING` branch, so it returns and waits. Only on the following frame does the switch re-read the status, fall into the `STATUS_BODY` case, and read the response. The status was updated one frame before it was checked.

C3HTTPRequest re-reads the status in the same loop iteration, right after polling, and proceeds without yielding the moment the request phase ends:

```gdscript
while true:
    client.poll()                                        # → STATUS_BODY
    if client.get_status() != HTTPClient.STATUS_REQUESTING:
        break                                            # proceed this frame, no yield
    ...
    await _pump(tree, _on_worker)
```

So a status transition that costs native a frame costs C3 nothing. This is the same mechanism at every status boundary; the `STATUS_REQUESTING` → `STATUS_BODY` transition is the one that lands inside the measured window. At a capped frame rate, `Options.use_threads = true` eliminates this overhead for both clients.

**C3 (session) eliminates connection-establishment overhead entirely.** When `Options.session` is set to a shared `Session` object, C3HTTPRequest reuses the existing TLS/TCP connection instead of opening a new one. The warmup requests pre-fill the session's connection pool so each timed call finds a ready connection. Measured times drop to 34–67 ms across frame caps — compared to 161–233 ms without a session — eliminating roughly 125 ms of TCP and TLS handshake overhead per request. Session latency still grows with lower frame caps (the main-thread coroutine still waits on `process_frame`), but the absolute numbers are so small that even at 30 fps the time is under 70 ms. Cooperative and threaded are within 2 ms of each other at every cap, since the connection-setup time that threading could overlap is already gone.

---

## Concurrency

### Methodology

Median wall-clock time for N simultaneous requests to complete, across 25 repetitions per concurrency level, at 60 fps. Concurrency levels: 1, 2, 4, 8.

For C3HTTPRequest, all N requests are launched as detached coroutines and share the same per-frame poll — they advance in parallel within a single scene-tree tick.

For native `HTTPRequest`, N nodes are created (required, since each node handles one request at a time), each fired immediately. Timers stop when the last completion callback fires.

### Results

| N   | C3 cooperative | native cooperative | C3 threaded | native threaded |
| --- | -------------- | ------------------ | ----------- | --------------- |
| 1   | 183.35 ms      | 216.57 ms          | 166.47 ms   | 166.69 ms       |
| 2   | 183.41 ms      | 216.55 ms          | 183.05 ms   | 183.30 ms       |
| 4   | 200.21 ms      | 233.17 ms          | 199.56 ms   | 199.95 ms       |
| 8   | 233.20 ms      | 266.38 ms          | 216.56 ms   | 216.75 ms       |

#### Session (keep-alive)

| N   | C3 session cooperative | C3 session threaded |
| --- | ---------------------- | ------------------- |
| 1   | 50.03 ms               | 49.83 ms            |
| 2   | 50.09 ms               | 49.77 ms            |
| 4   | 66.77 ms               | 66.44 ms            |
| 8   | 83.56 ms               | 82.99 ms            |

### Analysis

**C3HTTPRequest scales smoothly.** Wall-clock time grows modestly as concurrency rises: an extra ~16–33 ms per doubling (roughly one frame per additional serialized poll round). Cooperative grows 183 → 183 → 200 → 233 ms; threaded grows one clean frame per doubling, 166 → 183 → 200 → 217 ms. Threaded runs about one frame ahead of cooperative at N=1 and N=8 and ties it at N=2 and N=4 — the cooperative loop already advances all ready coroutines within a single frame, so polling at OS speed only ever saves the odd boundary frame.

**Native cooperative trails by ~2 frames.** The same modest growth pattern applies, but native cooperative sits a steady ~33 ms (two 60 fps frames) behind C3 cooperative at every level — one frame more than the single-request gap. The extra frame is node lifecycle overhead in the concurrent harness (each request needs its own `HTTPRequest` node added to the tree), not a difference in the transfer itself.

**Threaded mode equalizes the two clients.** C3 threaded and native threaded are within 0.5 ms of each other at every level — ~166, 183, 200, and 217 ms at N=1, 2, 4, and 8. With both polling at OS speed, neither node lifecycle overhead nor coroutine scheduling separates them by more than measurement noise.

**A shared session collapses the batch to one round trip's worth of work.** With every request drawing a warm connection from the pool, the whole batch finishes in ~50 ms at N=1–2 and ~67–84 ms at N=4–8 — 3–4× faster than the fresh-connection variants and within ~1 ms between cooperative and threaded. The pool's `max_connections_per_host` is raised to the batch size, so all N requests proceed in parallel over reused connections instead of paying a handshake each.

---

## Small Download (TCP Slow-Start)

### Background: the congestion window and IW10

When a TCP connection opens, it has no idea how much bandwidth the path can absorb. Flooding it immediately would risk swamping a slow link and triggering packet loss, so TCP starts cautiously and ramps up. The limit on how much unacknowledged data the sender may have in flight at any moment is the **congestion window** (cwnd). A fresh connection begins at the **initial congestion window**, which by modern default (RFC 6928) is 10 segments — commonly called **IW10**, about **14.6 KB** (10 × the ~1460-byte maximum segment size). The server may send up to that much, then must wait for the client's acknowledgement — one network round trip (RTT) — before it is allowed to send more. Each successful round trip roughly doubles the window (this ramp is _slow start_), so the connection climbs toward the path's real capacity over several RTTs.

Two consequences drive this benchmark:

- A payload that fits inside IW10 (≲ 14.6 KB) is delivered in a **single** post-handshake round trip. A larger one needs **additional** round trips while the window grows.
- A connection that has already carried traffic — a warm `Session` — has an enlarged window and skips the ramp entirely. (The benchmark server is configured with `net.ipv4.tcp_slow_start_after_idle=0`, so an idle keep-alive connection does not reset its window between requests; the warm-session advantage persists across gaps.)

This section picks three sizes to straddle that threshold: **10 KB** (fits in IW10), **20 KB** (just over it, so a fresh connection needs one extra RTT), and **400 KB** (far past it, so a fresh connection climbs slow start over several RTTs).

### Methodology

Download a body of the stated size, median of 25 runs per variant, at 60 fps. A single `Session` is shared across all three sizes so its window is fully warmed by the time the larger rows run. Warmup runs (not counted) precede timing.

### Results

| Body size | C3 cooperative | C3 threaded | C3 session cooperative | C3 session threaded | native cooperative | native threaded |
| --------- | -------------- | ----------- | ---------------------- | ------------------- | ------------------ | --------------- |
| 10 KB     | 183.33 ms      | 166.44 ms   | 50.03 ms               | 49.81 ms            | 200.03 ms          | 166.51 ms       |
| 20 KB     | 200.00 ms      | 199.78 ms   | 50.04 ms               | 49.82 ms            | 216.70 ms          | 199.83 ms       |
| 400 KB    | 283.77 ms      | 282.66 ms   | 51.12 ms               | 48.75 ms            | 333.40 ms          | 283.11 ms       |

### Analysis

**10 KB fits in one window, so it costs no more than a bare ping.** At 10 KB the fresh-connection times match the single-request latency baseline almost exactly — C3 cooperative 183 ms (vs. 183 ms for an empty ping at 60 fps), native 200 ms, both ~166 ms threaded. The whole body arrives in the first congestion window, in a single round trip, so there is nothing to pay beyond the handshake and one RTT.

**20 KB crosses IW10, so a fresh connection pays an extra round trip.** Bumping the body just past ~14.6 KB forces the server to stop after the first window and wait for an ACK before sending the rest. On fresh connections that extra round trip shows up as one or two added frames — C3 cooperative rises 183 → 200 ms, native 200 → 217 ms, and threaded jumps 166 → 200 ms. **The warm session does not move at all: 50 ms at both 10 KB and 20 KB.** Its window is already far larger than 20 KB, so the entire body still goes out in one round trip. This is the crux of the scenario — the slow-start penalty is a property of _fresh_ connections, and a `Session` erases it.

**400 KB makes the gap dramatic.** A body this large forces a fresh connection up the slow-start ramp over several round trips: C3 cooperative 284 ms, native 333 ms, ~283 ms threaded. The warm session delivers the same 400 KB in **51 ms** — barely more than its 10 KB time — because its window grew past 400 KB many requests ago. Here the session saves ~230 ms over a fresh cooperative connection, almost all of it slow-start ramp that never has to happen.

---

## File Download

### Methodology

Stream a body to disk using a 64 KB chunk size (`Options.download_chunk_size`). Median of 25 runs per variant, at 60 fps. A warmup run (not counted) runs before timing begins. Body sizes: 1 MB, 8 MB.

### Results

| Body size | C3 cooperative | C3 threaded | native cooperative | native threaded |
| --------- | -------------- | ----------- | ------------------ | --------------- |
| 1 MB      | 333.62 ms      | 332.95 ms   | 500.14 ms          | 349.72 ms       |
| 8 MB      | 566.72 ms      | 584.77 ms   | 2366.71 ms         | 601.19 ms       |

#### Session (keep-alive)

| Body size | C3 session cooperative | C3 session threaded |
| --------- | ---------------------- | ------------------- |
| 1 MB      | 100.50 ms              | 99.38 ms            |
| 8 MB      | 883.45 ms              | 749.70 ms           |

### Analysis

**Native cooperative throughput is capped by the frame rate.** This is verifiable in the engine source, not just inferred from the numbers. In [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/http_request.cpp) (4.7-stable), the body-reading state in `_update_connection()` calls `client->read_response_body_chunk()` exactly once and then returns — there is no loop draining the socket within a single call:

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

The slowness was first reported in 2019 as [godot#32807](https://github.com/godotengine/godot/issues/32807), but note that the issue documents the _symptom_ (slow downloads), not this mechanism. The maintainers attributed it to the small default `read_chunk_size` and resolved the issue by exposing `download_chunk_size` as a tunable, later raising its default to 64 KiB. That lifts the ceiling but does not remove the one-chunk-per-frame gate — which is the deeper cause, and which the verbatim source above shows is still present in 4.7-stable. (The per-frame structure was correctly identified by a commenter in that thread, but it was never the basis of the fix.) So the claim here rests on the engine source, not on the issue.

**C3HTTPRequest drains all available chunks per frame in cooperative mode.** It reads everything the connection delivers each frame, so its time tracks bandwidth rather than polling cadence — about 4× faster than native at 60 fps for an 8 MB body (567 ms vs. 2367 ms). The advantage already shows at 1 MB (334 ms vs. 500 ms): a 1 MB body is ~16 chunks, which at one chunk per frame is ~16 frames of gating that C3 collapses into far fewer. The two clients converge only once a body fits in a frame or two of chunks.

**Threaded mode equalizes both clients.** With `use_threads = true`, both poll at OS speed and deliver the full link bandwidth. For 8 MB, C3 (585 ms) and native (601 ms) are within ~17 ms — one frame, and well inside the round-trip and disk-write variance across 25 repetitions over a remote connection.

**The session is a win at 1 MB but not at 8 MB.** For 1 MB the warm session finishes in ~100 ms versus ~333 ms for a fresh connection — the same slow-start saving seen in the small-download section, since 1 MB is still small enough that ramping the window dominates. For 8 MB, though, the session is _slower_ than a fresh connection (883 ms cooperative / 750 ms threaded vs. 567 / 585 ms). The benchmark does not pin down the cause; the most likely candidate is that the long-lived connection's already-large window overshoots the path on a multi-megabyte transfer and pays it back in loss and retransmission, where a fresh connection ramps up more conservatively and avoids that. Either way, the takeaway is practical: a session helps most when handshake and slow-start are a large fraction of the transfer — short requests and small bodies — and offers no benefit once the transfer is large enough to reach steady-state bandwidth on its own.

A side effect worth noting: when V-Sync is enabled the frame rate locks to the monitor's refresh rate, so download throughput is directly proportional to it — a 144 Hz monitor yields a ~9.44 MB/s ceiling and a 240 Hz monitor ~15.73 MB/s. In other words, **upgrading your monitor makes your downloads faster with the native `HTTPRequest` for cooperative (i.e., non-threaded) downloads**. `C3HTTPRequest` has no such ceiling because it drains all available chunks per frame, so its throughput is bottlenecked by the actual connection speed rather than the frame rate.

The cooperative advantage depends on body size relative to what the connection can deliver per frame. For bodies that fit in one or two frames of bandwidth (most API responses), the two clients are equivalent in cooperative mode. The gap is most pronounced for large downloads with a fast enough connection to deliver multiple chunks per frame.

---

## Summary

| Scenario                           | C3HTTPRequest                              | native HTTPRequest                   |
| ---------------------------------- | ------------------------------------------ | ------------------------------------ |
| Latency (cooperative)              | ~1 frame sooner at any capped rate         | baseline                             |
| Latency (threaded)                 | flat ~166 ms; does not rise with cap       | flat ~166 ms; does not rise with cap |
| Latency (session)                  | ~4–5× lower; eliminates handshake overhead | —                                    |
| Concurrent requests (cooperative)  | smooth scaling                             | ~2 frames slower, otherwise smooth   |
| Concurrent requests (session)      | 3–4× faster; warm pool serves the batch    | —                                    |
| 20 KB download (fresh connection)  | +1 RTT past IW10; session pays none        | +1 RTT past IW10                     |
| 400 KB download (fresh vs session) | ~284 ms fresh vs ~51 ms session            | ~333 ms fresh                        |
| 8 MB download (cooperative)        | ~4× faster                                 | frame-rate-gated throughput ceiling  |
| 8 MB download (threaded)           | within ~1 frame                            | within ~1 frame                      |

For minimum latency, `Options.session` with a shared `Session` object is the strongest lever — it eliminates handshake and TCP slow-start overhead entirely, cutting round-trip time by ~125 ms per request when the connection is already established. That advantage holds for short requests and small bodies but fades for large transfers (and at 8 MB even reverses). For large cooperative downloads, C3HTTPRequest is the only option that doesn't hit the per-frame chunk ceiling; `Options.use_threads = true` is effective here and brings native `HTTPRequest` up to the same throughput.

---

## Raw Output

```
Godot Engine v4.7.stable.official.5b4e0cb0f - https://godotengine.org
Vulkan 1.4.341 - Forward+ - Using Device #0: NVIDIA - NVIDIA GeForce RTX 4070

C3HTTPRequest benchmark vs native HTTPRequest
commit 63b3902
Godot 4.7-stable (official) | Windows | AMD Ryzen 5 7600 6-Core Processor | forward_plus renderer

== Single-request latency (median of 25 requests) ==

uncapped             cooperative   threaded
C3HTTPRequest:         160.98 ms    163.26 ms
C3 (session):           34.45 ms     35.43 ms
native HTTPRequest:    161.62 ms    164.16 ms

120 fps              cooperative   threaded
C3HTTPRequest:         174.93 ms    166.52 ms
C3 (session):           41.69 ms     41.50 ms
native HTTPRequest:    183.33 ms    166.56 ms

60 fps               cooperative   threaded
C3HTTPRequest:         183.26 ms    166.52 ms
C3 (session):           50.02 ms     49.83 ms
native HTTPRequest:    200.00 ms    166.56 ms

30 fps               cooperative   threaded
C3HTTPRequest:         199.93 ms    166.52 ms
C3 (session):           66.69 ms     66.49 ms
native HTTPRequest:    233.33 ms    166.58 ms

== Concurrency: wall-clock to complete N simultaneous requests (median of 25 batches, 60 fps) ==
    N       C3 coop      C3s coop      nat coop     C3 thread    C3s thread    nat thread
    1     183.35 ms      50.03 ms     216.57 ms     166.47 ms      49.83 ms     166.69 ms
    2     183.41 ms      50.09 ms     216.55 ms     183.05 ms      49.77 ms     183.30 ms
    4     200.21 ms      66.77 ms     233.17 ms     199.56 ms      66.44 ms     199.95 ms
    8     233.20 ms      83.56 ms     266.38 ms     216.56 ms      82.99 ms     216.75 ms

== Small download: slow-start control vs. straddled IW10 (median of 25 runs, 60 fps) ==

10 KB                cooperative   threaded
C3HTTPRequest:         183.33 ms    166.44 ms
C3 (session):           50.03 ms     49.81 ms
native HTTPRequest:    200.03 ms    166.51 ms

20 KB                cooperative   threaded
C3HTTPRequest:         200.00 ms    199.78 ms
C3 (session):           50.04 ms     49.82 ms
native HTTPRequest:    216.70 ms    199.83 ms

400 KB               cooperative   threaded
C3HTTPRequest:         283.77 ms    282.66 ms
C3 (session):           51.12 ms     48.75 ms
native HTTPRequest:    333.40 ms    283.11 ms

== File download to disk (median of 25 runs, 60 fps) ==
Target: https://api.chriskumm.com/api/benchmark/download/1048576/

1 MB                 cooperative   threaded
C3HTTPRequest:         333.62 ms    332.95 ms
C3 (session):          100.50 ms     99.38 ms
native HTTPRequest:    500.14 ms    349.72 ms

8 MB                 cooperative   threaded
C3HTTPRequest:         566.72 ms    584.77 ms
C3 (session):          883.45 ms    749.70 ms
native HTTPRequest:   2366.71 ms    601.19 ms

Done.
```
