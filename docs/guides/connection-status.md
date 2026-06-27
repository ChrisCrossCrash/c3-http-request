# Connection Status

Set `Options.on_status_changed` to a `Callable` to observe the underlying `HTTPClient` as it advances through its lifecycle — the equivalent of polling the native node's `get_http_client_status()`. The callback fires once per change, `on_status_changed.call(status)`, where `status` is an `HTTPClient.Status` value.

```gdscript
var opts := C3HTTPRequest.Options.new()
opts.on_status_changed = func(status: HTTPClient.Status) -> void:
    print(status)  # HTTPClient.STATUS_CONNECTING, STATUS_REQUESTING, STATUS_BODY, ...

var res := await C3HTTPRequest.request("https://example.com", PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
```

A typical request reports `STATUS_RESOLVING`/`STATUS_CONNECTING` → `STATUS_CONNECTED` → `STATUS_REQUESTING` → `STATUS_BODY`.

## Notes

- **Observational only** — the request's outcome still arrives via the returned `Response`; this callback never changes it.
- **Fires in every mode**, including `download_file` and SSE (`on_sse_event`), since it tracks the connection, not the body.
- **Repeats per redirect hop** — each hop opens a fresh connection, so the connect → request → body sequence is emitted again for every hop followed.
- **Best-effort** — a very brief intermediate state may be coalesced, since the status is sampled once per poll.
