# Mock

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

Test helper that intercepts [`request()`](c3httprequest.md#method-request) calls. Install with [`install()`](#method-install), configure canned responses with [`stub()`](#method-stub), and inspect recorded calls via [`calls`](#property-calls). Always pair [`install()`](#method-install) with [`uninstall()`](#method-uninstall) in `after_each()`.



```gdscript
var mock: C3HTTPRequest.Mock

func before_each() -> void:
    mock = C3HTTPRequest.Mock.new()
    mock.install()

func after_each() -> void:
    mock.uninstall()

func test_example() -> void:
    mock.stub().ok({"id": 1})
    var res := await C3HTTPRequest.request("https://api.example.com/users")
    assert_true(res.ok)
    assert_eq(mock.last_call["url"], "https://api.example.com/users")
```

## Properties

| Type | Name | Default |
|------|------|---------|
| `Dictionary[]` | `calls` | `[]` |
| `int` | `call_count` |  |
| [`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html#class-dictionary) | `last_call` |  |

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | [`install`](#method-install)`()` |
| `void` | [`uninstall`](#method-uninstall)`()` |
| `_Stub` | [`stub`](#method-stub)`(url: String = "")` |
| `void` | [`reset`](#method-reset)`()` |

## Property Descriptions

### `Dictionary[]` calls = `[]` { #property-calls }

Recorded calls in order, newest last. Each entry is a [`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html#class-dictionary) with keys `url` ([`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string)), `method` ([int], `HTTPClient.METHOD_*`), `headers` ([`PackedStringArray`](https://docs.godotengine.org/en/stable/classes/class_packedstringarray.html#class-packedstringarray)), `body` ([`Variant`](https://docs.godotengine.org/en/stable/classes/class_variant.html#class-variant)), and `options` ([`Options`](options.md)).

### `int` call_count { #property-call_count }

Total number of calls received since construction or the last [`reset()`](#method-reset).

### [`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html#class-dictionary) last_call { #property-last_call }

The most recent call dictionary, or an empty [`Dictionary`](https://docs.godotengine.org/en/stable/classes/class_dictionary.html#class-dictionary) if no calls have been made yet.

## Method Descriptions

### `void` `install()` { #method-install }

Installs this mock as `C3HTTPRequest._impl`.

### `void` `uninstall()` { #method-uninstall }

Uninstalls this mock and restores normal request behavior.

### `_Stub` `stub(url: String = "")` { #method-stub }

Returns a stub builder for `url`. Omit `url` to create the catch-all default stub, matched when no URL-specific stub exists.
Stubs are evaluated in registration order; the first exact URL match wins, then the first default stub, then an empty [`Response`](response.md).

### `void` `reset()` { #method-reset }

Clears all recorded calls and registered stubs.
