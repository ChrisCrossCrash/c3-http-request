# C3 HTTP Request for Godot

_Like `HTTPRequest`, but better!_

`C3HTTPRequest` is a lightweight, async HTTP client for Godot 4 that covers nearly everything `HTTPRequest` does — and gets out of your way while doing it. There's no `Node` to instantiate, add to the tree, and free; no `request_completed` signal to connect; and no two-step "did the transfer work, _and_ was the status 2xx?" dance. You `await` a single static call and check one field.

Here's the same GET request both ways:

<table>
<tr><th><code>HTTPRequest</code></th><th><code>C3HTTPRequest</code></th></tr>
<tr valign="top"><td>

```gdscript
var http := HTTPRequest.new()
add_child(http)
http.request("https://api.example.com/todos/1")
var result: Array = await http.request_completed
http.queue_free()

var code: int = result[0]
var status: int = result[1]
var body: PackedByteArray = result[3]
if code == HTTPRequest.RESULT_SUCCESS and status == 200:
    var text := body.get_string_from_utf8()
    print(text)
    var data: Variant = JSON.parse_string(text)
    if data is Dictionary:
        print(data["title"])
else:
    push_error("Request failed")
```

</td><td>

```gdscript
var res := await C3HTTPRequest.request("https://api.example.com/todos/1")
if res.ok:
    print(res.text)
    print(res.json["title"])
else:
    push_error(str(res.error))
```

</td></tr>
</table>

No node, no signal, no tree — and `res.ok` is a single check that already accounts for transport failures, timeouts, and non-2xx statuses alike. Redirects are followed automatically (up to `Options.max_redirects`), so `res` reflects the final response the chain lands on.

## Features

- Static `await`-able `request()` callable from any script — no `Node` to add or configure
- Every call returns a typed `Response` object — a single `if not res.ok` check covers transport failures, timeouts, and non-2xx statuses alike
- Per-request `Options`: timeout, body size limit, gzip decompression, redirect control, custom TLS, proxy, and download-to-file
- `request_raw()` companion for sending a raw `PackedByteArray` body (binary payloads) unencoded
- Cancellation token — cancel an in-flight request from another coroutine or signal handler
- Server-Sent Events (SSE) — pass an `on_sse_event` callback to consume a streaming `text/event-stream` response incrementally
- Download progress — pass an `on_progress` callback to track `(bytes_received, total_bytes)` as the body arrives
- Connection status — pass an `on_status_changed` callback to observe the `HTTPClient` lifecycle (resolving, connecting, requesting, body)
- Automatic gzip/deflate decompression when the server sends compressed responses
- Redirect following with a configurable depth limit
- Optional threaded mode — set `use_threads` to poll on a background thread at OS speed instead of once per frame, with callbacks auto-marshaled back to the main thread

## Comparison with HTTPRequest

| Feature                                 | C3HTTPRequest |         HTTPRequest          |
| --------------------------------------- | :-----------: | :--------------------------: |
| No Node to add or configure             |       ✓       |              —               |
| `await`-able (no signal wiring)         |       ✓       |              —               |
| Single `ok` check (transport + non-2xx) |       ✓       |              —               |
| Decoded `text` body accessor            |       ✓       |              —               |
| Parsed `json` body accessor             |       ✓       |              —               |
| Server-Sent Events (SSE) streaming      |       ✓       |              —               |
| Typed `RequestError` with `Kind`        |       ✓       |   — (integer result code)    |
| Concurrent requests                     |   Unlimited   |         One per node         |
| Cancellation                            | ✓ Token-based |     ✓ `cancel_request()`     |
| Timeout                                 |       ✓       |              ✓               |
| Gzip/deflate decompression              |     ✓ \*      |              ✓               |
| Redirect following                      |       ✓       |              ✓               |
| Download to file                        |       ✓       |              ✓               |
| Body size limit                         |       ✓       |              ✓               |
| Custom TLS options                      |       ✓       |              ✓               |
| Binary response body in memory          |       ✓       |              ✓               |
| Raw request body (bytes)                |       ✓       |              ✓               |
| HTTP/HTTPS proxy                        |       ✓       |              ✓               |
| Download progress events                |       ✓       |              ✓               |
| Connection status callback              |       ✓       | ✓ `get_http_client_status()` |
| Threaded requests (off main loop)       |       ✓       |              ✓               |

<sub>\* When `Options.download_file` is set, the response body is written to disk as-is — decompression is skipped and the file may contain raw compressed bytes.</sub>

## Benchmarks

Benchmarked on Godot 4.6.2, AMD Ryzen 5 7600, Windows, against a remote API. Reproduce with [`examples/benchmark/`](examples/benchmark/). See [BENCHMARK.md](BENCHMARK.md) for the full analysis and raw output.

