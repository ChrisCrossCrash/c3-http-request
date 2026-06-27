# C3 HTTP Request for Godot

_Like `HTTPRequest`, but better!_

`C3HTTPRequest` is a lightweight, async HTTP client for Godot 4 that covers nearly everything `HTTPRequest` does — and gets out of your way while doing it. There's no `Node` to instantiate, add to the tree, and free; no `request_completed` signal to connect; and no two-step "did the transfer work, _and_ was the status 2xx?" dance. You `await` a single static call and check one field.

```gdscript
var res := await C3HTTPRequest.request("https://api.example.com/todos/1")
if res.ok:
    print(res.text)
    print(res.json["title"])
else:
    push_error(str(res.error))
```

No node, no signal, no tree — and `res.ok` is a single check that already accounts for transport failures, timeouts, and non-2xx statuses alike.

## Features

- Static `await`-able `request()` callable from any script — no `Node` to add or configure
- Every call returns a typed `Response` object — a single `if not res.ok` check covers transport failures, timeouts, and non-2xx statuses alike
- Per-request `Options`: timeout, body size limit, gzip decompression, redirect control, custom TLS, proxy, and download-to-file
- `request_raw()` companion for sending a raw `PackedByteArray` body (binary payloads) unencoded
- Cancellation token — cancel an in-flight request from another coroutine or signal handler
- Server-Sent Events (SSE) — pass an `on_sse_event` callback to consume a streaming `text/event-stream` response incrementally, with the `Last-Event-ID` cursor and `retry:` backoff surfaced for reconnects
- Download progress — pass an `on_progress` callback to track `(bytes_received, total_bytes)` as the body arrives
- Connection status — pass an `on_status_changed` callback to observe the `HTTPClient` lifecycle (resolving, connecting, requesting, body)
- Automatic gzip decompression when the server sends compressed responses
- Redirect following with a configurable depth limit
- Optional threaded mode — set `use_threads` to poll on a background thread at OS speed instead of once per frame, with callbacks auto-marshaled back to the main thread
- HTTP keep-alive — set `Options.session` to pool and reuse connections across calls to the same host
- Built-in test mock — `C3HTTPRequest.Mock` intercepts all requests in tests without a network, with stubs to configure responses and a call log for assertions

## Comparison with HTTPRequest

| Feature                                 |    C3HTTPRequest    |         HTTPRequest          |
| --------------------------------------- | :-----------------: | :--------------------------: |
| No Node to add or configure             |          ✓          |              —               |
| `await`-able (no signal wiring)         |          ✓          |              —               |
| Single `ok` check (transport + non-2xx) |          ✓          |              —               |
| Decoded `text` body accessor            |          ✓          |              —               |
| Parsed `json` body accessor             |          ✓          |              —               |
| Server-Sent Events (SSE) streaming      |          ✓          |              —               |
| Typed `RequestError` with `Kind`        |          ✓          |   — (integer result code)    |
| Built-in test mock                      |          ✓          |              —               |
| HTTP keep-alive and connection reuse    | ✓ `Options.session` |              —               |
| Cancellation                            |    ✓ Token-based    |     ✓ `cancel_request()`     |
| Timeout                                 |          ✓          |              ✓               |
| Gzip decompression                      |          ✓          |              ✓               |
| Redirect following                      |          ✓          |              ✓               |
| Download to file                        |          ✓          |              ✓               |
| Body size limit                         |          ✓          |              ✓               |
| Custom TLS options                      |          ✓          |              ✓               |
| Binary response body in memory          |          ✓          |              ✓               |
| Raw request body (bytes)                |          ✓          |              ✓               |
| HTTP/HTTPS proxy                        |          ✓          |              ✓               |
| Download progress events                |          ✓          |              ✓               |
| Connection status callback              |          ✓          | ✓ `get_http_client_status()` |
| Threaded requests (off main loop)       |          ✓          |              ✓               |

## Compatibility

Tested on Godot 4.7.x with automated ([GUT](https://github.com/bitwes/Gut)) and manual tests. Manually verified to work back to Godot 4.2.0.

## Installation

Click the "Asset Store" tab at the top of the Godot editor and search for "C3 HTTP Request". Then click "Download" and "Install". The addon will be automatically added to your project, and `C3HTTPRequest` will be available as a global class immediately — no plugin activation required.

Alternatively, download the latest release from [GitHub](https://github.com/ChrisCrossCrash/c3-http-request/releases) and copy the `addons/c3_http_request` folder into your project's `addons/` directory.
