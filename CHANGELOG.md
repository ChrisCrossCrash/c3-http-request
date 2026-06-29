# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] - TBD

### Added

- `Response.sse_retry_ms` — the server's last SSE `retry:` value (suggested reconnect backoff, in milliseconds), or `-1` when the stream sent none or the response was not an SSE stream.

### Changed

- **Breaking:** the class has been renamed from `C3HTTPRequest` to `C3Http`. All references to `C3HTTPRequest.*` must be updated to `C3Http.*` (e.g. `C3Http.request()`, `C3Http.Options`, `C3Http.Response`).
- **Breaking:** the `Options.on_sse_event` callback now receives a third argument, `last_event_id: String`, so its signature is `on_sse_event.call(data, event_type, last_event_id)`. Existing two-argument sinks must add the parameter. `last_event_id` is the stream's `id:` cursor and persists across events per the SSE spec — an event with no `id:` line still reports the most recent one. Together with `Response.sse_retry_ms`, this gives a caller everything needed to reconnect a dropped stream (echo the id as a `Last-Event-ID` header after waiting the suggested backoff); the client still does not auto-reconnect itself.
- **Breaking:** the addon-specific `Method` enum has been removed in favor of Godot's native `HTTPClient.Method`, mirroring `HTTPRequest` and dropping an internal translation layer. Migrate by replacing `C3HTTPRequest.Method.GET` with `HTTPClient.METHOD_GET`, `C3HTTPRequest.Method.POST` with `HTTPClient.METHOD_POST`, and so on for the remaining methods.

## [0.3.1] - 2026-06-22

### Added

- Runtime warning when `C3HTTPRequest` is instantiated directly, since it carries no instance state — all calls go through the static `request()` and `request_raw()` methods.

### Fixed

- Custom headers are now forwarded selectively across redirect hops in line with standard HTTP client conventions.
- The timeout budget now spans the entire redirect chain rather than restarting on each hop. A `timeout` of 5 s with `max_redirects` of 8 now enforces a 5 s total deadline, not up to 45 s across nine independent clocks.
- The download file is removed when a redirect follow-up fails before the body phase, rather than being left on disk with the redirect response's content.
- The body-read loop now exits immediately when the client leaves `STATUS_BODY` mid-poll, preventing a stale `read_response_body_chunk` call after the connection closes.

## [0.3.0] - 2026-06-21

### Added

- Streaming gzip decompression for `download_file` downloads: gzipped responses are now decoded incrementally through `StreamPeerGZIP` (feed-and-drain) so the file holds decoded content instead of raw compressed bytes, with bounded memory. A per-chunk budget stops a decompression bomb before it balloons memory, and `body_size_limit` now applies to the decompressed bytes written to disk (matching `HTTPRequest`).
- [docs/streaming-decompression.md](docs/streaming-decompression.md) explaining the `StreamPeerGZIP` feed-and-drain loop, back-pressure, and the zip-bomb and no-progress guards.

### Changed

- **Breaking:** automatic `deflate`-encoded response handling is no longer a feature because it simply cannot be done in a way that reliably distinguishes raw-deflate from zlib-wrapped deflate. The client now advertises `Accept-Encoding: gzip` only and never decodes `Content-Encoding: deflate`, sidestepping the [raw-vs-zlib-wrapped ambiguity](https://www.zlib.net/zlib_faq.html#faq39) that silently breaks `HTTPRequest` on raw-deflate responses. You can still request deflate by setting `Accept-Encoding: deflate` yourself — a caller-supplied `Accept-Encoding` header takes precedence over the automatic one — but the client passes the encoded body through untouched, leaving you to decompress it. [Go's `net/http`](https://github.com/golang/go/blob/fd6f414c65e61a51cf12c98ef473957d73f97c44/src/net/http/transport.go#L3003-L3005) makes the same gzip-only choice for the same reason — its source comment reads "Deflate is ambiguous and not as universally supported anyway" and cites the same zlib FAQ linked to above.
- In-memory gzipped bodies are decoded through the same streaming path instead of `PackedByteArray.decompress_dynamic`.
- `download_file` is opened only once the response body starts arriving, so a request that fails while resolving, connecting, or sending never creates or truncates the file. A partial file is removed when a transfer fails after writing has begun (timeout, cancellation, decode error, or size-limit breach).
- Header lookups (`Content-Encoding`, etc.) now match header names case- and whitespace-insensitively.
- Inner-class self-references inside `_Impl` use unqualified names, so vendoring the script as a sub-dependency now needs only the `class_name` line commented out — no other edits.

### Fixed

- A valid in-memory response with an empty gzipped body is no longer misreported as a `BODY_SIZE_LIMIT_EXCEEDED` error. `PackedByteArray.decompress_dynamic` collapses a valid empty body, an over-limit body, and a corrupt body into the same empty return, so an empty gzipped body looked over-limit; the streaming decoder distinguishes the three cases.
- A corrupt in-memory (i.e., non-file download) gzipped body now returns a `TRANSPORT` error instead of silently passing the raw compressed bytes through as the body.

## [0.2.0] - 2026-06-17

### Added

- `Options.use_threads` — run the polling loop on a dedicated background thread that polls at OS speed instead of once per rendered frame, lowering latency for fast endpoints and keeping the main thread free during large or streaming downloads. The public `await` API is unchanged; `on_sse_event`, `on_progress`, and `on_status_changed` callbacks are automatically marshaled back to the main thread, and every callback fires before the `Response` resolves. Falls back to the cooperative loop on export templates without thread support.
- Separate HTTP and HTTPS proxy routing via the new `http_proxy_host` / `http_proxy_port` and `https_proxy_host` / `https_proxy_port` options, so `http://` and `https://` requests can be routed through different proxies (or only one scheme proxied).
- Benchmark suite under `examples/benchmark/` (with a local test server) and [BENCHMARK.md](BENCHMARK.md) documenting cooperative vs. threaded throughput and latency.
- Shared example assets (rotating monkey, on-screen output overlay) reused by both the demo and the benchmark.

### Changed

- **Breaking:** the single `Options.proxy_host` / `Options.proxy_port` pair has been replaced by per-scheme options. Migrate by setting `http_proxy_host` / `http_proxy_port` for `http://` requests and `https_proxy_host` / `https_proxy_port` for `https://` requests. The previous fields applied one proxy to both schemes; set both new pairs to the same host/port to preserve that behavior.

## [0.1.0]

- Initial release: static, async HTTP client for Godot 4 with no scene-tree requirement. `await C3HTTPRequest.request(...)` and check `response.ok` to cover transport failures, timeouts, and non-2xx statuses with a single check. Per-request `Options` for timeout, body size limit, gzip decompression, redirect control, custom TLS, proxy, and download-to-file; cancellation tokens; and SSE, progress, and status-change callbacks.

[0.3.1]: https://github.com/ChrisCrossCrash/c3-http-request/compare/v0.3.0...v0.3.1
[0.3.0]: https://github.com/ChrisCrossCrash/c3-http-request/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ChrisCrossCrash/c3-http-request/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ChrisCrossCrash/c3-http-request/releases/tag/v0.1.0
