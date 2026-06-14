# C3 HTTP Request for Godot

A lightweight, async HTTP client for Godot 4 that requires no scene tree. Call the static `request()` method from anywhere — no node to add, no signal to wire.

```gdscript
var res := await C3HTTPRequest.request("https://api.example.com/todos/1")
if res.ok:
    print(res.text)
else:
    push_error(str(res.error))
```

## Features

- Static `await`-able `request()` callable from any script — no `Node` to add or configure
- Every call returns a typed `Response` object — a single `if not res.ok` check covers transport failures, timeouts, and non-2xx statuses alike
- Per-request `Options`: timeout, body size limit, gzip decompression, redirect control, custom TLS, proxy, and download-to-file
- `request_raw()` companion for sending a raw `PackedByteArray` body (binary payloads) unencoded
- Cancellation token — cancel an in-flight request from another coroutine or signal handler
- Server-Sent Events (SSE) — pass an `on_event` callback to consume a streaming `text/event-stream` response incrementally
- Automatic gzip/deflate decompression when the server sends compressed responses
- Redirect following with a configurable depth limit

## Comparison with HTTPRequest

| Feature                                 | C3HTTPRequest |       HTTPRequest       |
| --------------------------------------- | :-----------: | :---------------------: |
| No Node to add or configure             |       ✓       |            —            |
| `await`-able (no signal wiring)         |       ✓       |            —            |
| Single `ok` check (transport + non-2xx) |       ✓       |            —            |
| Decoded `text` body accessor            |       ✓       |            —            |
| Server-Sent Events (SSE) streaming      |       ✓       |            —            |
| Typed `RequestError` with `Kind`        |       ✓       | — (integer result code) |
| Concurrent requests                     |   Unlimited   |      One per node       |
| Cancellation                            | ✓ Token-based |  ✓ `cancel_request()`   |
| Timeout                                 |       ✓       |            ✓            |
| Gzip/deflate decompression              |     ✓ \*      |            ✓            |
| Redirect following                      |       ✓       |            ✓            |
| Download to file                        |       ✓       |            ✓            |
| Body size limit                         |       ✓       |            ✓            |
| Custom TLS options                      |       ✓       |            ✓            |
| Binary response body in memory          |       ✓       |            ✓            |
| Raw request body (bytes)                |       ✓       |            ✓            |
| HTTP/HTTPS proxy                        |       ✓       |            ✓            |
| Download progress events                |       —       |            ✓            |
| Threaded requests (off main loop)       |       —       |            ✓            |

<sub>\* When `Options.download_file` is set, the response body is written to disk as-is — decompression is skipped and the file may contain raw compressed bytes.</sub>

## Compatibility

