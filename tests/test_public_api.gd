extends GutTest


## Tests for the static [method C3Http.request] method.
class TestRequest extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new(C3Http)
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_returns_response_object() -> void:
		var res := await C3Http.request("https://example.com")
		assert_is(res, C3Http.Response)

	func test_delegates_url_to_impl() -> void:
		await C3Http.request("https://example.com/path")
		assert_eq(mock.calls[0]["url"], "https://example.com/path")

	func test_default_method_is_get() -> void:
		await C3Http.request("https://example.com")
		assert_eq(mock.calls[0]["method"], HTTPClient.METHOD_GET)

	func test_method_is_forwarded() -> void:
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_POST
		)
		assert_eq(mock.calls[0]["method"], HTTPClient.METHOD_POST)

	func test_custom_headers_forwarded() -> void:
		await C3Http.request(
			"https://example.com", PackedStringArray(["X-Custom: value"])
		)
		assert_eq(
			mock.calls[0]["headers"],
			PackedStringArray(["X-Custom: value"])
		)

	func test_request_data_forwarded() -> void:
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_POST,
			"hello"
		)
		assert_eq(mock.calls[0]["body"], "hello")

	func test_request_raw_data_forwarded() -> void:
		var body := PackedByteArray([0, 1, 2, 255])
		await C3Http.request_raw(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_POST,
			body
		)
		assert_eq(mock.calls[0]["body"], body)

	func test_request_raw_default_method_is_post() -> void:
		await C3Http.request_raw("https://example.com")
		assert_eq(mock.calls[0]["method"], HTTPClient.METHOD_POST)

	func test_request_raw_method_forwarded() -> void:
		await C3Http.request_raw(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_PUT,
			PackedByteArray([1, 2, 3])
		)
		assert_eq(mock.calls[0]["method"], HTTPClient.METHOD_PUT)

	func test_request_raw_headers_forwarded() -> void:
		await C3Http.request_raw(
			"https://example.com", PackedStringArray(["X-Custom: value"])
		)
		assert_eq(
			mock.calls[0]["headers"],
			PackedStringArray(["X-Custom: value"])
		)

	func test_request_raw_options_forwarded() -> void:
		var opts := C3Http.Options.new()
		opts.timeout = 5.0
		await C3Http.request_raw(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_POST,
			PackedByteArray(),
			opts
		)
		assert_eq(mock.calls[0]["options"], opts)

	func test_null_options_uses_defaults() -> void:
		await C3Http.request("https://example.com")
		var opts: C3Http.Options = mock.calls[0]["options"]
		assert_is(opts, C3Http.Options)
		assert_eq(opts.timeout, 0.0)
		assert_eq(opts.max_redirects, 8)
		assert_true(opts.accept_gzip)
		assert_false(opts.use_threads)

	func test_options_forwarded_when_provided() -> void:
		var opts := C3Http.Options.new()
		opts.timeout = 5.0
		opts.max_redirects = 0
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_eq(mock.calls[0]["options"], opts)

	func test_use_threads_forwarded_to_impl() -> void:
		var opts := C3Http.Options.new()
		opts.use_threads = true
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		var forwarded: C3Http.Options = mock.calls[0]["options"]
		assert_true(forwarded.use_threads)

	func test_on_progress_forwarded_to_impl() -> void:
		var sink := func(_received: int, _total: int) -> void: pass
		var opts := C3Http.Options.new()
		opts.on_progress = sink
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		var forwarded: C3Http.Options = mock.calls[0]["options"]
		assert_eq(forwarded.on_progress, sink)

	func test_on_status_changed_forwarded_to_impl() -> void:
		var sink := func(_status: HTTPClient.Status) -> void: pass
		var opts := C3Http.Options.new()
		opts.on_status_changed = sink
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		var forwarded: C3Http.Options = mock.calls[0]["options"]
		assert_eq(forwarded.on_status_changed, sink)

	func test_proxy_options_forwarded_to_impl() -> void:
		var opts := C3Http.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		var forwarded: C3Http.Options = mock.calls[0]["options"]
		assert_eq(forwarded.http_proxy_host, "http.proxy.example")
		assert_eq(forwarded.http_proxy_port, 8080)
		assert_eq(forwarded.https_proxy_host, "https.proxy.example")
		assert_eq(forwarded.https_proxy_port, 8443)

	func test_2xx_response_is_ok() -> void:
		mock.stub().ok()
		var res := await C3Http.request("https://example.com")
		assert_true(res.ok)

	func test_body_on_success() -> void:
		var preset := C3Http.Response.new()
		preset.ok = true
		preset.body = "hello".to_utf8_buffer()
		mock.stub().returns(preset)
		var res := await C3Http.request("https://example.com")
		assert_eq(res.body, "hello".to_utf8_buffer())

	func test_text_decodes_body() -> void:
		var preset := C3Http.Response.new()
		preset.ok = true
		preset.body = "hello".to_utf8_buffer()
		mock.stub().returns(preset)
		var res := await C3Http.request("https://example.com")
		assert_eq(res.text, "hello")

	func test_status_on_success() -> void:
		mock.stub().ok({}, 201)
		var res := await C3Http.request("https://example.com")
		assert_eq(res.status, 201)

	func test_failed_response_is_not_ok() -> void:
		mock.stub().fail(C3Http.RequestError.transport("Could not connect."))
		var res := await C3Http.request("https://example.com")
		assert_false(res.ok)

	func test_error_set_on_failure() -> void:
		var err := C3Http.RequestError.transport("Could not connect.")
		mock.stub().fail(err)
		var res := await C3Http.request("https://example.com")
		assert_eq(res.error.kind, C3Http.RequestError.Kind.TRANSPORT)

	func test_makes_exactly_one_call() -> void:
		await C3Http.request("https://example.com")
		assert_eq(mock.call_count, 1)


