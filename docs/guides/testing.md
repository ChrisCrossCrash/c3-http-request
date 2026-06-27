# Testing

`C3HTTPRequest`'s built-in `Mock` class makes testing with [GUT](https://github.com/bitwes/Gut) easy. `C3HTTPRequest.Mock` lets you test code that calls `C3HTTPRequest.request()` without touching the network. Install it in `before_each` and uninstall in `after_each` — every `await C3HTTPRequest.request(...)` in your code is intercepted for the duration:

```gdscript
var mock: C3HTTPRequest.Mock

func before_each() -> void:
    mock = C3HTTPRequest.Mock.new()
    mock.install()

func after_each() -> void:
    mock.uninstall()
```

## Stubbing responses

`mock.stub()` configures what a request returns. Pass a URL to match that endpoint exactly, or omit it to match any URL:

```gdscript
# Any URL → 200 OK with a JSON body
mock.stub().ok({"id": 1, "name": "Alice"})

# Specific endpoint → 201 Created
mock.stub("https://api.example.com/posts").ok({}, 201)

# Specific endpoint → transport failure
mock.stub("https://api.example.com/broken").fail(
    C3HTTPRequest.RequestError.transport("Connection refused")
)
```

When multiple stubs are registered, an exact-URL match takes priority over a wildcard. The three stub-builder methods are:

- `.ok(json: Dictionary = {}, status: int = 200)` — success response; `json` is serialized into `Response.body`
- `.fail(error: RequestError)` — failure response; build the error with `RequestError.transport()`, `RequestError.timed_out()`, etc.
- `.returns(response: Response)` — set a `Response` directly for full control (custom headers, a non-JSON body, etc.)

## Asserting calls

Every `C3HTTPRequest.request()` call is appended to `mock.calls`. Each entry is a `Dictionary` with keys `"url"`, `"method"`, `"headers"`, `"body"`, and `"options"`:

```gdscript
assert_eq(mock.call_count, 1)
assert_eq(mock.last_call["url"], "https://api.example.com/users")
assert_eq(mock.last_call["method"], HTTPClient.METHOD_POST)
```

`mock.reset()` clears the call log and all registered stubs without uninstalling — useful between sub-cases in the same test class.
