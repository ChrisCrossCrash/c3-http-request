# C3 HTTP Request for Godot

`C3HTTPRequest` is a lightweight nodeless replacement for [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html). It offers significant improvements in ergonomics, performance, and testability.

**[Full documentation](https://chriscrosscrash.github.io/c3-http-request/)**

Here is a complete working example of how to use C3HTTPRequest in a script:

```gdscript
extends Node2D


func _ready() -> void:
	var res := await C3HTTPRequest.request("https://jsonplaceholder.typicode.com/todos/1")
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
- Per-request `Options` that mirror the native `HTTPRequest` node's properties (`use_threads`, `accept_gzip`, etc.), plus additional features
- HTTP keep-alive — set `Options.session` to pool and reuse connections across calls to the same host
- Server-Sent Events (SSE) — pass an `on_sse_event` callback to consume a streaming `text/event-stream` response incrementally, with the `Last-Event-ID` cursor and `retry:` backoff surfaced for reconnects
- Download progress — pass an `on_progress` callback to track `(bytes_received, total_bytes)` as the body arrives
- Cancellation token — cancel an in-flight request from another coroutine or signal handler
- Connection status — pass an `on_status_changed` callback to observe the `HTTPClient` lifecycle (resolving, connecting, requesting, body)
- Built-in test mock — `C3HTTPRequest.Mock` intercepts all requests in tests without a network, with stubs to configure responses and a call log for assertions

## Comparison with HTTPRequest

| Feature                                 | C3HTTPRequest | HTTPRequest |
| --------------------------------------- | :-----------: | :---------: |
| No Node to add or configure             |      ✅       |     ❌      |
| `await`-able (no signal wiring)         |      ✅       |     ❌      |
| Single `ok` check (transport + non-2xx) |      ✅       |     ❌      |
| Decoded `text` body accessor            |      ✅       |     ❌      |
| Parsed `json` body accessor             |      ✅       |     ❌      |
| Server-Sent Events (SSE) streaming      |      ✅       |     ❌      |
| Typed `RequestError` with `Kind`        |      ✅       |     ❌      |
| Built-in test mock                      |      ✅       |     ❌      |
| HTTP keep-alive and connection reuse    |      ✅       |     ❌      |
| Cancellation                            |      ✅       |     ✅      |
| Timeout                                 |      ✅       |     ✅      |
| Gzip decompression                      |      ✅       |     ✅      |
| Redirect following                      |      ✅       |     ✅      |
| Download to file                        |      ✅       |     ✅      |
| Body size limit                         |      ✅       |     ✅      |
| Custom TLS options                      |      ✅       |     ✅      |
| Raw request body (bytes)                |      ✅       |     ✅      |
| HTTP/HTTPS proxy                        |      ✅       |     ✅      |
| Download progress events                |      ✅       |     ✅      |
| Connection status checking              |      ✅       |     ✅      |
| Threaded requests (off main loop)       |      ✅       |     ✅      |

## Compatibility

Tested on Godot 4.7.x with automated ([GUT](https://github.com/bitwes/Gut)) and manual tests. Manually verified to work back to Godot 4.2.0.

## Installation

Click the "Asset Store" tab at the top of the Godot editor and search for "C3 HTTP Request". Then click "Download" and "Install". The addon will be automatically added to your project, and `C3HTTPRequest` will be available as a global class immediately — no plugin activation required.

Alternatively, download the latest release from [GitHub](https://github.com/ChrisCrossCrash/c3-http-request/releases) and copy the `addons/c3_http_request` folder into your project's `addons/` directory.
