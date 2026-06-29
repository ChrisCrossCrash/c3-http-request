# Session

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

Holds a pool of idle HTTP connections for reuse across calls, reducing the TCP and TLS handshake cost for repeated requests to the same host.

Create one [`Session`](session.md) per logical group of requests and set it on [`Options.session`](options.md#property-session). A [`Session`](session.md) is a [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted) and is freed automatically when no [`Options`](options.md) objects reference it.
One-off callers that leave [`Options.session`](options.md#property-session) as `null` pay zero cost — a fresh connection is opened each time, as in previous versions.

## Properties

| Type | Name | Default |
|------|------|---------|
| `int` | `max_connections_per_host` | `6` |
| `float` | `idle_timeout` | `60.0` |

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | [`close`](#method-close)`()` |
| `void` | [`prune`](#method-prune)`()` |
| [`HTTPClient`](https://docs.godotengine.org/en/stable/classes/class_httpclient.html#class-httpclient) | [`checkout`](#method-checkout)`(key: String)` |
| `void` | [`checkin`](#method-checkin)`(key: String, client: HTTPClient)` |

## Property Descriptions

<a id="property-max_connections_per_host"></a>

### `int` max_connections_per_host = `6`

Maximum number of idle connections kept per unique `(host, port, scheme, TLS, proxy)` key. Extra connections beyond this limit are closed immediately on checkin.

<a id="property-idle_timeout"></a>

### `float` idle_timeout = `60.0`

Seconds an idle connection may sit in the pool before being discarded on the next checkout attempt. Keep this shorter than the server's keep-alive timeout (nginx defaults to 75 s, so 60 s is a safe choice). Set to `0.0` to disable time-based eviction.

## Method Descriptions

<a id="method-close"></a>

### `void` `close()`

Closes all pooled connections and empties the pool. Optional — connections are also freed when the [`Session`](session.md) goes out of scope.

<a id="method-prune"></a>

### `void` `prune()`

Evicts all idle connections whose age exceeds [`idle_timeout`](#property-idle_timeout). Useful after a network change to force fresh connections on the next call.

<a id="method-checkout"></a>

### [`HTTPClient`](https://docs.godotengine.org/en/stable/classes/class_httpclient.html#class-httpclient) `checkout(key: String)`

Returns a connected, non-expired client for `key`, or `null` if none is available. Stale or disconnected entries encountered during the search are discarded.

<a id="method-checkin"></a>

### `void` `checkin(key: String, client: HTTPClient)`

Returns `client` to the pool under `key`. If the pool is at [`max_connections_per_host`](#property-max_connections_per_host) capacity, the oldest idle entry is closed and evicted.
