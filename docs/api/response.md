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

<a id="property-ok"></a>

### `bool` ok = `true`

`true` when a response was received with a 2xx status code.

<a id="property-error"></a>

### [`RequestError`](requesterror.md) error = `null`

Error details when [`ok`](#property-ok) is `false`; `null` otherwise.

<a id="property-status"></a>

### `int` status = `0`

HTTP status code, e.g. `200` or `404`. `0` when no HTTP response was received (transport failure).

<a id="property-headers"></a>

### [`PackedStringArray`](https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html#class-packedstringarray) headers = `PackedStringArray()`

Response headers as `"Name: Value"` strings. Empty when no HTTP response was received.

<a id="property-body"></a>

### [`PackedByteArray`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html#class-packedbytearray) body = `PackedByteArray()`

Raw response body bytes. Empty when [`Options.download_file`](options.md#property-download_file) is set or when no body was received. Use [`text`](#property-text) for a decoded string view.

<a id="property-sse_retry_ms"></a>

### `int` sse_retry_ms = `-1`

The server's last SSE `retry:` value, in milliseconds — the backoff it suggests before reconnecting. `-1` when the stream sent no `retry:` line or the response was not an SSE stream. Pair it with the `last_event_id` from [`Options.on_sse_event`](options.md#property-on_sse_event) to reconnect: wait this long, then re-request with a `Last-Event-ID` header set to the last id seen.

<a id="property-text"></a>

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) text

The response body decoded as UTF-8. Computed lazily on first access and cached, so binary responses never pay the decode cost. Returns `""` for an empty or non-UTF-8 body.

<a id="property-json"></a>

### [`Variant`](https://docs.godotengine.org/en/stable/classes/class_variant.html#class-variant) json

The response body parsed as JSON. Parsed lazily on first access and cached, reusing the [`text`](#property-text) decode. On a parse failure this pushes an error (once, at parse time) and returns `null`. Note that a successful parse of a literal JSON `null` body also returns `null`.
