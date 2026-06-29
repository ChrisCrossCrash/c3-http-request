# Options

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

Per-request configuration. Defaults match [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest) node defaults.

## Properties

| Type | Name | Default |
|------|------|---------|
| `float` | `timeout` | `0.0` |
| `int` | `body_size_limit` | `-1` |
| `int` | `download_chunk_size` | `65536` |
| `bool` | `accept_gzip` | `true` |
| `int` | `max_redirects` | `8` |
| `bool` | `use_threads` | `false` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) | `download_file` | `""` |
| [`TLSOptions`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) | `tls_options` | `null` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) | `http_proxy_host` | `""` |
| `int` | `http_proxy_port` | `-1` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) | `https_proxy_host` | `""` |
| `int` | `https_proxy_port` | `-1` |
| [`CancellationToken`](cancellationtoken.md) | `cancellation_token` | `null` |
| [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) | `on_sse_event` | `Callable()` |
| [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) | `on_progress` | `Callable()` |
| [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) | `on_status_changed` | `Callable()` |
| [`Session`](session.md) | `session` | `null` |

## Property Descriptions

### `float` timeout = `0.0` { #property-timeout }

Maximum seconds to wait for a response. `0.0` disables the timeout.

### `int` body_size_limit = `-1` { #property-body_size_limit }

Maximum response body size in bytes. `-1` is unlimited.

### `int` download_chunk_size = `65536` { #property-download_chunk_size }