## Tests for [C3Http.RequestError] factories and formatting.
class TestRequestError extends GutTest:
	const RequestError := C3Http.RequestError

	func test_transport_factory() -> void:
		var e := RequestError.transport("No route to host.")
		assert_eq(e.kind, RequestError.Kind.TRANSPORT)
		assert_eq(e.message, "No route to host.")
		assert_eq(e.status, 0)

	func test_timed_out_factory() -> void:
		var e := RequestError.timed_out("Request timed out.")
		assert_eq(e.kind, RequestError.Kind.TIMEOUT)
		assert_eq(e.message, "Request timed out.")

	func test_client_error_factory() -> void:
		var e := RequestError.client_error("Invalid URL.")
		assert_eq(e.kind, RequestError.Kind.CLIENT)
		assert_eq(e.message, "Invalid URL.")

	func test_cancelled_factory() -> void:
		var e := RequestError.cancelled("Cancelled by caller.")
		assert_eq(e.kind, RequestError.Kind.CANCELLED)
		assert_eq(e.message, "Cancelled by caller.")

	func test_to_string_includes_kind_and_message() -> void:
		var s := str(RequestError.transport("Down."))
		assert_string_contains(s, "[transport]")
		assert_string_contains(s, "Down.")

	func test_to_string_omits_zero_status() -> void:
		assert_eq(str(RequestError.transport("Down.")), "[transport] Down.")

	func test_to_string_includes_status_when_nonzero() -> void:
		var e := RequestError.new()
		e.kind = RequestError.Kind.HTTP
		e.status = 404
		e.message = "Not found."
		assert_string_contains(str(e), "status=404")

	func test_to_string_timeout() -> void:
		var s := str(RequestError.timed_out("Timed out."))
		assert_string_contains(s, "[timeout]")

	func test_body_size_limit_exceeded_factory() -> void:
		var e := RequestError.body_size_limit_exceeded("Body too large.")
		assert_eq(e.kind, RequestError.Kind.BODY_SIZE_LIMIT_EXCEEDED)
		assert_eq(e.message, "Body too large.")
		assert_eq(e.status, 0)

	func test_to_string_body_size_limit_exceeded() -> void:
		var s := str(RequestError.body_size_limit_exceeded("Body too large."))
		assert_string_contains(s, "[body_size_limit_exceeded]")

	func test_to_string_cancelled() -> void:
		var s := str(RequestError.cancelled("Cancelled."))
		assert_string_contains(s, "[cancelled]")

	func test_to_string_client() -> void:
		var s := str(RequestError.client_error("Bad URL."))
		assert_string_contains(s, "[client]")

	func test_to_string_http() -> void:
		var e := RequestError.new()
		e.kind = RequestError.Kind.HTTP
		e.status = 404
		e.message = "Not found."
		assert_string_contains(str(e), "[http]")


## Tests for [C3Http.Response] defaults.
class TestResponse extends GutTest:
	func test_default_ok() -> void:
		assert_true(C3Http.Response.new().ok)

	func test_default_error() -> void:
		assert_null(C3Http.Response.new().error)

	func test_default_status() -> void:
		assert_eq(C3Http.Response.new().status, 0)

	func test_default_headers() -> void:
		assert_eq(C3Http.Response.new().headers, PackedStringArray())

	func test_default_body() -> void:
		assert_eq(C3Http.Response.new().body, PackedByteArray())

	func test_default_text() -> void:
		assert_eq(C3Http.Response.new().text, "")

	func test_text_decodes_body() -> void:
		var res := C3Http.Response.new()
		res.body = "😎".to_utf8_buffer()
		assert_eq(res.text, "😎")

	func test_text_empty_body_no_error() -> void:
		assert_eq(C3Http.Response.new().text, "")

	func test_json_parses_object() -> void:
		var res := C3Http.Response.new()
		res.body = '{"a":1}'.to_utf8_buffer()
		var parsed: Variant = res.json
		assert_true(parsed is Dictionary)
		assert_eq(parsed["a"], 1.0)

	func test_json_parses_array() -> void:
		var res := C3Http.Response.new()
		res.body = "[1,2,3]".to_utf8_buffer()
		var parsed: Variant = res.json
		assert_true(parsed is Array)
		assert_eq((parsed as Array).size(), 3)

	func test_json_default_is_null() -> void:
		assert_null(C3Http.Response.new().json)
		assert_push_error("not valid JSON")

	func test_json_literal_null() -> void:
		var res := C3Http.Response.new()
		res.body = "null".to_utf8_buffer()
		assert_null(res.json)
		assert_push_error_count(0)

	func test_json_invalid_returns_null() -> void:
		var res := C3Http.Response.new()
		res.body = "not json".to_utf8_buffer()
		assert_null(res.json)
		assert_push_error("not valid JSON")

	func test_json_cached() -> void:
		var res := C3Http.Response.new()
		res.body = '{"a":1}'.to_utf8_buffer()
		var first: Variant = res.json
		var second: Variant = res.json
		assert_eq(first, second)


