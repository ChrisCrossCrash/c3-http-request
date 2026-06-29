# C3Http Benchmark

This analysis compares `C3Http` against Godot's [`HTTPRequest`](https://docs.godotengine.org/en/4.7/classes/class_httprequest.html) node across three scenarios: single-request latency, small downloads (TCP slow-start behavior), and large file downloads. The results are from a run of the [`examples/benchmark/benchmark.gd`](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/examples/benchmark/benchmark.gd) script, which generated the results in [`BENCHMARK.md`](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/BENCHMARK.md).

Both clients are built on the same transport: Godot's [`HTTPClient`](https://docs.godotengine.org/en/4.7/classes/class_httpclient.html), a non-blocking state machine you drive by calling `poll()` repeatedly to advance it through its stages — resolving the host, connecting, sending the request, then reading the response body one chunk at a time. Neither client blocks a thread waiting on the network; instead each runs a **polling loop** that calls `poll()` over and over until the response is complete. One of the important design consideration regarding speed for each client is _how often, and on which thread, that loop gets to run._

Each scenario tests two polling modes. In **cooperative** mode (the default for both clients), the polling loop yields back to the scene tree whenever it has to wait, resuming on the next frame — so the frame rate bounds how often it can resume to make progress. How much work each client does within a single resume varies, and that is exactly where the two differ on downloads, below. This cadence ties timing to the frame rate throughout, so the latency scenario varies the frame cap directly (uncapped, 120, 60, and 30 fps) to isolate its effect. In **threaded** mode, the request runs on a background thread that polls at OS speed, decoupling it from the frame rate entirely. Each client opts in through its own setting: `Options.use_threads = true` for `C3Http`, and `HTTPRequest`'s own `use_threads` property. The tables below report both modes for each client side by side. Every section also includes a `C3Http` "session" variant that passes a shared `Session` object via `Options.session`, reusing the existing TLS/TCP connection across requests instead of opening a new one each time.

**Test environment:**

