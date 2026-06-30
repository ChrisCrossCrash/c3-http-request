# Testing

`C3Http`'s built-in `Mock` class makes testing with [GUT](https://github.com/bitwes/Gut) easy. `C3Http.Mock` lets you test code that calls `C3Http.request()` without touching the network. Install it in `before_each` and uninstall in `after_each` — every `await C3Http.request(...)` in your code is intercepted for the duration:

```gdscript
var mock: C3Http.Mock

func before_each() -> void:
    mock = C3Http.Mock.new(C3Http)
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
    C3Http.RequestError.transport("Connection refused")
)
```

When multiple stubs are registered, an exact-URL match takes priority over a wildcard. The three stub-builder methods are:

- `.ok(json: Dictionary = {}, status: int = 200)` — success response; `json` is serialized into `Response.body`
- `.fail(error: RequestError)` — failure response; build the error with `RequestError.transport()`, `RequestError.timed_out()`, etc.
- `.returns(response: Response)` — set a `Response` directly for full control (custom headers, a non-JSON body, etc.)

## Asserting calls

Every `C3Http.request()` call is appended to `mock.calls`. Each entry is a `Dictionary` with keys `"url"`, `"method"`, `"headers"`, `"body"`, and `"options"`:

```gdscript
assert_eq(mock.call_count, 1)
assert_eq(mock.last_call["url"], "https://api.example.com/users")
assert_eq(mock.last_call["method"], HTTPClient.METHOD_POST)
```

`mock.reset()` clears the call log and all registered stubs without uninstalling — useful between sub-cases in the same test class.

## Testing without a global class name

Some addons comment out `class_name C3Http` to avoid polluting the global scope. In that case, load the script once into a local variable and use it everywhere `C3Http` would otherwise appear — including the `Mock.new()` call:

```gdscript
const C3Http := preload("res://addons/c3-http-request/c3_http_request/c3_http_request.gd")

var mock  # C3Http.Mock — typed as Variant to avoid the class name at the declaration site

func before_each() -> void:
    mock = C3Http.Mock.new(C3Http)
    mock.install()

func after_each() -> void:
    mock.uninstall()
```

`mock.install()` and `mock.uninstall()` take no arguments regardless — the script reference is captured once at construction time. Everything else (`mock.stub()`, `mock.calls`, `mock.reset()`) works identically.
