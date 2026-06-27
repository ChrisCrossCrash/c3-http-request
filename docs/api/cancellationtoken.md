# CancellationToken

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

Token passed to [`Options.cancellation_token`](options.md#property-cancellation_token) to cancel an in-flight request from another coroutine or signal handler.

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | [`cancel`](#method-cancel)`()` |
| `bool` | [`is_cancelled`](#method-is_cancelled)`()` |

## Method Descriptions

### `void` `cancel()` { #method-cancel }

Cancels any in-flight request holding this token. Subsequent calls have no effect.

### `bool` `is_cancelled()` { #method-is_cancelled }

Returns `true` if [`cancel()`](#method-cancel) has been called.
