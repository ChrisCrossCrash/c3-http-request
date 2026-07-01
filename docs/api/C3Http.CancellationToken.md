# C3Http.CancellationToken

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

Token passed to [`cancellation_token`](C3Http.Options.md#property-cancellation_token) to cancel an in-flight request from another coroutine or signal handler.

## Methods

| Returns | Signature |
|---------|-----------|
| `void` | <code><a href="#method-cancel">cancel</a>()</code> |
| [`bool`](https://docs.godotengine.org/en/stable/classes/class_bool.html) | <code><a href="#method-is_cancelled">is_cancelled</a>()</code> |

## Method Descriptions

<a id="method-cancel"></a>

### <code>cancel</code>

<pre><code>func cancel() -> void:</code></pre>

Cancels any in-flight request holding this token. Subsequent calls have no effect.

<a id="method-is_cancelled"></a>

### <code>is_cancelled</code>

<pre><code>func is_cancelled() -> <a href="https://docs.godotengine.org/en/stable/classes/class_bool.html">bool</a>:</code></pre>

Returns `true` if [`cancel()`](#method-cancel) has been called.
