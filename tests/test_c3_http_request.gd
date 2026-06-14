extends GutTest


class TestableImpl extends C3HTTPRequest._Impl:
	## The response returned for every call to execute().
	var preset: C3HTTPRequest.Response = null
	## Ordered log of all execute() calls.
	var call_log: Array[Dictionary] = []

	func execute(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: String,
		options: C3HTTPRequest.Options,
		_redirects_left: int = -1
	) -> C3HTTPRequest.Response:
		call_log.append({
			"url": url,
			"custom_headers": custom_headers,
			"method": method,
			"request_data": request_data,
			"options": options,
		})
		if preset != null:
			return preset
		var res := C3HTTPRequest.Response.new()
		return res


## Tests for the static [method C3HTTPRequest.request] method.
class TestRequest extends GutTest:
	var impl: TestableImpl

	func before_each() -> void:
		impl = TestableImpl.new()
		C3HTTPRequest._impl = impl
		impl.preset = C3HTTPRequest.Response.new()

	func after_each() -> void:
		C3HTTPRequest._impl = C3HTTPRequest._Impl.new()

	func test_returns_response_object() -> void:
		var res := await C3HTTPRequest.request("https://example.com")
		assert_is(res, C3HTTPRequest.Response)

	func test_delegates_url_to_impl() -> void:
		await C3HTTPRequest.request("https://example.com/path")
		assert_eq(impl.call_log[0]["url"], "https://example.com/path")

	func test_default_method_is_get() -> void:
		await C3HTTPRequest.request("https://example.com")
		assert_eq(impl.call_log[0]["method"], HTTPClient.METHOD_GET)

	func test_method_is_forwarded() -> void:
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.POST
		)
		assert_eq(impl.call_log[0]["method"], HTTPClient.METHOD_POST)

	func test_custom_headers_forwarded() -> void:
		await C3HTTPRequest.request(
			"https://example.com", PackedStringArray(["X-Custom: value"])
		)
		assert_eq(
			impl.call_log[0]["custom_headers"],
			PackedStringArray(["X-Custom: value"])
		)

	func test_request_data_forwarded() -> void:
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.POST,
			"hello"
		)
		assert_eq(impl.call_log[0]["request_data"], "hello")

	func test_null_options_uses_defaults() -> void:
		await C3HTTPRequest.request("https://example.com")
		var opts: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_is(opts, C3HTTPRequest.Options)
		assert_eq(opts.timeout, 0.0)
		assert_eq(opts.max_redirects, 8)
		assert_true(opts.accept_gzip)

	func test_options_forwarded_when_provided() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.timeout = 5.0
		opts.max_redirects = 0
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.GET,
			"",
			opts
		)
		assert_eq(impl.call_log[0]["options"], opts)

	func test_2xx_response_is_ok() -> void:
		impl.preset.ok = true
		impl.preset.status = 200
		var res := await C3HTTPRequest.request("https://example.com")
		assert_true(res.ok)

	func test_body_on_success() -> void:
		impl.preset.ok = true
		impl.preset.body = "hello".to_utf8_buffer()
		var res := await C3HTTPRequest.request("https://example.com")
		assert_eq(res.body, "hello".to_utf8_buffer())

	func test_text_decodes_body() -> void:
		impl.preset.ok = true
		impl.preset.body = "hello".to_utf8_buffer()
		var res := await C3HTTPRequest.request("https://example.com")
		assert_eq(res.text, "hello")

	func test_status_on_success() -> void:
		impl.preset.ok = true
		impl.preset.status = 201
		var res := await C3HTTPRequest.request("https://example.com")
		assert_eq(res.status, 201)

	func test_failed_response_is_not_ok() -> void:
		impl.preset.ok = false
		impl.preset.error = C3HTTPRequest.RequestError.transport(
			"Could not connect."
		)
		var res := await C3HTTPRequest.request("https://example.com")
		assert_false(res.ok)

	func test_error_set_on_failure() -> void:
		var err := C3HTTPRequest.RequestError.transport("Could not connect.")
		impl.preset.ok = false
		impl.preset.error = err
		var res := await C3HTTPRequest.request("https://example.com")
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.TRANSPORT)

	func test_makes_exactly_one_call() -> void:
		await C3HTTPRequest.request("https://example.com")
		assert_eq(impl.call_log.size(), 1)


## Tests for [C3HTTPRequest.RequestError] factories and formatting.
class TestRequestError extends GutTest:
	const RequestError := C3HTTPRequest.RequestError

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


