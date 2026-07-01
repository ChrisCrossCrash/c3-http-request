# C3Http.RequestError

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html)

Structured error placed on [`error`](C3Http.Response.md#property-error) when [`ok`](C3Http.Response.md#property-ok) is `false`.

## Properties

| Type | Name | Default |
|------|------|---------|
| [`Kind`](#enum-Kind) | [`kind`](#property-kind) | `0` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html) | [`message`](#property-message) | `""` |
| [`int`](https://docs.godotengine.org/en/stable/classes/class_int.html) | [`status`](#property-status) | `0` |

## Methods

| Returns | Signature |
|---------|-----------|
| **C3Http.RequestError** | <code><a href="#method-transport">transport</a>(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |
| **C3Http.RequestError** | <code><a href="#method-timed_out">timed_out</a>(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |
| **C3Http.RequestError** | <code><a href="#method-client_error">client_error</a>(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |
| **C3Http.RequestError** | <code><a href="#method-cancelled">cancelled</a>(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |
| **C3Http.RequestError** | <code><a href="#method-body_size_limit_exceeded">body_size_limit_exceeded</a>(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>)</code> |

## Constants

<a id="enum-Kind"></a>

### enum `Kind`

| Name | Value | Description |
|------|-------|-------------|
| <a id="enum-Kind-TRANSPORT"></a> `TRANSPORT` | `0` | No usable HTTP response (DNS, TLS, connection, or request-start failure). |
| <a id="enum-Kind-HTTP"></a> `HTTP` | `1` | A non-2xx status was received. |
| <a id="enum-Kind-CLIENT"></a> `CLIENT` | `2` | The request was rejected before being sent (e.g. an invalid argument). |
| <a id="enum-Kind-CANCELLED"></a> `CANCELLED` | `3` | The caller aborted the request. |
| <a id="enum-Kind-TIMEOUT"></a> `TIMEOUT` | `4` | No response was received before the timeout elapsed. |
| <a id="enum-Kind-BODY_SIZE_LIMIT_EXCEEDED"></a> `BODY_SIZE_LIMIT_EXCEEDED` | `5` | The response body exceeded [`body_size_limit`](C3Http.Options.md#property-body_size_limit). |

## Property Descriptions

<a id="property-kind"></a>

### <code><a href="#enum-Kind">Kind</a> kind = 0</code>

Broad category of failure. One of the [`Kind`](#enum-Kind) values.

<a id="property-message"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a> message = &quot;&quot;</code>

Human-readable description. Never empty.

<a id="property-status"></a>

### <code><a href="https://docs.godotengine.org/en/stable/classes/class_int.html">int</a> status = 0</code>

HTTP status code, or `0` when not applicable.

## Method Descriptions

<a id="method-transport"></a>

### <code>transport</code>

<pre><code>func transport(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> C3Http.RequestError:</code></pre>

Builds an error for a transport-level failure with no usable HTTP response.

<a id="method-timed_out"></a>

### <code>timed_out</code>

<pre><code>func timed_out(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> C3Http.RequestError:</code></pre>

Builds an error for a request that received no response before the timeout.

<a id="method-client_error"></a>

### <code>client_error</code>

<pre><code>func client_error(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> C3Http.RequestError:</code></pre>

Builds an error for a request rejected before being sent.

<a id="method-cancelled"></a>

### <code>cancelled</code>

<pre><code>func cancelled(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> C3Http.RequestError:</code></pre>

Builds an error for a caller-initiated cancellation.

<a id="method-body_size_limit_exceeded"></a>

### <code>body_size_limit_exceeded</code>

<pre><code>func body_size_limit_exceeded(p_message: <a href="https://docs.godotengine.org/en/stable/classes/class_string.html">String</a>) -> C3Http.RequestError:</code></pre>

Builds an error for a response body that exceeded [`body_size_limit`](C3Http.Options.md#property-body_size_limit).
