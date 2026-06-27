# Download Progress

Set `Options.on_progress` to a `Callable` to track a download as it arrives. The callback fires once per chunk — `on_progress.call(bytes_received, total_bytes)` — where `bytes_received` is the cumulative count so far and `total_bytes` is the `Content-Length`, or `-1` when the server doesn't send one (e.g. a chunked response). Compute a percentage only when `total_bytes` is positive.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_progress = func(bytes_received: int, total_bytes: int) -> void:
    if total_bytes > 0:
        print("%d%%" % (bytes_received * 100 / total_bytes))
    else:
        print("%d bytes" % bytes_received)  # length unknown

var res := await C3HTTPRequest.request("https://example.com/large.bin", PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
```

Works for both in-memory and `download_file` downloads. `bytes_received` counts raw bytes off the wire, so it may differ from the final `res.body.size()` when a gzip body is decompressed after the transfer completes. It has no effect in SSE mode (`on_sse_event`), where the events themselves are the incremental signal.