## Tests for [C3Http.Options] defaults.
class TestOptions extends GutTest:
	func test_default_timeout() -> void:
		assert_eq(C3Http.Options.new().timeout, 0.0)

	func test_default_body_size_limit() -> void:
		assert_eq(C3Http.Options.new().body_size_limit, -1)

	func test_default_download_chunk_size() -> void:
		assert_eq(C3Http.Options.new().download_chunk_size, 65536)

	func test_default_accept_gzip() -> void:
		assert_true(C3Http.Options.new().accept_gzip)

	func test_default_max_redirects() -> void:
		assert_eq(C3Http.Options.new().max_redirects, 8)

	func test_default_download_file() -> void:
		assert_eq(C3Http.Options.new().download_file, "")

	func test_default_tls_options() -> void:
		assert_null(C3Http.Options.new().tls_options)

	func test_default_http_proxy_host() -> void:
		assert_eq(C3Http.Options.new().http_proxy_host, "")

	func test_default_http_proxy_port() -> void:
		assert_eq(C3Http.Options.new().http_proxy_port, -1)

	func test_default_https_proxy_host() -> void:
		assert_eq(C3Http.Options.new().https_proxy_host, "")

	func test_default_https_proxy_port() -> void:
		assert_eq(C3Http.Options.new().https_proxy_port, -1)

	func test_default_cancellation_token() -> void:
		assert_null(C3Http.Options.new().cancellation_token)

	func test_default_on_sse_event_is_invalid() -> void:
		assert_false(C3Http.Options.new().on_sse_event.is_valid())

	func test_default_on_progress_is_invalid() -> void:
		assert_false(C3Http.Options.new().on_progress.is_valid())

	func test_default_on_status_changed_is_invalid() -> void:
		assert_false(C3Http.Options.new().on_status_changed.is_valid())


## Tests for [C3Http.CancellationToken] and cancellation behavior.
class TestCancellationToken extends GutTest:
	func test_starts_not_cancelled() -> void:
		assert_false(C3Http.CancellationToken.new().is_cancelled())

	func test_cancel_marks_as_cancelled() -> void:
		var token := C3Http.CancellationToken.new()
		token.cancel()
		assert_true(token.is_cancelled())

	func test_cancel_is_idempotent() -> void:
		var token := C3Http.CancellationToken.new()
		token.cancel()
		token.cancel()
		assert_true(token.is_cancelled())

	func test_pre_cancelled_token_returns_cancelled_response() -> void:
		var token := C3Http.CancellationToken.new()
		token.cancel()
		var opts := C3Http.Options.new()
		opts.cancellation_token = token
		var res: C3Http.Response = await C3Http._Impl.new().request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3Http.RequestError.Kind.CANCELLED)

	func test_pre_cancelled_error_string_contains_cancelled() -> void:
		var token := C3Http.CancellationToken.new()
		token.cancel()
		var opts := C3Http.Options.new()
		opts.cancellation_token = token
		var res: C3Http.Response = await C3Http._Impl.new().request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_string_contains(str(res.error), "[cancelled]")


class TestInstantiation extends GutTest:
	func test_instantiation_pushes_warning() -> void:
		C3Http.new()
		assert_push_warning("not meant to be instantiated")


## Saving the body to a file and streaming it as SSE are mutually exclusive:
## SSE parsing bypasses the file-write path, so the request would leave an empty
## file behind. The combination is rejected up front with a CLIENT error.
class TestDownloadFileSseConflict extends GutTest:
	const _DOWNLOAD_PATH := "user://test_sse_conflict.bin"

	func after_each() -> void:
		if FileAccess.file_exists(_DOWNLOAD_PATH):
			DirAccess.remove_absolute(_DOWNLOAD_PATH)

	func test_download_file_with_sse_returns_client_error() -> void:
		var opts := C3Http.Options.new()
		opts.download_file = _DOWNLOAD_PATH
		opts.on_sse_event = func(_data: String, _event_type: String, _id: String) -> void: pass
		var res: C3Http.Response = await C3Http._Impl.new().request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3Http.RequestError.Kind.CLIENT)

	func test_download_file_with_sse_creates_no_file() -> void:
		var opts := C3Http.Options.new()
		opts.download_file = _DOWNLOAD_PATH
		opts.on_sse_event = func(_data: String, _event_type: String, _id: String) -> void: pass
		await C3Http._Impl.new().request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_false(
			FileAccess.file_exists(_DOWNLOAD_PATH),
			"no file should be created when the request is rejected up front"
		)
