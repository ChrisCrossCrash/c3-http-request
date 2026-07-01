# C3Http

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

General-purpose async HTTP client that requires no scene tree.

## Description

Call the static [`request()`](#method-request) from anywhere — no `Node` to add or configure. Every call `await`s a [`C3Http.Response`](C3Http.Response.md) carrying [`ok`](C3Http.Response.md#property-ok) as a single failure check that covers transport errors, timeouts, and non-2xx statuses alike.

## Methods

| Returns | Signature |
|---------|-----------|
| [`C3Http.Response`](C3Http.Response.md) | <code><a href="#method-request">request</a>(url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>, custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a> = PackedStringArray(), method: HTTPClient.Method = 0, request_data: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> = &quot;&quot;, options: <a href="C3Http.Options.md">C3Http.Options</a> = null)</code> |
| [`C3Http.Response`](C3Http.Response.md) | <code><a href="#method-request_raw">request_raw</a>(url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>, custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a> = PackedStringArray(), method: HTTPClient.Method = 2, request_data_raw: <a href="https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html">PackedByteArray</a> = PackedByteArray(), options: <a href="C3Http.Options.md">C3Http.Options</a> = null)</code> |

## Constants

<a id="constant-VERSION"></a>

**<code>VERSION = &quot;v0.4.0&quot;</code>**

The installed version of this addon, e.g. for logging or feature gating.

## Method Descriptions

<a id="method-request"></a>

### <code>request</code>

<pre><code>func request(
    url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>,
    custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a> = PackedStringArray(),
    method: HTTPClient.Method = 0,
    request_data: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> = &quot;&quot;,
    options: <a href="C3Http.Options.md">C3Http.Options</a> = null
) -> <a href="C3Http.Response.md">C3Http.Response</a>:</code></pre>

Sends an HTTP request to `url` and returns the response. 

`custom_headers` are sent alongside any headers injected by [`accept_gzip`](C3Http.Options.md#property-accept_gzip). 

`method` is an `HTTPClient.Method` value; defaults to `METHOD_GET`. 

`request_data` is the raw request body string. 

`options` controls timeout, redirects, and other per-request settings; `null` uses all defaults.

<a id="method-request_raw"></a>

### <code>request_raw</code>

<pre><code>func request_raw(
    url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>,
    custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a> = PackedStringArray(),
    method: HTTPClient.Method = 2,
    request_data_raw: <a href="https://docs.godotengine.org/en/stable/classes/class_packedbytearray.html">PackedByteArray</a> = PackedByteArray(),
    options: <a href="C3Http.Options.md">C3Http.Options</a> = null
) -> <a href="C3Http.Response.md">C3Http.Response</a>:</code></pre>

Sends an HTTP request with a raw byte-array body, like [`request()`](#method-request) but the body is sent as-is without UTF-8 encoding. Use for binary payloads (encoded files, serialized data, custom binary protocols). 

`request_data_raw` is the raw request body bytes. 

`method` defaults to `METHOD_POST`; a raw body is ignored on `METHOD_GET`. 

See [`request()`](#method-request) for the remaining parameters.
