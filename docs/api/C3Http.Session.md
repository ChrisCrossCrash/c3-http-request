# C3Http.Session

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

Holds a pool of idle HTTP connections for reuse across calls, reducing the TCP and TLS handshake cost for repeated requests to the same host.

## Description

Create one **C3Http.Session** per logical group of requests and set it on [`session`](C3Http.Options.md#property-session). A **C3Http.Session** is a `RefCounted` and is freed automatically when no [`C3Http.Options`](C3Http.Options.md) objects reference it.

One-off callers that leave [`session`](C3Http.Options.md#property-session) as `null` pay zero cost — a fresh connection is opened each time, as in previous versions.

## Properties

| Type | Name | Default |
|------|------|---------|
| [`int`](https://docs.godotengine.org/en/stable/classes/class_int.html) | [`max_connections_per_host`](#property-max_connections_per_host) | `6` |
| [`float`](https://docs.godotengine.org/en/stable/classes/class_float.html) | [`idle_timeout`](#property-idle_timeout) | `60.0` |

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | <code><a href="#method-close">close</a>()</code> |
| `void` | <code><a href="#method-prune">prune</a>()</code> |
| [`HTTPClient`](https://docs.godotengine.org/en/stable/classes/class_httpclient.html) | <code><a href="#method-checkout">checkout</a>(key: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |
| `void` | <code><a href="#method-checkin">checkin</a>(key: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>, client: <a href="https://docs.godotengine.org/en/stable/classes/class_httpclient.html">HTTPClient</a>)</code> |

## Property Descriptions

<a id="property-max_connections_per_host"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> max_connections_per_host = 6</code>

Maximum number of idle connections kept per unique `(host, port, scheme, TLS, proxy)` key. Extra connections beyond this limit are closed immediately on checkin.

<a id="property-idle_timeout"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_float.html">float</a> idle_timeout = 60.0</code>

Seconds an idle connection may sit in the pool before being discarded on the next checkout attempt. Keep this shorter than the server's keep-alive timeout (nginx defaults to 75 s, so 60 s is a safe choice). Set to `0.0` to disable time-based eviction.

## Method Descriptions

<a id="method-close"></a>

### <code>close</code>

<pre><code>func close() -> void:</code></pre>

Closes all pooled connections and empties the pool. Optional — connections are also freed when the **C3Http.Session** goes out of scope.

<a id="method-prune"></a>

### <code>prune</code>

<pre><code>func prune() -> void:</code></pre>

Evicts all idle connections whose age exceeds [`idle_timeout`](#property-idle_timeout). Useful after a network change to force fresh connections on the next call.

<a id="method-checkout"></a>

### <code>checkout</code>

<pre><code>func checkout(key: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> <a href="https://docs.godotengine.org/en/stable/classes/class_httpclient.html">HTTPClient</a>:</code></pre>

Returns a connected, non-expired client for `key`, or `null` if none is available. Stale or disconnected entries encountered during the search are discarded.

<a id="method-checkin"></a>

### <code>checkin</code>

<pre><code>func checkin(
    key: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>,
    client: <a href="https://docs.godotengine.org/en/stable/classes/class_httpclient.html">HTTPClient</a>
) -> void:</code></pre>

Returns `client` to the pool under `key`. If the pool is at [`max_connections_per_host`](#property-max_connections_per_host) capacity, the oldest idle entry is closed and evicted.
