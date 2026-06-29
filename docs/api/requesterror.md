# RequestError

**Inherits:** [`RefCounted`](https://docs.godotengine.org/en/stable/classes/class_refcounted.html#class-refcounted)

Structured error placed on [`Response.error`](response.md#property-error) when [`Response.ok`](response.md#property-ok) is `false`.

## Properties

| Type | Name | Default |
|------|------|---------|
| `RequestError.Kind` | `kind` | `0` |
| [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) | `message` | `""` |
| `int` | `status` | `0` |

## Methods

| Returns | Signature |
|---------|-----------|
| [`RequestError`](requesterror.md) | [`transport`](#method-transport)`(p_message: String) static` |
| [`RequestError`](requesterror.md) | [`timed_out`](#method-timed_out)`(p_message: String) static` |
| [`RequestError`](requesterror.md) | [`client_error`](#method-client_error)`(p_message: String) static` |
| [`RequestError`](requesterror.md) | [`cancelled`](#method-cancelled)`(p_message: String) static` |
| [`RequestError`](requesterror.md) | [`body_size_limit_exceeded`](#method-body_size_limit_exceeded)`(p_message: String) static` |

## Constants

### enum `Kind`

| Name | Value | Description |
|------|-------|-------------|
| `TRANSPORT` | `0` | No usable HTTP response (DNS, TLS, connection, or request-start failure). |
| `HTTP` | `1` | A non-2xx status was received. |
| `CLIENT` | `2` | The request was rejected before being sent (e.g. an invalid argument). |
| `CANCELLED` | `3` | The caller aborted the request. |
| `TIMEOUT` | `4` | No response was received before the timeout elapsed. |
| `BODY_SIZE_LIMIT_EXCEEDED` | `5` | The response body exceeded [`Options.body_size_limit`](options.md#property-body_size_limit). |

## Property Descriptions

<a id="property-kind"></a>

### `RequestError.Kind` kind = `0`

Broad category of failure. One of the `Kind` values.

<a id="property-message"></a>

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) message = `""`

Human-readable description. Never empty.

<a id="property-status"></a>

### `int` status = `0`

HTTP status code, or `0` when not applicable.

## Method Descriptions

<a id="method-transport"></a>

### [`RequestError`](requesterror.md) `transport(p_message: String) static`

Builds an error for a transport-level failure with no usable HTTP response.

<a id="method-timed_out"></a>

### [`RequestError`](requesterror.md) `timed_out(p_message: String) static`

Builds an error for a request that received no response before the timeout.

<a id="method-client_error"></a>

### [`RequestError`](requesterror.md) `client_error(p_message: String) static`

Builds an error for a request rejected before being sent.

<a id="method-cancelled"></a>

### [`RequestError`](requesterror.md) `cancelled(p_message: String) static`

Builds an error for a caller-initiated cancellation.

<a id="method-body_size_limit_exceeded"></a>

### [`RequestError`](requesterror.md) `body_size_limit_exceeded(p_message: String) static`

Builds an error for a response body that exceeded [`Options.body_size_limit`](options.md#property-body_size_limit).
