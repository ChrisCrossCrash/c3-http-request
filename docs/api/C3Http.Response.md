# C3Http.Response

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

The response returned by [`request()`](C3Http.md#method-request).

## Properties

| Type | Name | Default |
|------|------|---------|
| [`bool`](https://docs.godotengine.org/en/stable/classes/class_bool.html) | [`ok`](#property-ok) | `true` |
| [`C3Http.RequestError`](C3Http.RequestError.md) | [`error`](#property-error) | `null` |
| [`int`](https://docs.godotengine.org/en/stable/classes/class_int.html) | [`status`](#property-status) | `0` |
| [`PackedStringArray`](https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html) | [`headers`](#property-headers) | `PackedStringArray()` |
| [`PackedByteArray`](https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html) | [`body`](#property-body) | `PackedByteArray()` |
| [`int`](https://docs.godotengine.org/en/stable/classes/class_int.html) | [`sse_retry_ms`](#property-sse_retry_ms) | `-1` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html) | [`text`](#property-text) |  |
| [`Variant`](https://docs.godotengine.org/en/stable/classes/class_variant.html) | [`json`](#property-json) |  |

## Property Descriptions

<a id="property-ok"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a> ok = true</code>

`true` when a response was received with a 2xx status code.

<a id="property-error"></a>

### <code><a href="C3Http.RequestError.md">C3Http.RequestError</a> error = null</code>

Error details when [`ok`](#property-ok) is `false`; `null` otherwise.

<a id="property-status"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> status = 0</code>

HTTP status code, e.g. `200` or `404`. `0` when no HTTP response was received (transport failure).

<a id="property-headers"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a> headers = PackedStringArray()</code>

Response headers as `"Name: Value"` strings. Empty when no HTTP response was received.

<a id="property-body"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html">PackedByteArray</a> body = PackedByteArray()</code>

Raw response body bytes. Empty when [`download_file`](C3Http.Options.md#property-download_file) is set or when no body was received. Use [`text`](#property-text) for a decoded string view.

<a id="property-sse_retry_ms"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> sse_retry_ms = -1</code>

The server's last SSE `retry:` value, in milliseconds — the backoff it suggests before reconnecting. `-1` when the stream sent no `retry:` line or the response was not an SSE stream. Pair it with the `last_event_id` from [`on_sse_event`](C3Http.Options.md#property-on_sse_event) to reconnect: wait this long, then re-request with a `Last-Event-ID` header set to the last id seen.

<a id="property-text"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> text</code>

The response body decoded as UTF-8. Computed lazily on first access and cached, so binary responses never pay the decode cost. Returns `""` for an empty or non-UTF-8 body.

<a id="property-json"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_variant.html">Variant</a> json</code>

The response body parsed as JSON. Parsed lazily on first access and cached, reusing the [`text`](#property-text) decode. On a parse failure this pushes an error (once, at parse time) and returns `null`. Note that a successful parse of a literal JSON `null` body also returns `null`.