|                  |                                                                                                                                                                                                                             |
| ---------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Machine          | AMD Ryzen 5 7600, Windows 11                                                                                                                                                                                                |
| Godot            | 4.7-stable (official)                                                                                                                                                                                                       |
| Renderer         | forward_plus (Vulkan), NVIDIA GeForce RTX 4070                                                                                                                                                                              |
| Server           | Django/Daphne/Nginx on Amazon Lightsail (Ubuntu, 2 vCPUs, 512 MB RAM, Virginia Zone A) — [source](https://github.com/ChrisCrossCrash/chriskumm.com_django/blob/5c287dc02169d61a161ea12264c9641892b9dea5/benchmark/views.py) |
| Server TCP       | BBR congestion control, fq qdisc, `tcp_slow_start_after_idle=0`                                                                                                                                                             |
| Benchmark script | [`examples/benchmark/`](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/examples/benchmark/)                                                                                                                   |
| Run command      | `godot --path . --no-debug examples/benchmark/benchmark.tscn`                                                                                                                                                               |

> [!NOTE]
> To prevent abuse, the server requires an API key for all requests. However, a [Python script](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/examples/benchmark/benchmark_server.py) is included, which will run a benchmark-compatible server locally on your own machine. To use it, change the `SERVER_BASE` constant in [`benchmark.gd`](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/examples/benchmark/benchmark.gd) to point to `http://127.0.0.1:8927`, then run the Python script in a separate terminal before running the benchmark. The results will differ significantly from the published numbers due to the local connection, but the relative performance of the clients should be similar.

All results are medians, so a request occasionally slowed by system noise doesn't skew the numbers. The client machine was in Minneapolis, MN; the server in Virginia (AWS us-east-1), roughly 1,300 miles away. All timing values are in milliseconds. The following table defines the labels used in the results tables below.

| ID       | Description                                         |
| -------- | --------------------------------------------------- |
| nat_coop | Native `HTTPRequest`, cooperative (default) polling |
| c3_coop  | `C3Http`, cooperative (default) polling             |
| c3s_coop | `C3Http`, cooperative polling, session (keep-alive) |
| nat_thr  | Native `HTTPRequest`, threaded polling              |
| c3_thr   | `C3Http`, threaded polling                          |
| c3s_thr  | `C3Http`, threaded polling, session (keep-alive)    |

---

## Latency

### Methodology

25 requests per variant, interleaved across variants so any slow drift in machine load is spread evenly. Warmup requests (not counted) prime the connection and DNS cache beforehand. Sweep runs at four frame caps: uncapped, 120 fps, 60 fps, and 30 fps.

### Results

| Frame rate | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| ---------- | -------- | ------- | -------- | ------- | ------ | ------- |
| uncapped   | 162.1    | 162.9   | 33.5     | 165.7   | 163.6  | 34.5    |
| 120 fps    | 183.3    | 174.9   | 41.7     | 166.6   | 166.5  | 41.5    |
| 60 fps     | 200.0    | 183.3   | 50.0     | 166.6   | 166.5  | 49.8    |
| 30 fps     | 233.3    | 199.9   | 66.7     | 166.6   | 166.5  | 66.5    |

### Analysis

**The baseline is ~162–166 ms.** Running uncapped removes per-frame polling overhead, leaving just the network round-trip time. Both clients land in the same ~162–166 ms band — confirming this is a network constant, not a code difference.

**Threaded mode is nearly flat across frame caps.** Both clients sit at ~162–166 ms uncapped and ~166.5 ms at every capped rate — they do _not_ climb with the frame cap the way cooperative mode does (compare native cooperative's 183 → 200 → 233 ms). The request runs on a background thread that completes the whole connection (resolve, connect, send, receive) in one shot at network speed, ~162 ms. The only frame-dependent cost left is delivery: the finished result is handed back to the awaiting main-thread coroutine on the next `process_frame`, so the measured time is the true network time rounded _up_ to the next frame boundary — at most one frame of overhead. That all three capped rates land on the same ~166.5 ms is a coincidence of the caps chosen: ~162 ms rounds up to 20 frames at 120 fps, 10 frames at 60 fps, and 5 frames at 30 fps, and all three products fall at ~166.7 ms. Unlike cooperative mode, threaded mode never accumulates per-frame polling latency, so it stays flat instead of rising as the cap drops.

**In cooperative mode, `C3Http` resolves ~1 frame sooner than native.** The difference between `C3Http` and `HTTPRequest` at each capped rate matches almost exactly one additional frame period:

- 120 fps (8.3 ms/frame): `HTTPRequest` is 8.4 ms slower than `C3Http` — one frame
- 60 fps (16.7 ms/frame): `HTTPRequest` is 16.7 ms slower than `C3Http` — one frame
- 30 fps (33.3 ms/frame): `HTTPRequest` is 33.4 ms slower than `C3Http` — one frame

`HTTPRequest` burns one extra frame per request, regardless of frame rate, because of how its polling loop is structured. `HTTPRequest` runs one iteration of a `switch (client->get_status())` per frame, in [`scene/main/http_request.cpp`](https://github.com/godotengine/godot/blob/4.7-stable/scene/main/http_request.cpp#L415-L420). When `client->poll()` advances the status, that transition isn't acted on until the _next_ frame, when the switch is evaluated again. The `STATUS_REQUESTING` case shows it:

```cpp
case HTTPClient::STATUS_REQUESTING: {
    client->poll();   // headers may arrive here → status becomes STATUS_BODY
    return false;     // but we've already branched; bail and come back next frame
} break;
```

On the frame the headers arrive, `poll()` moves the client to `STATUS_BODY`, but the switch has already committed to the `STATUS_REQUESTING` branch, so it returns and waits. Only on the following frame does the switch re-read the status, fall into the `STATUS_BODY` case, and read the response. The status was updated one frame before it was checked.

`C3Http` re-reads the status in the same loop iteration, right after polling, and proceeds without yielding the moment the request phase ends:

```gdscript
while true:
    client.poll()                                        # → STATUS_BODY
    if client.get_status() != HTTPClient.STATUS_REQUESTING:
        break                                            # proceed this frame, no yield
    ...
    await _pump(tree, _on_worker)
```

So a status transition that costs native a frame costs `C3Http` nothing. This is the same mechanism at every status boundary; the `STATUS_REQUESTING` → `STATUS_BODY` transition is the one that lands inside the measured window. At a capped frame rate, `Options.use_threads = true` eliminates this overhead for both clients.

**`C3Http` (session) eliminates connection-establishment overhead entirely.** When `Options.session` is set to a shared `Session` object, `C3Http` reuses the existing TLS/TCP connection instead of opening a new one. The warmup requests pre-fill the session's connection pool so each timed call finds a ready connection. Measured times drop to 33–67 ms across frame caps — compared to 162–233 ms without a session — eliminating roughly 125 ms of TCP and TLS handshake overhead per request. Session latency still grows with lower frame caps (the main-thread coroutine still waits on `process_frame`), but the absolute numbers are so small that even at 30 fps the time is under 70 ms. Cooperative and threaded are within 2 ms of each other at every cap, since the connection-setup time that threading could overlap is already gone.

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

| Body size | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| --------- | -------- | ------- | -------- | ------- | ------ | ------- |
| 10 KB     | 200.0    | 183.3   | 50.0     | 183.2   | 183.1  | 49.8    |
| 20 KB     | 200.0    | 199.9   | 50.0     | 199.8   | 199.9  | 49.8    |
| 400 KB    | 333.4    | 300.1   | 51.1     | 299.8   | 299.6  | 65.4    |

### Analysis

**10 KB fits in one window, but a body adds one frame in threaded mode.** At 10 KB the fresh-connection cooperative times match the single-request latency baseline — C3 cooperative 183 ms (vs. 183 ms for an empty ping at 60 fps), native 200 ms. The whole body arrives in the first congestion window, in a single round trip, so there is nothing to pay beyond the handshake and one RTT. Threaded mode tells a slightly different story: both clients land at ~183 ms rather than the ~166.5 ms threaded baseline from the latency section — one extra frame at 60 fps. Reading the 10 KB body on the background thread adds a small amount of CPU time that, for this particular network latency and frame rate, is enough to push the thread's completion past a frame boundary, delaying delivery by one `process_frame`. The spread revealed in the five-number summaries in [BENCHMARK.md](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/BENCHMARK.md#small-download-slow-start-control-vs-straddled-iw10) confirms this is a borderline boundary effect rather than a fixed cost: the fastest threaded runs dip to ~166 ms (min 166.4 ms for C3, 166.5 ms for native), one frame below the 183 ms median — on those runs the read finished just early enough to make the earlier frame.

**20 KB crosses IW10, so a fresh connection pays an extra round trip.** Bumping the body just past ~14.6 KB forces the server to stop after the first window and wait for an ACK before sending the rest. On fresh connections that extra round trip shows up as one or two added frames — C3 cooperative rises 183 → 200 ms, native stays at 200 ms (it was already a frame behind), and threaded jumps 183 → 200 ms. **The warm session does not move at all: 50 ms at both 10 KB and 20 KB.** Its window is already far larger than 20 KB, so the entire body still goes out in one round trip. This is the crux of the scenario — the slow-start penalty is a property of _fresh_ connections, and a `Session` erases it.

The five-number summaries show how clean this step is. In cooperative mode the Q1–Q3 spread is under 1 ms at every size, because each time is quantized to a whole number of frames (183.3 ms is 11 frames at 60 fps; 200.0 ms is 12). The slow-start penalty is therefore a discrete jump between frame counts, not an average of scattered samples. The one revealing outlier is c3s_coop at 20 KB: a 50 ms median against a max of 200.0 ms — exactly the fresh-connection cost — consistent with a single run that found no warm connection in the pool and paid the full handshake and slow-start it normally skips.

**400 KB makes the gap dramatic.** A body this large forces a fresh connection up the slow-start ramp over several round trips: C3 cooperative 300 ms, native 333 ms, ~300 ms threaded. The warm session delivers the same 400 KB in **51 ms** — barely more than its 10 KB time — because its window grew past 400 KB many requests ago. Here the session saves ~249 ms over a fresh cooperative connection, all of it handshake and slow-start overhead that never has to happen.

---

## File Download

### Methodology

Stream a body to disk using a 64 KB chunk size (`Options.download_chunk_size`). Median of 25 runs per variant, at 60 fps. A warmup run (not counted) runs before timing begins. Body sizes: 1 MB, 8 MB, 32 MB.

### Results

| Body size | nat_coop | c3_coop | c3s_coop | nat_thr | c3_thr | c3s_thr |
| --------- | -------- | ------- | -------- | ------- | ------ | ------- |
| 1 MB      | 500.1    | 334.0   | 67.6     | 333.1   | 332.5  | 65.6    |
| 8 MB      | 2366.7   | 486.5   | 150.5    | 549.8   | 466.4  | 164.2   |
| 32 MB     | 8799.7   | 984.4   | 534.8    | 1334.6  | 948.5  | 561.5   |

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

In cooperative mode `_update_connection()` runs once per frame (driven by `NOTIFICATION_INTERNAL_PROCESS`), so the node reads at most one chunk per frame. Each chunk is bounded by `download_chunk_size`, which the node passes straight to the client (`set_download_chunk_size()` → `client->set_read_chunk_size()`). The effective bandwidth ceiling is therefore `download_chunk_size × frame_rate`. At 60 fps with 65,536-byte chunks that is ~3.93 MB/s — regardless of how fast the connection actually delivers data. An 8 MB body therefore takes roughly 8 MB / 3.93 MB/s ≈ 2.04 s, which matches the measured 2.37 s closely (the remainder is the request round-trip plus disk writes). Since V-Sync ties the frame rate to the monitor's refresh rate, this ceiling is monitor-dependent: a 144 Hz monitor yields ~9.44 MB/s and a 240 Hz monitor ~15.73 MB/s — in other words, **upgrading your monitor makes native cooperative downloads faster**.

The slowness was first reported in 2019 as [godot#32807](https://github.com/godotengine/godot/issues/32807), but note that the issue documents the _symptom_ (slow downloads), not this mechanism. The maintainers attributed it to the small default `read_chunk_size` and resolved the issue by exposing `download_chunk_size` as a tunable, later raising its default to 64 KiB. That lifts the ceiling but does not remove the one-chunk-per-frame gate — which is the deeper cause, and which the verbatim source above shows is still present in 4.7-stable. (The per-frame structure was correctly identified by a commenter in that thread, but it was never the basis of the fix.) So the claim here rests on the engine source, not on the observed behavior. The one-chunk-per-frame gate was identified while building C3 HTTP Request and filed as [godot#120425](https://github.com/godotengine/godot/issues/120425); at the time of writing a fix PR is pending approval.

**`C3Http` drains all available chunks per frame in cooperative mode.** It reads everything the connection delivers each frame, so its time tracks bandwidth rather than polling cadence — nearly 5× faster than native at 60 fps for an 8 MB body (487 ms vs. 2367 ms), and nearly 9× faster at 32 MB (984 ms vs. 8800 ms). The advantage already shows at 1 MB (334 ms vs. 500 ms): a 1 MB body is ~16 chunks, which at one chunk per frame is ~16 frames of gating that C3 collapses into far fewer. The two clients converge only once a body fits in a frame or two of chunks.

**Threaded mode narrows the gap but does not fully close it.** With `use_threads = true`, both clients poll at OS speed. At 8 MB, C3 threaded (466 ms) and native threaded (550 ms) are within ~84 ms — compared to the ~1,880 ms cooperative gap — but they do not converge. At 32 MB the threaded gap widens to ~386 ms (948 ms vs. 1,335 ms). C3's drain-all-chunks behavior retains a throughput advantage even without the per-frame gate.

**The session is a substantial win at all body sizes.** A warm `Session` connection skips TCP slow-start ramp-up and begins transferring at full window size immediately. The benefit is largest where handshake and slow-start are the dominant cost:

- 1 MB: session ~68 ms vs. fresh ~334 ms — roughly 5× faster
- 8 MB: session ~150 ms vs. fresh ~487 ms — roughly 3× faster
- 32 MB: session ~535 ms vs. fresh ~984 ms — roughly 2× faster

The advantage narrows as body size grows because the actual transfer time increasingly dominates over connection-setup overhead — at 32 MB the two are within a factor of 2 — but the session is faster at every size tested.

---

## Summary

| Scenario                     | `C3Http` (session)                         | `C3Http`                             | `HTTPRequest`                        |
| ---------------------------- | ------------------------------------------ | ------------------------------------ | ------------------------------------ |
| Latency (cooperative)        | ~4–5× lower; eliminates handshake overhead | ~1 frame sooner at any capped rate   | baseline                             |
| Latency (threaded)           | ~35–67 ms                                  | flat ~166 ms; does not rise with cap | flat ~166 ms; does not rise with cap |
| 20 KB download               | no extra RTT; window already past IW10     | +1 RTT past IW10                     | +1 RTT past IW10                     |
| 400 KB download              | ~51 ms                                     | ~300 ms                              | ~333 ms                              |
| 8 MB download (cooperative)  | ~150 ms                                    | ~5× faster than native               | frame-rate-gated throughput ceiling  |
| 8 MB download (threaded)     | ~164 ms                                    | ~84 ms faster than native            | baseline                             |
| 32 MB download (cooperative) | ~535 ms                                    | ~9× faster than native               | frame-rate-gated throughput ceiling  |
| 32 MB download (threaded)    | ~562 ms                                    | ~386 ms faster than native           | baseline                             |

For minimum latency, `Options.session` with a shared `Session` object is the strongest lever — it eliminates handshake and TCP slow-start overhead entirely, cutting round-trip time by ~125 ms per request when the connection is already established. The session advantage holds at every transfer size tested, though it narrows as body size grows and raw throughput dominates over connection-setup time. For large cooperative downloads, `C3Http` is the only option that doesn't hit the per-frame chunk ceiling; `Options.use_threads = true` substantially closes the gap for `HTTPRequest`, but `C3Http` retains a throughput edge even in threaded mode at larger body sizes.
