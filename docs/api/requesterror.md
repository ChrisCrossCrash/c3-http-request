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

### `RequestError.Kind` kind = `0` { #property-kind }

Broad category of failure. One of the `Kind` values.

### [`String`](https://docs.godotengine.org/en/stable/classes/class_string.html#class-string) message = `""` { #property-message }

Human-readable description. Never empty.

### `int` status = `0` { #property-status }

HTTP status code, or `0` when not applicable.

## Method Descriptions

### [`RequestError`](requesterror.md) `transport(p_message: String) static` { #method-transport }

Builds an error for a transport-level failure with no usable HTTP response.

### [`RequestError`](requesterror.md) `timed_out(p_message: String) static` { #method-timed_out }

Builds an error for a request that received no response before the timeout.

### [`RequestError`](requesterror.md) `client_error(p_message: String) static` { #method-client_error }

Builds an error for a request rejected before being sent.

### [`RequestError`](requesterror.md) `cancelled(p_message: String) static` { #method-cancelled }

Builds an error for a caller-initiated cancellation.

### [`RequestError`](requesterror.md) `body_size_limit_exceeded(p_message: String) static` { #method-body_size_limit_exceeded }

Builds an error for a response body that exceeded [`Options.body_size_limit`](options.md#property-body_size_limit).
