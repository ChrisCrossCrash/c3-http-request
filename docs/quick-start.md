# Quick Start

```gdscript
# GET
var res := await C3Http.request("https://api.example.com/todos/1")
if not res.ok:
    push_error(str(res.error))
    return
print(res.status)  # 200
print(res.text)    # response body decoded as UTF-8
print(res.json)    # response body parsed as JSON (Variant; null if invalid)
print(res.body)    # raw response body bytes (PackedByteArray)

# POST with a JSON body and custom headers
var res2 := await C3Http.request(
    "https://api.example.com/posts",
    PackedStringArray([
        "Content-Type: application/json",
        "Authorization: Bearer " + token,
    ]),
    HTTPClient.METHOD_POST,
    '{"title": "hello"}'
)

# POST a raw binary body (sent as-is, not UTF-8 encoded)
var res_raw := await C3Http.request_raw(
    "https://api.example.com/upload",
    PackedStringArray(["Content-Type: application/octet-stream"]),
    HTTPClient.METHOD_POST,
    payload  # a PackedByteArray
)

# Per-request options
var opts := C3Http.Options.new()
opts.timeout = 10.0
var res3 := await C3Http.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
```

Redirects are followed automatically (up to [`Options.max_redirects`](api/C3Http.Options.md#property-max_redirects)), so `res` reflects the final response the chain lands on.

## Signature

```gdscript
static func request(
    url: String,
    custom_headers: PackedStringArray = PackedStringArray(),
    method: HTTPClient.Method = HTTPClient.METHOD_GET,
    request_data: String = "",
    options: Options = null
) -> Response
```

```gdscript
static func request_raw(
    url: String,
    custom_headers: PackedStringArray = PackedStringArray(),
    method: HTTPClient.Method = HTTPClient.METHOD_GET,
    request_data: PackedByteArray = PackedByteArray(),
    options: Options = null
) -> Response
```

`request_raw()` is identical to `request()` except the body is a `PackedByteArray` sent as-is, without UTF-8 encoding. Use it for binary payloads (file uploads, protobuf, etc.).
