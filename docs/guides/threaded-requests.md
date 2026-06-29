# Threaded Requests

By default the polling loop yields to the scene tree whenever it has to wait, so it resumes at most once per frame — the same cadence as `HTTPRequest`. Set `Options.use_threads` to `true` to run the loop on a dedicated background thread that polls at OS speed instead, lowering latency for fast endpoints and keeping the main thread free during large or streaming downloads.

```gdscript
var opts := C3Http.Options.new()
opts.use_threads = true

var res := await C3Http.request("https://example.com/large-file", PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
```

## Notes

- **The `await` API is unchanged** — `request()` still returns a `Response` you `await` exactly as before.
- **Callbacks stay main-thread-safe** — `on_sse_event`, `on_progress`, and `on_status_changed` are automatically marshaled back to the main thread, so they may freely touch the scene tree. They are also guaranteed to have all fired by the time the `await` resolves.
- **Cancellation and redirects** work as usual; a redirect chain reuses the same single worker thread.
- **Fallback** — on export templates without thread support (e.g. single-threaded web builds), this transparently falls back to the cooperative per-frame loop.

## When to use it

See [Benchmarks](../benchmarks.md) for quantitative guidance. In summary:

- **Fast endpoints / low latency** — threaded mode removes the per-frame overhead, landing closer to the raw RTT floor.
- **Large downloads** — cooperative mode caps throughput at `chunk_size × fps`; threaded mode drains at full link bandwidth.
- **Concurrent requests** — both modes scale smoothly, but threaded erases the ~2-frame-per-level gap cooperative mode shows.
- **Small responses at an uncapped frame rate** — both modes are equivalent; the difference is below measurement noise.
