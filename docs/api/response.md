# Response

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

The response returned by [`request()`](c3http.md#method-request).

## Properties

| Type | Name | Default |
|------|------|---------|
| `bool` | `ok` | `true` |
| [`RequestError`](requesterror.md) | `error` | `null` |
| `int` | `status` | `0` |
| [`PackedStringArray`](https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html#class-packedstringarray) | `headers` | `PackedStringArray()` |
| [`PackedByteArray`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html#class-packedbytearray) | `body` | `PackedByteArray()` |
| `int` | `sse_retry_ms` | `-1` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) | `text` |  |
| [`Variant`](https://docs.godotengine.org/en/stable/classes/class_variant.html#class-variant) | `json` |  |

## Property Descriptions

### `bool` ok = `true` { #property-ok }

`true` when a response was received with a 2xx status code.

### [`RequestError`](requesterror.md) error = `null` { #property-error }

Error details when [`ok`](#property-ok) is `false`; `null` otherwise.

### `int` status = `0` { #property-status }

HTTP status code, e.g. `200` or `404`. `0` when no HTTP response was received (transport failure).

### [`PackedStringArray`](https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html#class-packedstringarray) headers = `PackedStringArray()` { #property-headers }

Response headers as `"Name: Value"` strings. Empty when no HTTP response was received.

### [`PackedByteArray`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html#class-packedbytearray) body = `PackedByteArray()` { #property-body }

Raw response body bytes. Empty when [`Options.download_file`](options.md#property-download_file) is set or when no body was received. Use [`text`](#property-text) for a decoded string view.

### `int` sse_retry_ms = `-1` { #property-sse_retry_ms }

The server's last SSE `retry:` value, in milliseconds — the backoff it suggests before reconnecting. `-1` when the stream sent no `retry:` line or the response was not an SSE stream. Pair it with the `last_event_id` from [`Options.on_sse_event`](options.md#property-on_sse_event) to reconnect: wait this long, then re-request with a `Last-Event-ID` header set to the last id seen.

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) text { #property-text }

The response body decoded as UTF-8. Computed lazily on first access and cached, so binary responses never pay the decode cost. Returns `""` for an empty or non-UTF-8 body.

### [`Variant`](https://docs.godotengine.org/en/stable/classes/class_variant.html#class-variant) json { #property-json }

The response body parsed as JSON. Parsed lazily on first access and cached, reusing the [`text`](#property-text) decode. On a parse failure this pushes an error (once, at parse time) and returns `null`. Note that a successful parse of a literal JSON `null` body also returns `null`.