Tested on Godot 4.6.x with automated ([GUT](https://github.com/bitwes/Gut)) tests.

## Installation

Download the latest release from GitHub and copy the `addons/c3_http_request-<version>` folder into your project's `addons/` directory. No plugin activation required — `C3HTTPRequest` is available as a global class immediately.

## Quick start

```gdscript
# GET
var res := await C3HTTPRequest.request("https://api.example.com/todos/1")
if not res.ok:
    push_error(str(res.error))
    return
print(res.status)  # 200
print(res.text)    # response body decoded as UTF-8
print(res.body)    # raw response body bytes (PackedByteArray)

# POST with a JSON body and custom headers
var res2 := await C3HTTPRequest.request(
    "https://api.example.com/posts",
    PackedStringArray([
        "Content-Type: application/json",
        "Authorization: Bearer " + token,
    ]),
    C3HTTPRequest.Method.POST,
    '{"title": "hello"}'
)

# POST a raw binary body (sent as-is, not UTF-8 encoded)
var res_raw := await C3HTTPRequest.request_raw(
    "https://api.example.com/upload",
    PackedStringArray(["Content-Type: application/octet-stream"]),
    C3HTTPRequest.Method.POST,
    payload  # a PackedByteArray
)

# Per-request options
var opts := C3HTTPRequest.Options.new()
opts.timeout = 10.0
var res3 := await C3HTTPRequest.request(url, PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
```

## Response

| Field     | Type                | Description                                                                                 |
| --------- | ------------------- | ------------------------------------------------------------------------------------------- |
| `ok`      | `bool`              | `true` when a 2xx status was received. Never affected by body content.                      |
| `status`  | `int`               | HTTP status code, or `0` on transport failure.                                              |
| `headers` | `PackedStringArray` | Response headers as `"Name: Value"` strings. Empty on transport failure.                    |
| `body`    | `PackedByteArray`   | Raw response body bytes. Empty when `Options.download_file` is set or no body was received. |
| `text`    | `String`            | `body` decoded as UTF-8. Computed lazily on first access and cached.                        |
| `error`   | `RequestError`      | Error details when `ok` is `false`; `null` otherwise.                                       |

## Options

| Property              | Type                | Default | Description                                                                                                               |
| --------------------- | ------------------- | ------- | ------------------------------------------------------------------------------------------------------------------------- |
| `timeout`             | `float`             | `0.0`   | Maximum seconds to wait. `0.0` disables the timeout.                                                                      |
| `body_size_limit`     | `int`               | `-1`    | Maximum response body size in bytes. `-1` is unlimited.                                                                   |
| `download_chunk_size` | `int`               | `65536` | Read buffer size in bytes.                                                                                                |
| `accept_gzip`         | `bool`              | `true`  | Inject `Accept-Encoding: gzip, deflate` and auto-decompress.                                                              |
| `max_redirects`       | `int`               | `8`     | Maximum redirects to follow. `0` disables following.                                                                      |
| `download_file`       | `String`            | `""`    | Path to stream the body to on disk. Empty keeps the body in memory.                                                       |
| `tls_options`         | `TLSOptions`        | `null`  | `null` uses `TLSOptions.client()`. Override for self-signed certificates.                                                 |
| `proxy_host`          | `String`            | `""`    | Route http/https requests through a proxy host. Empty = direct connection.                                                |
| `proxy_port`          | `int`               | `-1`    | Port of `proxy_host`. Ignored when `proxy_host` is empty.                                                                 |
| `cancellation_token`  | `CancellationToken` | `null`  | Token for cancelling the request. `null` disables cancellation support.                                                   |
| `on_event`            | `Callable`          | empty   | When set, parse a 2xx body as an SSE stream and invoke this per event. See [Server-Sent Events](#server-sent-events-sse). |

## Error handling

When `res.ok` is `false`, `res.error` is a `RequestError` describing what went wrong. Its `kind` field categorizes the failure:

| `kind`                                       | Meaning                                                                    |
| -------------------------------------------- | -------------------------------------------------------------------------- |
| `RequestError.Kind.TRANSPORT`                | No usable HTTP response (DNS, connection, TLS, or request could not start) |
| `RequestError.Kind.HTTP`                     | A non-2xx status was received                                              |
| `RequestError.Kind.CLIENT`                   | The request was rejected before being sent (e.g. an invalid URL)           |
| `RequestError.Kind.TIMEOUT`                  | No response was received before `Options.timeout` elapsed                  |
| `RequestError.Kind.CANCELLED`                | The request was cancelled via a `CancellationToken`                        |
| `RequestError.Kind.BODY_SIZE_LIMIT_EXCEEDED` | The response body exceeded `Options.body_size_limit`                       |

`str(error)` produces a compact one-line summary: `[transport] Could not connect.` or `[http] status=404 Request failed with status 404.`

## Cancellation

Pass a `CancellationToken` via `Options.cancellation_token` and call `token.cancel()` from anywhere; the polling loop checks the token between iterations and, once cancelled, abandons the request and returns a `Response` with `error.kind == CANCELLED`.

```gdscript
var token := C3HTTPRequest.CancellationToken.new()
var opts := C3HTTPRequest.Options.new()
opts.cancellation_token = token

# In another coroutine or signal handler:
token.cancel()

var res := await C3HTTPRequest.request(url, PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
if not res.ok and res.error.kind == C3HTTPRequest.RequestError.Kind.CANCELLED:
    print("Cancelled.")
```

## Server-Sent Events (SSE)

Set `Options.on_event` to a `Callable` to consume a streaming `text/event-stream` response. The callback fires once per event — `on_event.call(data, event_type)` — as events arrive, and the same `await` you already use resolves to a final `Response` once the stream closes. No new method, no `Node`, no signal wiring.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_event = func(data: String, event_type: String) -> void:
    print("[%s] %s" % [event_type, data])

var res := await C3HTTPRequest.request("https://api.example.com/stream", PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
if not res.ok:
    push_error(str(res.error))  # non-2xx body is collected normally into res.error
```

Behavior while streaming:

- **`data:` and `event:` fields** are surfaced; `event_type` defaults to `"message"` when no `event:` line is present. Multiple `data:` lines in one event are joined with newlines. Comment lines (`:` keep-alives) and events with no `data:` are dropped. The `id:` and `retry:` fields are ignored — this client does not auto-reconnect.
- **Both `\n\n` and `\r\n\r\n` event delimiters** are supported, and a multi-byte UTF-8 character split across network reads is reassembled before decoding.
- **`Response.body` stays empty** on a successful (2xx) stream — the bytes are delivered to your callback, not collected. A **non-2xx** response is collected normally, so `res.ok`, `res.error`, and the error body work as usual.
- **`timeout` becomes an idle timeout** — the maximum seconds _between_ events, not a total deadline — so a healthy long-lived stream is never cut off. A stalled connection still fails with `Kind.TIMEOUT`. Use `0.0` to disable.
- **`accept_gzip` and `download_file` are ignored** while streaming.
- **Stop a stream** by cancelling its `cancellation_token` (see [Cancellation](#cancellation)); the `await` then resolves with `Kind.CANCELLED`.
