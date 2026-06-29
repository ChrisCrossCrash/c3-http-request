# C3Http

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

General-purpose async HTTP client that requires no scene tree.

Call the static [`request()`](#method-request) from anywhere — no [`Node`](https://docs.godotengine.org/en/stable/classes/class_node.html#class-node) to add or configure. Every call `await`s a [`Response`](response.md) carrying [`Response.ok`](response.md#property-ok) as a single failure check that covers transport errors, timeouts, and non-2xx statuses alike.

## Methods

| Returns | Signature |
|---------|-----------|
| [`Response`](response.md) | [`request`](#method-request)`(url: String, custom_headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = 0, request_data: String = "", options: Options = null) static` |
| [`Response`](response.md) | [`request_raw`](#method-request_raw)`(url: String, custom_headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = 2, request_data_raw: PackedByteArray = PackedByteArray(), options: Options = null) static` |

## Constants

**`VERSION` = `"v0.3.1"`**

The installed version of this addon, e.g. for logging or feature gating.

## Method Descriptions

### [`Response`](response.md) `request(url: String, custom_headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = 0, request_data: String = "", options: Options = null) static` { #method-request }

Sends an HTTP request to `url` and returns the response.

`custom_headers` are sent alongside any headers injected by [`Options.accept_gzip`](options.md#property-accept_gzip).

`method` is an `HTTPClient.Method` value; defaults to `METHOD_GET`.

`request_data` is the raw request body string.

`options` controls timeout, redirects, and other per-request settings; `null` uses all defaults.

### [`Response`](response.md) `request_raw(url: String, custom_headers: PackedStringArray = PackedStringArray(), method: HTTPClient.Method = 2, request_data_raw: PackedByteArray = PackedByteArray(), options: Options = null) static` { #method-request_raw }

Sends an HTTP request with a raw byte-array body, like [`request()`](#method-request) but the body is sent as-is without UTF-8 encoding. Use for binary payloads (encoded files, serialized data, custom binary protocols).

`request_data_raw` is the raw request body bytes.

`method` defaults to `METHOD_POST`; a raw body is ignored on `METHOD_GET`.

See [`request()`](#method-request) for the remaining parameters.