## Tests for [C3HTTPRequest.Response] defaults.
class TestResponse extends GutTest:
	func test_default_ok() -> void:
		assert_true(C3HTTPRequest.Response.new().ok)

	func test_default_error() -> void:
		assert_null(C3HTTPRequest.Response.new().error)

	func test_default_status() -> void:
		assert_eq(C3HTTPRequest.Response.new().status, 0)

	func test_default_headers() -> void:
		assert_eq(C3HTTPRequest.Response.new().headers, PackedStringArray())

	func test_default_body() -> void:
		assert_eq(C3HTTPRequest.Response.new().body, PackedByteArray())

	func test_default_text() -> void:
		assert_eq(C3HTTPRequest.Response.new().text, "")

	func test_text_decodes_body() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = "😎".to_utf8_buffer()
		assert_eq(res.text, "😎")


## Tests for [C3HTTPRequest.Options] defaults.
class TestOptions extends GutTest:
	func test_default_timeout() -> void:
		assert_eq(C3HTTPRequest.Options.new().timeout, 0.0)

	func test_default_body_size_limit() -> void:
		assert_eq(C3HTTPRequest.Options.new().body_size_limit, -1)

	func test_default_download_chunk_size() -> void:
		assert_eq(C3HTTPRequest.Options.new().download_chunk_size, 65536)

	func test_default_accept_gzip() -> void:
		assert_true(C3HTTPRequest.Options.new().accept_gzip)

	func test_default_max_redirects() -> void:
		assert_eq(C3HTTPRequest.Options.new().max_redirects, 8)

	func test_default_download_file() -> void:
		assert_eq(C3HTTPRequest.Options.new().download_file, "")

	func test_default_tls_options() -> void:
		assert_null(C3HTTPRequest.Options.new().tls_options)

	func test_default_cancellation_token() -> void:
		assert_null(C3HTTPRequest.Options.new().cancellation_token)


## Tests for [C3HTTPRequest.CancellationToken] and cancellation behavior.
class TestCancellationToken extends GutTest:
	func test_starts_not_cancelled() -> void:
		assert_false(C3HTTPRequest.CancellationToken.new().is_cancelled())

	func test_cancel_marks_as_cancelled() -> void:
		var token := C3HTTPRequest.CancellationToken.new()
		token.cancel()
		assert_true(token.is_cancelled())

	func test_cancel_is_idempotent() -> void:
		var token := C3HTTPRequest.CancellationToken.new()
		token.cancel()
		token.cancel()
		assert_true(token.is_cancelled())

	func test_pre_cancelled_token_returns_cancelled_response() -> void:
		var token := C3HTTPRequest.CancellationToken.new()
		token.cancel()
		var opts := C3HTTPRequest.Options.new()
		opts.cancellation_token = token
		var res: C3HTTPRequest.Response = await C3HTTPRequest._Impl.new().execute(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.CANCELLED)

	func test_pre_cancelled_error_string_contains_cancelled() -> void:
		var token := C3HTTPRequest.CancellationToken.new()
		token.cancel()
		var opts := C3HTTPRequest.Options.new()
		opts.cancellation_token = token
		var res: C3HTTPRequest.Response = await C3HTTPRequest._Impl.new().execute(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_string_contains(str(res.error), "[cancelled]")


## Unit tests for redirect method and body downgrade logic.
class TestRedirectSemantics extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	# _redirect_method
	func test_301_post_becomes_get() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_POST, 301),
			HTTPClient.METHOD_GET
		)

	func test_302_post_becomes_get() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_POST, 302),
			HTTPClient.METHOD_GET
		)

	func test_303_post_becomes_get() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_POST, 303),
			HTTPClient.METHOD_GET
		)

	func test_303_put_becomes_get() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_PUT, 303),
			HTTPClient.METHOD_GET
		)

	func test_301_get_stays_get() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_GET, 301),
			HTTPClient.METHOD_GET
		)

	func test_301_put_stays_put() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_PUT, 301),
			HTTPClient.METHOD_PUT
		)

	func test_307_post_stays_post() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_POST, 307),
			HTTPClient.METHOD_POST
		)

	func test_308_post_stays_post() -> void:
		assert_eq(
			impl._redirect_method(HTTPClient.METHOD_POST, 308),
			HTTPClient.METHOD_POST
		)

	# _redirect_body
	func test_301_post_drops_body() -> void:
		assert_eq(impl._redirect_body(HTTPClient.METHOD_POST, 301, "data"), "")

	func test_302_post_drops_body() -> void:
		assert_eq(impl._redirect_body(HTTPClient.METHOD_POST, 302, "data"), "")

	func test_303_drops_body_regardless_of_method() -> void:
		assert_eq(impl._redirect_body(HTTPClient.METHOD_PUT, 303, "data"), "")

	func test_307_post_preserves_body() -> void:
		assert_eq(
			impl._redirect_body(HTTPClient.METHOD_POST, 307, "data"), "data"
		)

	func test_308_post_preserves_body() -> void:
		assert_eq(
			impl._redirect_body(HTTPClient.METHOD_POST, 308, "data"), "data"
		)

	func test_301_put_preserves_body() -> void:
		assert_eq(
			impl._redirect_body(HTTPClient.METHOD_PUT, 301, "data"), "data"
		)