**Highlights:**

- **Latency:** In cooperative mode at a capped frame rate, C3HTTPRequest resolves ~1 frame sooner per request (e.g. 183 ms vs 200 ms at 60 fps — a 16.7 ms gap that tracks the frame period exactly). In threaded mode, or uncapped, both clients hit the same ~167 ms network floor. The difference is purely the native node's extra per-frame poll, not faster networking.
- **Downloads:** For large cooperative downloads the gap is structural. An 8 MB body at 60 fps takes ~600 ms with C3HTTPRequest vs ~2367 ms with native (~4×), because the native node reads one chunk per frame — capping throughput at `chunk_size × fps` regardless of available bandwidth — while C3HTTPRequest drains all buffered data each frame. Verified against the Godot 4.6.2 source in [BENCHMARK.md](BENCHMARK.md). With `use_threads = true`, both clients deliver full link bandwidth and are equal (~600 ms). Small responses fit in a frame or two of bandwidth, so the two are equivalent there.
- **Concurrency:** Both clients scale smoothly through 8 simultaneous requests. In cooperative mode native is consistently ~1 frame slower per level (matching the single-request result); in threaded mode the two converge as concurrency rises.

Threaded mode and uncapped runs are RTT- or bandwidth-limited, so the clients are effectively equal there — the cooperative, capped-frame-rate differences above are where C3HTTPRequest's polling model shows an edge. See [BENCHMARK.md](BENCHMARK.md) for the full tables, methodology, and raw output.

## Compatibility

