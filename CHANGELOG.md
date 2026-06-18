# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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

[0.2.0]: https://github.com/ChrisCrossCrash/c3-http-request/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ChrisCrossCrash/c3-http-request/releases/tag/v0.1.0
