# Sessions (HTTP Keep-Alive)

By default every `request()` call opens a fresh TCP (and TLS) connection, completes the request, and closes it. That handshake cost is negligible for a one-off call, but it adds up when you're hitting the same host repeatedly — an API polling loop, a batch of asset fetches, or a chat client sending messages.

`Options.session` solves this. Assign a `Session` object and idle connections are pooled after each response and reused by the next call to the same host, skipping the handshake entirely.

```gdscript
var session := C3HTTPRequest.Session.new()

# Both calls reuse the same underlying TCP connection.
var res1 := await C3HTTPRequest.request(
    "https://api.example.com/users",
    PackedStringArray(), HTTPClient.METHOD_GET, "",
    _opts(session)
)
var res2 := await C3HTTPRequest.request(
    "https://api.example.com/posts",
    PackedStringArray(), HTTPClient.METHOD_GET, "",
    _opts(session)
)

func _opts(session: C3HTTPRequest.Session) -> C3HTTPRequest.Options:
    var opts := C3HTTPRequest.Options.new()
    opts.session = session
    return opts
```

One `Session` can be shared across as many calls as you like. Connections are keyed by `(host, port, scheme, TLS options, proxy)`, so a single session correctly handles multiple hosts without cross-contamination.

## Configuration

| Property                   | Type    | Default | Description                                                                                                                                                                                                                                        |
| -------------------------- | ------- | ------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `max_connections_per_host` | `int`   | `6`     | Maximum idle connections kept per host key. Extra connections beyond this limit are closed immediately on check-in.                                                                                                                                |
| `idle_timeout`             | `float` | `60.0`  | Seconds an idle connection may sit in the pool before being discarded on the next checkout attempt. `0.0` disables time-based eviction. Keep this shorter than the server's keep-alive timeout (nginx defaults to 75 s, so 60 s is a safe choice). |

```gdscript
var session := C3HTTPRequest.Session.new()
session.max_connections_per_host = 4
session.idle_timeout = 30.0
```

## Lifetime

`Session` is a `RefCounted`. It is freed automatically when no `Options` objects hold a reference to it — you don't need to free it manually. If you want to release connections early, call `close()`:

```gdscript
session.close()  # closes all pooled connections and empties the pool
```

`prune()` evicts only the connections that have exceeded `idle_timeout`, leaving fresher ones in place. This is useful after a network change (e.g. a WiFi handoff) to force fresh connections without discarding everything:

```gdscript
session.prune()
```

## Custom TLS options

If you leave `Options.tls_options` as `null` (the default), pooling just works — the pool key covers TLS vs. plain HTTP and the default `TLSOptions.client()` is implied.

If you set a custom `TLSOptions` (e.g. for self-signed certificates), you **must** reuse the same `TLSOptions` instance for every call that shares the session. Connections are pooled by the object's identity, so a newly constructed `TLSOptions` per request produces a different pool key each time and silently defeats connection reuse:

```gdscript
# Correct — one shared TLSOptions instance.
var tls := TLSOptions.client_unsafe()
var session := C3HTTPRequest.Session.new()

var opts := C3HTTPRequest.Options.new()
opts.session = session
opts.tls_options = tls  # same instance every time
```

## Automatic retry on a dead connection

A connection that was idle in the pool may have been closed by the server between requests. When this happens, `C3HTTPRequest` automatically retries the request once on a fresh connection — but only for methods that are safe to replay without side effects: `GET`, `HEAD`, and `OPTIONS`. `POST`, `PUT`, `PATCH`, and `DELETE` are never auto-retried, since the server may have already processed the request before dropping the connection.

This retry is transparent: the caller always receives a single `Response` and never needs to handle it.

## `Connection: close` responses

When a server sends a `Connection: close` response header, it signals that it will close the socket after this response. `C3HTTPRequest` honors this: the connection is **not** returned to the pool, and the next call opens a fresh one. This prevents handing a dying connection to the next request.