Size in bytes of the buffer used to read the response body off the socket (via [`HTTPClient.set_read_chunk_size()`](https://docs.godotengine.org/en/stable/classes/class_httpclient.html#class-httpclient)). These are raw, as-received bytes — *before* decompression — so for a compressed response this bounds the compressed read, not the decoded output. Lower values reduce peak memory use during large downloads.

### `bool` accept_gzip = `true` { #property-accept_gzip }

When `true`, sends `Accept-Encoding: gzip` and decompresses the response body automatically. Applies to [`download_file`](#property-download_file) downloads too: compressed bytes are streamed through the decompressor straight to disk, so the file holds the decoded content.
When `false`, no `Accept-Encoding` header is sent and no decompression is performed (matching [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest)). Note this is *not* the same as refusing compression: sending no `Accept-Encoding` tells the server any encoding is acceptable, so it may still return a `Content-Encoding: gzip` body. You then receive it exactly as sent — the raw, still-compressed bytes, for you to decode. To actually forbid compression, set your own `Accept-Encoding: identity` in `custom_headers`. A caller-supplied `Accept-Encoding` always takes precedence and suppresses the automatic one.
Only `gzip` is requested and decoded — never `deflate`, which is where this differs from [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest) ([`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest) advertises both). HTTP `deflate` is ambiguous: the spec says it is zlib-wrapped (RFC 1950), but many servers send raw deflate (RFC 1951) instead, and the two cannot be told apart reliably. Native [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html#class-httprequest) assumes zlib-wrapped and fails to decode raw-deflate responses — a rare bug that is hard to trace because it only surfaces against the uncommon servers that send raw deflate. C3Http sidesteps it by never requesting deflate at all; gzip is near-universal and brotli covers the rest, so deflate is effectively a rounding error on the modern web. If you genuinely need it, request it via `custom_headers` and decode the bytes yourself.

### `int` max_redirects = `8` { #property-max_redirects }

Maximum number of redirects to follow. `0` disables following.

### `bool` use_threads = `false` { #property-use_threads }

When `true`, the polling loop runs on a dedicated background thread that polls at OS speed rather than once per rendered frame, lowering latency for fast endpoints and large or streaming downloads. The public `await` API is unchanged, and this falls back to the cooperative loop on export templates without thread support.
The [`on_sse_event`](#property-on_sse_event), [`on_progress`](#property-on_progress), and [`on_status_changed`](#property-on_status_changed) callbacks are automatically marshaled back to the main thread, so they stay safe to touch the scene tree. Marshaling uses `call_deferred`, which would normally let a callback run on a *later* frame — but this client drains all pending callbacks before the `await` resolves. So any state a callback mutates is fully settled by the time the response comes back, and the result is identical whether or not threading is on:


```gdscript
# Count the connection-status changes via a callback.
var status_changes: Array[int] = []
var opts := C3Http.Options.new()
opts.use_threads = true
opts.on_status_changed = func(status: HTTPClient.Status) -> void:
    status_changes.append(status)

await C3Http.request("https://example.com",
    PackedStringArray(), HTTPClient.METHOD_GET, "", opts)

# Every status change has already fired — none is still queued for a later
# frame — so this prints the same count with use_threads true or false.
print(status_changes.size())
```

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) download_file = `""` { #property-download_file }

Path to write the response body to on disk. When non-empty, [`Response.body`](response.md#property-body) is empty and the data is in the file. The file is created only once the response body starts arriving, so a request that fails while resolving, connecting, or sending leaves the path untouched — never truncating an existing file it will not fill. If the transfer fails after writing has begun (timeout, cancellation, a decode error, or exceeding [`body_size_limit`](#property-body_size_limit)), the partial file is removed.

### [`TLSOptions`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) tls_options = `null` { #property-tls_options }

TLS options for HTTPS connections. `null` uses [`TLSOptions.client()`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) (validates the server certificate). Override with [`TLSOptions.client_unsafe()`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) for self-signed certificates.
If you set a [`session`](#property-session), leaving this `null` (the default) needs no extra thought — pooling just works. But if you *do* set a custom [`TLSOptions`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions), you must reuse the same instance for every call that shares the session: connections are pooled by this object's identity, so a newly constructed [`TLSOptions`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) per request produces a different pool key each time and silently defeats connection reuse.

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) http_proxy_host = `""` { #property-http_proxy_host }

Host of an HTTP proxy to route plain `http://` requests through. Empty means a direct connection for HTTP. Has no effect on `https://` requests — set [`https_proxy_host`](#property-https_proxy_host) for those.

### `int` http_proxy_port = `-1` { #property-http_proxy_port }

Port of the proxy named by [`http_proxy_host`](#property-http_proxy_host). Ignored when [`http_proxy_host`](#property-http_proxy_host) is empty.

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) https_proxy_host = `""` { #property-https_proxy_host }

Host of an HTTPS proxy to tunnel `https://` requests through. Empty means a direct connection for HTTPS. Has no effect on `http://` requests — set [`http_proxy_host`](#property-http_proxy_host) for those.

### `int` https_proxy_port = `-1` { #property-https_proxy_port }

Port of the proxy named by [`https_proxy_host`](#property-https_proxy_host). Ignored when [`https_proxy_host`](#property-https_proxy_host) is empty.

### [`CancellationToken`](cancellationtoken.md) cancellation_token = `null` { #property-cancellation_token }

Token for cancelling this request from another coroutine or signal handler. `null` means no cancellation support.

### [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) on_sse_event = `Callable()` { #property-on_sse_event }

Optional [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) invoked once per Server-Sent Event as the response streams in, as `on_sse_event.call(data: String, event_type: String, last_event_id: String)`. `last_event_id` is the stream's current `id:` cursor: it persists across events per the SSE spec, so an event with no `id:` line still reports the most recent one (echo it as a `Last-Event-ID` header to resume after a drop; see also [`Response.sse_retry_ms`](response.md#property-sse_retry_ms) for the suggested backoff). When set, a 2xx response body is parsed as an SSE stream rather than collected: [`Response.body`](response.md#property-body) stays empty and [`request()`](c3http.md#method-request) resolves only when the stream closes (use [`cancellation_token`](#property-cancellation_token) to stop it early). While streaming, [`accept_gzip`](#property-accept_gzip) and [`download_file`](#property-download_file) are ignored, and [`timeout`](#property-timeout) becomes an idle timeout (maximum seconds between events) rather than a total deadline. A non-2xx response is collected normally, so [`Response.ok`](response.md#property-ok), [`Response.error`](response.md#property-error), and the error body still work as usual. Both LF (`\n\n`) and CRLF (`\r\n\r\n`) event delimiters are supported.

### [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) on_progress = `Callable()` { #property-on_progress }

Optional [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) invoked as the response body downloads, as `on_progress.call(bytes_received: int, total_bytes: int)`. `bytes_received` is the cumulative byte count; `total_bytes` is the `Content-Length`, or `-1` when unknown (e.g. a chunked response). Fires once per non-empty chunk for both in-memory and [`download_file`](#property-download_file) downloads. Has no effect in SSE mode (see [`on_sse_event`](#property-on_sse_event)), where [`on_sse_event`](#property-on_sse_event) is the incremental signal instead.

### [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) on_status_changed = `Callable()` { #property-on_status_changed }

Optional [`Callable`](https://docs.godotengine.org/en/stable/classes/class_callable.html#class-callable) invoked as the underlying connection advances, as `on_status_changed.call(status: HTTPClient.Status)` — one of `STATUS_RESOLVING`, `STATUS_CONNECTING`, `STATUS_CONNECTED`, `STATUS_REQUESTING`, `STATUS_BODY`, etc. Fires once per change, in every mode (including SSE), and repeats the cycle for each hop when redirects are followed. Purely observational: the request's outcome is still reported via the returned [`Response`](response.md). Very brief intermediate states may be coalesced.

### [`Session`](session.md) session = `null` { #property-session }

Optional [`Session`](session.md) for HTTP keep-alive connection reuse. When set, idle connections to the same host are pooled and reused across calls, reducing latency for repeated requests to the same endpoint.
`null` (the default) disables pooling: each call opens a fresh connection. Create a [`Session`](session.md) once and share it across calls that target the same set of hosts.
If you also set a custom [`tls_options`](#property-tls_options), share that one [`TLSOptions`](https://docs.godotengine.org/en/stable/classes/class_tlsoptions.html#class-tlsoptions) instance across the pooled calls too, or connection reuse is defeated. The default `null` [`tls_options`](#property-tls_options) needs no such care. See [`tls_options`](#property-tls_options).
