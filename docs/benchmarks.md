# Benchmarks

Benchmarked on Godot 4.7, AMD Ryzen 5 7600, Windows, against a remote API. Reproduce with [`examples/benchmark/`](https://github.com/ChrisCrossCrash/c3-http-request/tree/main/examples/benchmark). See [BENCHMARK.md](https://github.com/ChrisCrossCrash/c3-http-request/blob/main/BENCHMARK.md) on GitHub for the full analysis and raw output.

The results compare two polling modes. **Cooperative** is the default: the polling loop resumes at most once per frame, so the frame rate bounds how often the request can make progress (the same cadence as the native `HTTPRequest` node). **Threaded** (`Options.use_threads = true`) runs the loop on a background thread that polls at OS speed instead. See [Threaded Requests](guides/threaded-requests.md) for details.

## Highlights

- **Latency:** In cooperative mode at a capped frame rate, C3HTTPRequest resolves ~1 frame sooner per request (e.g. 183 ms vs 200 ms at 60 fps — a 16.7 ms gap that tracks the frame period exactly). In threaded mode, or uncapped, both clients land in the same ~163–167 ms network floor. The difference is purely the native node's extra per-frame poll, not faster networking.
- **Downloads:** For large cooperative downloads the gap is structural. An 8 MB body at 60 fps takes ~571 ms with C3HTTPRequest vs ~2367 ms with native (~4×), because the native node reads one chunk per frame — capping throughput at `chunk_size × fps` regardless of available bandwidth — while C3HTTPRequest drains all buffered data each frame. With `use_threads = true`, both clients deliver full link bandwidth and are close (~550–616 ms). Small responses fit in a frame or two of bandwidth, so the two are equivalent there.
- **Concurrency:** Both clients scale smoothly through 8 simultaneous requests. In cooperative mode native trails by ~2 frames per level; threaded mode erases that gap, with the two clients landing within a frame of each other.

Threaded mode and uncapped runs are RTT- or bandwidth-limited, so the clients are effectively equal there — the cooperative, capped-frame-rate differences above are where C3HTTPRequest's polling model shows an edge.
