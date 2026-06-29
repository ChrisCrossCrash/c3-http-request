# Cancellation

Pass a `CancellationToken` via `Options.cancellation_token` and call `token.cancel()` from anywhere — another coroutine, a signal handler, a button press. The polling loop checks the token between iterations and, once cancelled, abandons the request and returns a `Response` with `error.kind == CANCELLED`.

```gdscript
var token := C3Http.CancellationToken.new()
var opts := C3Http.Options.new()
opts.cancellation_token = token

# In another coroutine or signal handler:
token.cancel()

var res := await C3Http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
if not res.ok and res.error.kind == C3Http.RequestError.Kind.CANCELLED:
    print("Cancelled.")
```

To stop an SSE stream early, cancel the same token — the `await` resolves with `Kind.CANCELLED`.