Tested on Godot 4.6.x with automated ([GUT](https://github.com/bitwes/Gut)) and manual tests. Manually verified to work back to Godot 4.2.0.

## Installation

Click the "Asset Store" tab at the top of the Godot editor and search for "C3 HTTP Request". Then click "Download" and "Install". The addon will be automatically added to your project, and `C3HTTPRequest` will be available as a global class immediately — no plugin activation required.

Alternatively, download the latest release from [GitHub](https://github.com/ChrisCrossCrash/c3-http-request/releases) and copy the `addons/c3_http_request` folder into your project's `addons/` directory.

## Quick start

```gdscript
# GET
var res := await C3HTTPRequest.request("https://api.example.com/todos/1")
if not res.ok:
    push_error(str(res.error))
    return
print(res.status)  # 200
print(res.text)    # response body decoded as UTF-8
print(res.json)    # response body parsed as JSON (Variant; null if invalid)
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

| Field     | Type                | Description                                                                                                   |
| --------- | ------------------- | ------------------------------------------------------------------------------------------------------------- |
| `ok`      | `bool`              | `true` when a 2xx status was received. Never affected by body content.                                        |
| `status`  | `int`               | HTTP status code, or `0` on transport failure.                                                                |
| `headers` | `PackedStringArray` | Response headers as `"Name: Value"` strings. Empty on transport failure.                                      |
| `body`    | `PackedByteArray`   | Raw response body bytes. Empty when `Options.download_file` is set or no body was received.                   |
| `text`    | `String`            | `body` decoded as UTF-8. Computed lazily on first access and cached.                                          |
| `json`    | `Variant`           | `body` parsed as JSON. Parsed lazily on first access and cached. `null` (and a pushed error) on invalid JSON. |
| `error`   | `RequestError`      | Error details when `ok` is `false`; `null` otherwise.                                                         |

## Options

| Property              | Type                | Default | Description                                                                                                                                                                      |
| --------------------- | ------------------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `timeout`             | `float`             | `0.0`   | Maximum seconds to wait. `0.0` disables the timeout.                                                                                                                             |
| `body_size_limit`     | `int`               | `-1`    | Maximum response body size in bytes. `-1` is unlimited.                                                                                                                          |
| `download_chunk_size` | `int`               | `65536` | Read buffer size in bytes.                                                                                                                                                       |
| `accept_gzip`         | `bool`              | `true`  | Inject `Accept-Encoding: gzip, deflate` and auto-decompress.                                                                                                                     |
| `max_redirects`       | `int`               | `8`     | Maximum redirects to follow. `0` disables following.                                                                                                                             |
| `use_threads`         | `bool`              | `false` | Run the polling loop on a background thread at OS speed instead of once per frame. Callbacks are auto-marshaled to the main thread. See [Threaded requests](#threaded-requests). |
| `download_file`       | `String`            | `""`    | Path to stream the body to on disk. Empty keeps the body in memory.                                                                                                              |
| `tls_options`         | `TLSOptions`        | `null`  | `null` uses `TLSOptions.client()`. Override for self-signed certificates.                                                                                                        |
| `http_proxy_host`     | `String`            | `""`    | Route plain `http://` requests through this proxy host. Empty = direct HTTP connection.                                                                                          |
| `http_proxy_port`     | `int`               | `-1`    | Port of `http_proxy_host`. Ignored when `http_proxy_host` is empty.                                                                                                              |
| `https_proxy_host`    | `String`            | `""`    | Tunnel `https://` requests through this proxy host. Empty = direct HTTPS connection.                                                                                             |
| `https_proxy_port`    | `int`               | `-1`    | Port of `https_proxy_host`. Ignored when `https_proxy_host` is empty.                                                                                                            |
| `cancellation_token`  | `CancellationToken` | `null`  | Token for cancelling the request. `null` disables cancellation support.                                                                                                          |
| `on_sse_event`        | `Callable`          | empty   | When set, parse a 2xx body as an SSE stream and invoke this per event. See [Server-Sent Events](#server-sent-events-sse).                                                        |
| `on_progress`         | `Callable`          | empty   | When set, invoke `(bytes_received, total_bytes)` per chunk as the body downloads. See [Download progress](#download-progress).                                                   |
| `on_status_changed`   | `Callable`          | empty   | When set, invoke `(status)` each time the `HTTPClient` status changes. See [Connection status](#connection-status).                                                              |

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

Set `Options.on_sse_event` to a `Callable` to consume a streaming `text/event-stream` response. The callback fires once per event — `on_sse_event.call(data, event_type)` — as events arrive, and the same `await` you already use resolves to a final `Response` once the stream closes. No new method, no `Node`, no signal wiring.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_sse_event = func(data: String, event_type: String) -> void:
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

## Download progress

Set `Options.on_progress` to a `Callable` to track a download as it arrives. The callback fires once per chunk — `on_progress.call(bytes_received, total_bytes)` — where `bytes_received` is the cumulative count so far and `total_bytes` is the `Content-Length`, or `-1` when the server doesn't send one (e.g. a chunked response). Compute a percentage only when `total_bytes` is positive.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_progress = func(bytes_received: int, total_bytes: int) -> void:
    if total_bytes > 0:
        print("%d%%" % (bytes_received * 100 / total_bytes))
    else:
        print("%d bytes" % bytes_received)  # length unknown

var res := await C3HTTPRequest.request("https://example.com/large.bin", PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
```

Works for both in-memory and `download_file` downloads. `bytes_received` counts raw bytes off the wire, so it may differ from the final `res.body.size()` when a gzip/deflate body is decompressed after the transfer completes. It has no effect in SSE mode (`on_sse_event`), where the events themselves are the incremental signal.

## Connection status

Set `Options.on_status_changed` to a `Callable` to observe the underlying `HTTPClient` as it advances through its lifecycle — the equivalent of polling the native node's `get_http_client_status()`. The callback fires once per change, `on_status_changed.call(status)`, where `status` is an `HTTPClient.Status` value.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_status_changed = func(status: HTTPClient.Status) -> void:
    print(status)  # HTTPClient.STATUS_CONNECTING, STATUS_REQUESTING, STATUS_BODY, ...

var res := await C3HTTPRequest.request("https://example.com", PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
```

A typical request reports `STATUS_RESOLVING`/`STATUS_CONNECTING` → `STATUS_CONNECTED` → `STATUS_REQUESTING` → `STATUS_BODY`. Notes:

- **Observational only** — the request's outcome still arrives via the returned `Response`; this callback never changes it.
- **Fires in every mode**, including `download_file` and SSE (`on_sse_event`), since it tracks the connection, not the body.
- **Repeats per redirect hop** — each hop opens a fresh connection, so the connect → request → body sequence is emitted again for every hop followed.
- **Best-effort** — a very brief intermediate state may be coalesced, since the status is sampled once per poll.

### Threaded requests

By default the polling loop yields to the scene tree once per frame, so it advances at most once per rendered frame (the same cadence as the native `HTTPRequest` node). Set `Options.use_threads` to `true` to run the loop on a dedicated background thread that polls at OS speed instead — lowering latency for fast endpoints and keeping the main thread free during large or streaming downloads.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.use_threads = true

var res := await C3HTTPRequest.request("https://example.com/large-file", PackedStringArray(), C3HTTPRequest.Method.GET, "", opts)
```

Notes:

- **The `await` API is unchanged** — `request()` still returns a `Response` you `await` exactly as before.
- **Callbacks stay main-thread-safe** — `on_sse_event`, `on_progress`, and `on_status_changed` are automatically marshaled back to the main thread, so they may freely touch the scene tree. They are also guaranteed to have all fired by the time the `await` resolves.
- **Cancellation and redirects** work as usual; a redirect chain reuses the same single worker thread.
- **Fallback** — on export templates without thread support (e.g. single-threaded web builds), this transparently falls back to the cooperative per-frame loop.
