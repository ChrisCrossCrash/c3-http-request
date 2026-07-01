# C3Http.Mock

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

Test helper that intercepts [`request()`](C3Http.md#method-request) calls. Install with [`install()`](#method-install), configure canned responses with [`stub()`](#method-stub), and inspect recorded calls via [`calls`](#property-calls). Always pair [`install()`](#method-install) with [`uninstall()`](#method-uninstall) in `after_each()`.

```gdscript
var mock: C3Http.Mock

func before_each() -> void:
    mock = C3Http.Mock.new()
    mock.install()

func after_each() -> void:
    mock.uninstall()

func test_example() -> void:
    mock.stub().ok({"id": 1})
    var res := await C3Http.request("https://api.example.com/users")
    assert_true(res.ok)
    assert_eq(mock.last_call["url"], "https://api.example.com/users")
```

## Properties

| Type | Name | Default |
|------|------|---------|
| [`Array`](https://docs.godotengine.org/en/stable/classes/class_array.html)[[`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html)] | [`calls`](#property-calls) | `[]` |
| [`int`](https://docs.godotengine.org/en/stable/classes/class_int.html) | [`call_count`](#property-call_count) |  |
| [`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html) | [`last_call`](#property-last_call) |  |

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | <code><a href="#method-install">install</a>()</code> |
| `void` | <code><a href="#method-uninstall">uninstall</a>()</code> |
| `C3Http._Stub` | <code><a href="#method-stub">stub</a>(url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> = &quot;&quot;)</code> |
| `void` | <code><a href="#method-reset">reset</a>()</code> |
| [`C3Http.Response`](C3Http.Response.md) | <code><a href="#method-request">request</a>(url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>, custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a>, method: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a>, request_data: <a href="https://docs.godotengine.org/en/stable/classes/class_variant.html">Variant</a>, options: <a href="C3Http.Options.md">C3Http.Options</a>, _redirects_left: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> = -1, _on_worker: <a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a> = false, _start_ms: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> = -1, _force_fresh: <a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a> = false)</code> |

## Property Descriptions

<a id="property-calls"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_array.html">Array</a>[<a href="https://docs.godotengine.org/en/stable/classes/class_dictionary.html">Dictionary</a>] calls = []</code>

Recorded calls in order, newest last. Each entry is a `Dictionary` with keys `url` (`String`), `method` (`int`, `HTTPClient.METHOD_*`), `headers` (`PackedStringArray`), `body` (`Variant`), and `options` ([`C3Http.Options`](C3Http.Options.md)).

<a id="property-call_count"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> call_count</code>

Total number of calls received since construction or the last [`reset()`](#method-reset).

<a id="property-last_call"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_dictionary.html">Dictionary</a> last_call</code>

The most recent call dictionary, or an empty `Dictionary` if no calls have been made yet.

## Method Descriptions

<a id="method-install"></a>

### <code>install</code>

<pre><code>func install() -> void:</code></pre>

Installs this mock as `C3Http._impl`.

<a id="method-uninstall"></a>

### <code>uninstall</code>

<pre><code>func uninstall() -> void:</code></pre>

Uninstalls this mock and restores normal request behavior.

<a id="method-stub"></a>

### <code>stub</code>

<pre><code>func stub(url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> = &quot;&quot;) -> C3Http._Stub:</code></pre>

Returns a stub builder for `url`. Omit `url` to create the catch-all default stub, matched when no URL-specific stub exists.

Stubs are evaluated in registration order; the first exact URL match wins, then the first default stub, then an empty [`C3Http.Response`](C3Http.Response.md).

<a id="method-reset"></a>

### <code>reset</code>

<pre><code>func reset() -> void:</code></pre>

Clears all recorded calls and registered stubs.

<a id="method-request"></a>

### <code>request</code>

<pre><code>func request(
    url: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>,
    custom_headers: <a href="https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html">PackedStringArray</a>,
    method: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a>,
    request_data: <a href="https://docs.godotengine.org/en/stable/classes/class_variant.html">Variant</a>,
    options: <a href="C3Http.Options.md">C3Http.Options</a>,
    _redirects_left: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> = -1,
    _on_worker: <a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a> = false,
    _start_ms: <a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> = -1,
    _force_fresh: <a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a> = false
) -> <a href="C3Http.Response.md">C3Http.Response</a>:</code></pre>