## Unit tests for redirect URL resolution.
class TestResolveRedirectUrl extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_absolute_https_returned_as_is() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"https://other.com/path", "host.com", 443, true, "/old"
			),
			"https://other.com/path"
		)

	func test_absolute_http_returned_as_is() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"http://other.com/path", "host.com", 80, false, "/old"
			),
			"http://other.com/path"
		)

	func test_protocol_relative_prepends_https() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"//other.com/path", "host.com", 443, true, "/old"
			),
			"https://other.com/path"
		)

	func test_protocol_relative_prepends_http() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"//other.com/path", "host.com", 80, false, "/old"
			),
			"http://other.com/path"
		)

	func test_absolute_path_on_default_port() -> void:
		assert_eq(
			impl._resolve_redirect_url("/new", "host.com", 443, true, "/old"),
			"https://host.com/new"
		)

	func test_absolute_path_on_explicit_port() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"/new", "localhost", 8080, false, "/old"
			),
			"http://localhost:8080/new"
		)

	func test_relative_path_resolved_against_base_dir() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"page", "host.com", 443, true, "/api/v1/"
			),
			"https://host.com/api/v1/page"
		)

	func test_relative_path_with_dot_dot() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"../v2/users", "host.com", 443, true, "/api/v1/users"
			),
			"https://host.com/api/v2/users"
		)

	func test_dot_segment_in_absolute_path() -> void:
		assert_eq(
			impl._resolve_redirect_url(
				"/a/b/../c", "host.com", 443, true, "/old"
			),
			"https://host.com/a/c"
		)

	func test_dot_dot_cannot_escape_root() -> void:
		assert_eq(
			impl._resolve_redirect_url("/../c", "host.com", 443, true, "/old"),
			"https://host.com/c"
		)


## Unit tests for the internal URL parser.
class TestParseUrl extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_https_default_port() -> void:
		var r := impl._parse_url("https://example.com/path")
		assert_eq(r["port"], 443)
		assert_true(r["tls"])

	func test_http_default_port() -> void:
		var r := impl._parse_url("http://example.com/path")
		assert_eq(r["port"], 80)
		assert_false(r["tls"])

	func test_explicit_port() -> void:
		var r := impl._parse_url("http://localhost:8080/api")
		assert_eq(r["host"], "localhost")
		assert_eq(r["port"], 8080)

	func test_host_extracted() -> void:
		var r := impl._parse_url("https://api.example.com/v1/users")
		assert_eq(r["host"], "api.example.com")

	func test_path_extracted() -> void:
		var r := impl._parse_url("https://example.com/v1/items")
		assert_eq(r["path"], "/v1/items")

	func test_no_path_defaults_to_slash() -> void:
		var r := impl._parse_url("https://example.com")
		assert_eq(r["path"], "/")

	func test_missing_scheme_returns_empty() -> void:
		assert_true(impl._parse_url("example.com/path").is_empty())

	func test_unsupported_scheme_returns_empty() -> void:
		assert_true(impl._parse_url("ftp://example.com").is_empty())

	func test_empty_host_returns_empty() -> void:
		assert_true(impl._parse_url("https:///path").is_empty())

	func test_fragment_stripped_from_path() -> void:
		var r := impl._parse_url("https://example.com/page#section")
		assert_eq(r["path"], "/page")

	func test_fragment_stripped_after_query() -> void:
		var r := impl._parse_url("https://example.com/page?q=1#section")
		assert_eq(r["path"], "/page?q=1")

	func test_ipv6_bare_address_default_port() -> void:
		var r := impl._parse_url("http://[::1]/path")
		assert_eq(r["host"], "::1")
		assert_eq(r["port"], 80)
		assert_false(r["tls"])

	func test_ipv6_with_explicit_port() -> void:
		var r := impl._parse_url("http://[::1]:8080/path")
		assert_eq(r["host"], "::1")
		assert_eq(r["port"], 8080)

	func test_ipv6_https_default_port() -> void:
		var r := impl._parse_url("https://[::1]/path")
		assert_eq(r["host"], "::1")
		assert_eq(r["port"], 443)
		assert_true(r["tls"])

	func test_ipv6_full_address() -> void:
		var r := impl._parse_url("https://[2001:db8::1]/path")
		assert_eq(r["host"], "2001:db8::1")
		assert_eq(r["port"], 443)

	func test_ipv6_no_path_defaults_to_slash() -> void:
		var r := impl._parse_url("http://[::1]")
		assert_eq(r["path"], "/")

	func test_ipv6_unclosed_bracket_returns_empty() -> void:
		assert_true(impl._parse_url("http://[::1/path").is_empty())
