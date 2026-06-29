# C3 HTTP Request (C3Http)

`C3Http` is a lightweight nodeless replacement for [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html). It offers significant improvements in ergonomics, performance, and testability.

**[Full documentation](https://chriscrosscrash.github.io/c3-http-request/)**

Here is a complete working example of how to use `C3Http` in a script:

```gdscript
extends Node2D


func _ready() -> void:
	var res := await C3Http.request("https://jsonplaceholder.typicode.com/todos/1")
	if res.ok:
		print(res.body.get_string_from_utf8())  # .body is PackedStringArray
		print(res.text)                         # .text is String
		print(res.json["title"])                # .json is Variant
	else:
		print(res.error)         # "[http] status=404 Request failed with status 404."
		print(res.error.status)  # 404
```

## Features

- Static `await`-able `request()` callable from any script — no `Node` to add or configure
- Every call returns a typed `Response` object — a single `if not res.ok` check covers transport failures, timeouts, and non-2xx statuses alike
- Per-request `Options` that mirror `HTTPRequest`'s properties (`use_threads`, `accept_gzip`, etc.), plus additional features
- HTTP keep-alive — set `Options.session` to pool and reuse connections across calls to the same host
- Server-Sent Events (SSE) — pass an `on_sse_event` callback to consume a streaming `text/event-stream` response incrementally, with the `Last-Event-ID` cursor and `retry:` backoff surfaced for reconnects
- Download progress — pass an `on_progress` callback to track `(bytes_received, total_bytes)` as the body arrives
- Cancellation token — cancel an in-flight request from another coroutine or signal handler
- Connection status — pass an `on_status_changed` callback to observe the `HTTPClient` lifecycle (resolving, connecting, requesting, body)
- Built-in test mock — `C3Http.Mock` intercepts all requests in tests without a network, with stubs to configure responses and a call log for assertions

## Comparison with HTTPRequest

| Feature                                 | `C3Http` | `HTTPRequest` |
| --------------------------------------- | :------: | :-----------: |
| No Node to add or configure             |    ✅    |      ❌       |
| `await`-able (no signal wiring)         |    ✅    |      ❌       |
| Single `ok` check (transport + non-2xx) |    ✅    |      ❌       |
| Decoded `text` body accessor            |    ✅    |      ❌       |
| Parsed `json` body accessor             |    ✅    |      ❌       |
| Server-Sent Events (SSE) streaming      |    ✅    |      ❌       |
| Typed `RequestError` with `Kind`        |    ✅    |      ❌       |
| Built-in test mock                      |    ✅    |      ❌       |
| HTTP keep-alive and connection reuse    |    ✅    |      ❌       |
| Cancellation                            |    ✅    |      ✅       |
| Timeout                                 |    ✅    |      ✅       |
| Gzip decompression                      |    ✅    |      ✅       |
| Redirect following                      |    ✅    |      ✅       |
| Download to file                        |    ✅    |      ✅       |
| Body size limit                         |    ✅    |      ✅       |
| Custom TLS options                      |    ✅    |      ✅       |
| Raw request body (bytes)                |    ✅    |      ✅       |
| HTTP/HTTPS proxy                        |    ✅    |      ✅       |
| Download progress events                |    ✅    |      ✅       |
| Connection status checking              |    ✅    |      ✅       |
| Threaded requests (off main loop)       |    ✅    |      ✅       |

## Benchmarks

A benchmark analysis was performed using Godot 4.7 on Windows 11 against a remote API. The benchmark scene can be found in [`examples/benchmark/`](examples/benchmark/). The raw results can be found in [`BENCHMARK.md`](BENCHMARK.md), and [docs/benchmarks.md](docs/benchmarks.md) has the full analysis.

**Highlights:**

- **`C3Http` excels at large downloads:** In its default `use_threads = false` mode, `HTTPRequest` reads exactly one chunk per frame, capping throughput at `download_chunk_size × frame_rate` (~3.93 MB/s at 60 fps with 64 KB chunks) no matter how fast the link is. `C3Http` drains every available chunk each frame, so its time tracks bandwidth instead — ~5× faster at 8 MB (487 ms vs 2367 ms) and ~9× faster at 32 MB (984 ms vs 8800 ms).
- **Sessions (keep-alive) are the strongest lever:** With `C3Http`, passing a shared `Session` via `Options.session` reuses a warm TLS/TCP connection, eliminating ~125 ms of handshake and TCP slow-start per request: single-request latency drops from ~162 ms to ~34 ms, and a 400 KB download from ~300 ms to ~51 ms. Native `HTTPRequest` has no equivalent.
- **Latency: `C3Http` is ~1 frame faster when `use_threads = false`:** With `use_threads = false` (the default for both clients) at any capped frame rate, `C3Http` resolves one frame earlier than native (e.g. 183 ms vs 200 ms at 60 fps) because when the underlying `HTTPClient`'s status transitions (e.g. from requesting to reading the body after headers arrive), `C3Http` re-reads the client status in the same loop iteration rather than waiting for the next frame.

## Compatibility

Tested on Godot 4.7.x with automated ([GUT](https://github.com/bitwes/Gut)) and manual tests. Manually verified to work back to Godot 4.2.0.

## Installation

Click the "Asset Store" tab at the top of the Godot editor and search for "C3 HTTP Request". Then click "Download" and "Install". The addon will be automatically added to your project, and `C3Http` will be available as a global class immediately — no plugin activation required.

Alternatively, download the latest release from [GitHub](https://github.com/ChrisCrossCrash/c3-http-request/releases) and copy the `addons/c3_http_request` folder into your project's `addons/` directory.

## Quick start

```gdscript
# GET
var res := await C3Http.request("https://api.example.com/todos/1")
if not res.ok:
    push_error(str(res.error))
    return
print(res.status)  # 200
print(res.text)    # response body decoded as UTF-8
print(res.json)    # response body parsed as JSON (Variant; null if invalid)
print(res.body)    # raw response body bytes (PackedByteArray)

# POST with a JSON body and custom headers
var res2 := await C3Http.request(
    "https://api.example.com/posts",
    PackedStringArray([
        "Content-Type: application/json",
        "Authorization: Bearer " + token,
    ]),
    HTTPClient.METHOD_POST,
    '{"title": "hello"}'
)

# POST a raw binary body (sent as-is, not UTF-8 encoded)
var res_raw := await C3Http.request_raw(
    "https://api.example.com/upload",
    PackedStringArray(["Content-Type: application/octet-stream"]),
    HTTPClient.METHOD_POST,
    payload  # a PackedByteArray
)

# Per-request options
var opts := C3Http.Options.new()
opts.timeout = 10.0
var res3 := await C3Http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
```

## Response

| Field          | Type                | Description                                                                                                                         |
| -------------- | ------------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `ok`           | `bool`              | `true` when a 2xx status was received. Never affected by body content.                                                              |
| `status`       | `int`               | HTTP status code, or `0` on transport failure.                                                                                      |
| `headers`      | `PackedStringArray` | Response headers as `"Name: Value"` strings. Empty on transport failure.                                                            |
| `body`         | `PackedByteArray`   | Raw response body bytes. Empty when `Options.download_file` is set or no body was received.                                         |
| `text`         | `String`            | `body` decoded as UTF-8. Computed lazily on first access and cached.                                                                |
| `json`         | `Variant`           | `body` parsed as JSON. Parsed lazily on first access and cached. `null` (and a pushed error) on invalid JSON.                       |
| `error`        | `RequestError`      | Error details when `ok` is `false`; `null` otherwise.                                                                               |
| `sse_retry_ms` | `int`               | Server's last SSE `retry:` value (reconnect backoff, ms), or `-1` if none / not an SSE stream. See [SSE guide](docs/guides/sse.md). |

See the [Response reference](docs/reference/response.md) for full details.

## Options

| Property              | Type                | Default | Description                                                                                                                                                                                                                            |
| --------------------- | ------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `timeout`             | `float`             | `0.0`   | Maximum seconds to wait. `0.0` disables the timeout.                                                                                                                                                                                   |
| `body_size_limit`     | `int`               | `-1`    | Maximum response body size in bytes. `-1` is unlimited.                                                                                                                                                                                |
| `download_chunk_size` | `int`               | `65536` | Read buffer size in bytes.                                                                                                                                                                                                             |
| `accept_gzip`         | `bool`              | `true`  | Inject `Accept-Encoding: gzip` and auto-decompress. Gzip only — deflate is intentionally unsupported (its raw-vs-zlib ambiguity makes it unreliable).                                                                                  |
| `max_redirects`       | `int`               | `8`     | Maximum redirects to follow. `0` disables following.                                                                                                                                                                                   |
| `use_threads`         | `bool`              | `false` | Run the polling loop on a background thread at OS speed instead of once per frame. Callbacks are auto-marshaled to the main thread. See [Threaded requests](docs/guides/threaded-requests.md).                                         |
| `download_file`       | `String`            | `""`    | Path to stream the body to on disk. Empty keeps the body in memory.                                                                                                                                                                    |
| `tls_options`         | `TLSOptions`        | `null`  | `null` uses `TLSOptions.client()`. Override for self-signed certificates.                                                                                                                                                              |
| `http_proxy_host`     | `String`            | `""`    | Route plain `http://` requests through this proxy host. Empty = direct HTTP connection.                                                                                                                                                |
| `http_proxy_port`     | `int`               | `-1`    | Port of `http_proxy_host`. Ignored when `http_proxy_host` is empty.                                                                                                                                                                    |
| `https_proxy_host`    | `String`            | `""`    | Tunnel `https://` requests through this proxy host. Empty = direct HTTPS connection.                                                                                                                                                   |
| `https_proxy_port`    | `int`               | `-1`    | Port of `https_proxy_host`. Ignored when `https_proxy_host` is empty.                                                                                                                                                                  |
| `cancellation_token`  | `CancellationToken` | `null`  | Token for cancelling the request. `null` disables cancellation support. See [Cancellation](docs/guides/cancellation.md).                                                                                                               |
| `on_sse_event`        | `Callable`          | empty   | When set, parse a 2xx body as an SSE stream and invoke this per event. See [Server-Sent Events](docs/guides/sse.md).                                                                                                                   |
| `on_progress`         | `Callable`          | empty   | When set, invoke `(bytes_received, total_bytes)` per chunk as the body downloads. `total_bytes` is `-1` when the server sends no `Content-Length` (e.g. chunked responses). See [Download progress](docs/guides/download-progress.md). |
| `on_status_changed`   | `Callable`          | empty   | When set, invoke `(status)` each time the `HTTPClient` status changes. See [Connection status](docs/guides/connection-status.md).                                                                                                      |
| `session`             | `Session`           | `null`  | Connection pool for HTTP keep-alive reuse. `null` opens a fresh connection per call. See [Sessions (Keep-Alive)](docs/guides/sessions.md).                                                                                             |

See the [Options reference](docs/reference/options.md) for full details.

## Error handling

When `res.ok` is `false`, `res.error` is a `RequestError` describing what went wrong. Its `kind` field categorizes the failure:

| `kind`                                       | Meaning                                                                    |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| `RequestError.Kind.TRANSPORT`                | No usable HTTP response (DNS, connection, TLS, or request could not start) |
| `RequestError.Kind.HTTP`                     | A non-2xx status was received                                              |
| `RequestError.Kind.CLIENT`                   | The request was rejected before being sent (e.g. an invalid argument)      |
| `RequestError.Kind.TIMEOUT`                  | No response was received before `Options.timeout` elapsed                  |
| `RequestError.Kind.CANCELLED`                | The request was cancelled via a `CancellationToken`                        |
| `RequestError.Kind.BODY_SIZE_LIMIT_EXCEEDED` | The response body exceeded `Options.body_size_limit`                       |

`str(error)` produces a compact one-line summary: `[transport] Could not connect.` or `[http] status=404 Request failed with status 404.`

See the [Errors reference](docs/reference/errors.md) for full details.

## Cancellation

Pass a `CancellationToken` via `Options.cancellation_token` and call `token.cancel()` from anywhere to abandon an in-flight request. The polling loop checks the token between iterations and returns a `Response` with `error.kind == CANCELLED`.

See the [Cancellation guide](docs/guides/cancellation.md) for usage and examples.

## Server-Sent Events (SSE)

Set `Options.on_sse_event` to a `Callable` to consume a streaming `text/event-stream` response. The callback fires once per event as events arrive, and the `await` resolves to a final `Response` once the stream closes. `Response.sse_retry_ms` surfaces the server's `retry:` backoff for reconnects.

See the [SSE guide](docs/guides/sse.md) for full details, including reconnect patterns.

## Download progress

Set `Options.on_progress` to a `Callable` to track a download as it arrives. The callback fires once per chunk — `on_progress.call(bytes_received, total_bytes)` — where `total_bytes` is the `Content-Length` or `-1` when the server doesn't send one.

See the [Download progress guide](docs/guides/download-progress.md) for usage and examples.

## Connection status

Set `Options.on_status_changed` to a `Callable` to observe the underlying `HTTPClient` as it advances through its lifecycle — the equivalent of `HTTPRequest`'s `get_http_client_status()`. The callback fires once per change with an `HTTPClient.Status` value.

See the [Connection status guide](docs/guides/connection-status.md) for usage and examples.

## Threaded requests

By default the polling loop yields to the scene tree once per frame (the same cadence as `HTTPRequest`). Set `Options.use_threads` to `true` to run the loop on a dedicated background thread that polls at OS speed — lowering latency for fast endpoints and keeping the main thread free during large or streaming downloads. The `await` API is unchanged; callbacks are auto-marshaled back to the main thread.

See the [Threaded requests guide](docs/guides/threaded-requests.md) for details and caveats.

## Sessions (Keep-Alive)

Set `Options.session` to a `Session` object to pool and reuse connections across calls to the same host, skipping the TCP/TLS handshake on subsequent requests. `Session` exposes `max_connections_per_host` (default `6`) and `idle_timeout` (default `60.0` seconds). Call `session.close()` to release all pooled connections early.

See the [Sessions guide](docs/guides/sessions.md) for usage and examples.

## Testing

`C3Http.Mock` intercepts all `request()` calls in tests without touching the network. Install it in `before_each` and uninstall in `after_each`; register canned responses with `mock.stub()` and assert outgoing calls via `mock.calls` / `mock.call_count` / `mock.last_call`.

See the [Testing guide](docs/guides/testing.md) for full usage, including stubbing and call assertions.
