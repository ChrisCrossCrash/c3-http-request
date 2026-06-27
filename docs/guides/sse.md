# Server-Sent Events (SSE)

Set `Options.on_sse_event` to a `Callable` to consume a streaming `text/event-stream` response. The callback fires once per event — `on_sse_event.call(data, event_type, last_event_id)` — as events arrive, and the same `await` you already use resolves to a final `Response` once the stream closes. No new method, no `Node`, no signal wiring.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_sse_event = func(data: String, event_type: String, last_event_id: String) -> void:
    print("[%s] %s" % [event_type, data])

var res := await C3HTTPRequest.request("https://api.example.com/stream", PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
if not res.ok:
    push_error(str(res.error))  # non-2xx body is collected normally into res.error
```

## Behavior

- **`data:` and `event:` fields** are surfaced; `event_type` defaults to `"message"` when no `event:` line is present. Multiple `data:` lines in one event are joined with newlines. Comment lines (`:` keep-alives) and events with no `data:` are dropped.
- **The `id:` field** is surfaced as the callback's `last_event_id`. Per the SSE spec it is a persistent cursor: an event with no `id:` line still reports the most recent one. The `retry:` field (the server's suggested reconnect backoff in milliseconds) lands on `Response.sse_retry_ms` — `-1` when none was sent.
- **Both `\n\n` and `\r\n\r\n` event delimiters** are supported, and a multi-byte UTF-8 character split across network reads is reassembled before decoding.
- **`Response.body` stays empty** on a successful (2xx) stream — the bytes are delivered to your callback, not collected. A **non-2xx** response is collected normally, so `res.ok`, `res.error`, and the error body work as usual.
- **`timeout` becomes an idle timeout** — the maximum seconds _between_ events, not a total deadline — so a healthy long-lived stream is never cut off. A stalled connection still fails with `Kind.TIMEOUT`. Use `0.0` to disable.
- **`accept_gzip` and `download_file` are ignored** while streaming.
- **Stop a stream** by cancelling its `cancellation_token` (see [Cancellation](cancellation.md)); the `await` then resolves with `Kind.CANCELLED`.

## Resuming a dropped stream

SSE connections are routinely severed — proxies and servers often cap a response at 30–60 seconds — so a long-lived consumer is expected to reconnect. The protocol supports resuming without gaps: the client echoes the last event's `id:` back as a `Last-Event-ID` request header, and the server replays whatever was missed.

`C3HTTPRequest` stays a one-shot client (one `request()`, one `Response`), but it surfaces both pieces you need, so the reconnect loop is a few lines on top:

```gdscript
# A single-element Array so the callback's write is visible out here — GDScript
# lambdas capture locals (like a String) by value, but an Array by reference.
var last_id := [""]
while true:
    var headers := PackedStringArray()
    if not last_id[0].is_empty():
        headers.append("Last-Event-ID: " + last_id[0])

    var opts := C3HTTPRequest.Options.new()
    opts.on_sse_event = func(data: String, event_type: String, id: String) -> void:
        last_id[0] = id  # remember where to resume from
        handle_event(data, event_type)

    var res := await C3HTTPRequest.request("https://api.example.com/stream", headers, HTTPClient.METHOD_GET, "", opts)

    # Honor the server's backoff hint if it sent one, else fall back.
    var backoff_ms := res.sse_retry_ms if res.sse_retry_ms >= 0 else 3000
    await Engine.get_main_loop().create_timer(backoff_ms / 1000.0).timeout
```
