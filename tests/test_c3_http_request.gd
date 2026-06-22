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
		request_data: Variant,
		options: C3HTTPRequest.Options,
		_redirects_left: int = -1,
		_on_worker: bool = false
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

	func test_request_raw_data_forwarded() -> void:
		var body := PackedByteArray([0, 1, 2, 255])
		await C3HTTPRequest.request_raw(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.POST,
			body
		)
		assert_eq(impl.call_log[0]["request_data"], body)

	func test_request_raw_default_method_is_post() -> void:
		await C3HTTPRequest.request_raw("https://example.com")
		assert_eq(impl.call_log[0]["method"], HTTPClient.METHOD_POST)

	func test_request_raw_method_forwarded() -> void:
		await C3HTTPRequest.request_raw(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.PUT,
			PackedByteArray([1, 2, 3])
		)
		assert_eq(impl.call_log[0]["method"], HTTPClient.METHOD_PUT)

	func test_request_raw_headers_forwarded() -> void:
		await C3HTTPRequest.request_raw(
			"https://example.com", PackedStringArray(["X-Custom: value"])
		)
		assert_eq(
			impl.call_log[0]["custom_headers"],
			PackedStringArray(["X-Custom: value"])
		)

	func test_request_raw_options_forwarded() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.timeout = 5.0
		await C3HTTPRequest.request_raw(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.POST,
			PackedByteArray(),
			opts
		)
		assert_eq(impl.call_log[0]["options"], opts)

	func test_null_options_uses_defaults() -> void:
		await C3HTTPRequest.request("https://example.com")
		var opts: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_is(opts, C3HTTPRequest.Options)
		assert_eq(opts.timeout, 0.0)
		assert_eq(opts.max_redirects, 8)
		assert_true(opts.accept_gzip)
		assert_false(opts.use_threads)

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

	func test_use_threads_forwarded_to_impl() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.use_threads = true
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.GET,
			"",
			opts
		)
		var forwarded: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_true(forwarded.use_threads)

	func test_on_progress_forwarded_to_impl() -> void:
		var sink := func(_received: int, _total: int) -> void: pass
		var opts := C3HTTPRequest.Options.new()
		opts.on_progress = sink
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.GET,
			"",
			opts
		)
		var forwarded: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_eq(forwarded.on_progress, sink)

	func test_on_status_changed_forwarded_to_impl() -> void:
		var sink := func(_status: HTTPClient.Status) -> void: pass
		var opts := C3HTTPRequest.Options.new()
		opts.on_status_changed = sink
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.GET,
			"",
			opts
		)
		var forwarded: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_eq(forwarded.on_status_changed, sink)

	func test_proxy_options_forwarded_to_impl() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		await C3HTTPRequest.request(
			"https://example.com",
			PackedStringArray(),
			C3HTTPRequest.Method.GET,
			"",
			opts
		)
		var forwarded: C3HTTPRequest.Options = impl.call_log[0]["options"]
		assert_eq(forwarded.http_proxy_host, "http.proxy.example")
		assert_eq(forwarded.http_proxy_port, 8080)
		assert_eq(forwarded.https_proxy_host, "https.proxy.example")
		assert_eq(forwarded.https_proxy_port, 8443)

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

	func test_text_empty_body_no_error() -> void:
		assert_eq(C3HTTPRequest.Response.new().text, "")

	func test_json_parses_object() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = '{"a":1}'.to_utf8_buffer()
		var parsed: Variant = res.json
		assert_true(parsed is Dictionary)
		assert_eq(parsed["a"], 1.0)

	func test_json_parses_array() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = "[1,2,3]".to_utf8_buffer()
		var parsed: Variant = res.json
		assert_true(parsed is Array)
		assert_eq((parsed as Array).size(), 3)

	func test_json_default_is_null() -> void:
		assert_null(C3HTTPRequest.Response.new().json)
		assert_push_error("not valid JSON")

	func test_json_literal_null() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = "null".to_utf8_buffer()
		assert_null(res.json)
		assert_push_error_count(0)

	func test_json_invalid_returns_null() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = "not json".to_utf8_buffer()
		assert_null(res.json)
		assert_push_error("not valid JSON")

	func test_json_cached() -> void:
		var res := C3HTTPRequest.Response.new()
		res.body = '{"a":1}'.to_utf8_buffer()
		var first: Variant = res.json
		var second: Variant = res.json
		assert_eq(first, second)


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

	func test_default_http_proxy_host() -> void:
		assert_eq(C3HTTPRequest.Options.new().http_proxy_host, "")

	func test_default_http_proxy_port() -> void:
		assert_eq(C3HTTPRequest.Options.new().http_proxy_port, -1)

	func test_default_https_proxy_host() -> void:
		assert_eq(C3HTTPRequest.Options.new().https_proxy_host, "")

	func test_default_https_proxy_port() -> void:
		assert_eq(C3HTTPRequest.Options.new().https_proxy_port, -1)

	func test_default_cancellation_token() -> void:
		assert_null(C3HTTPRequest.Options.new().cancellation_token)

	func test_default_on_sse_event_is_invalid() -> void:
		assert_false(C3HTTPRequest.Options.new().on_sse_event.is_valid())

	func test_default_on_progress_is_invalid() -> void:
		assert_false(C3HTTPRequest.Options.new().on_progress.is_valid())

	func test_default_on_status_changed_is_invalid() -> void:
		assert_false(C3HTTPRequest.Options.new().on_status_changed.is_valid())


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


## Unit tests for the internal SSE event parser.
class TestSSEParsing extends GutTest:
	# 😀 U+1F600 — 4 bytes: F0 9F 98 80.
	const _EMOJI := "😀"
	# — U+2014 em-dash — 3 bytes: E2 80 94.
	const _EM_DASH := "—"

	var impl: C3HTTPRequest._Impl
	var events: Array = []

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()
		events = []

	# Records each dispatched event as [data, event_type].
	func _sink() -> Callable:
		return func(data: String, event_type: String) -> void:
			events.append([data, event_type])

	# Feeds [param first] then [param second] as two separate socket reads,
	# draining after each — mirroring the body loop accumulating raw bytes across
	# frames. A character split across the two reads must survive reassembly.
	func _feed_two_reads(first: PackedByteArray, second: PackedByteArray) -> void:
		var rest := impl._drain_sse_buffer(first, _sink())
		rest.append_array(second)
		impl._drain_sse_buffer(rest, _sink())

	# _emit_sse_event
	func test_emit_basic_event_defaults_to_message() -> void:
		impl._emit_sse_event("data: hello", _sink())
		assert_eq(events, [["hello", "message"]])

	func test_emit_uses_event_type() -> void:
		impl._emit_sse_event("event: ping\ndata: hello", _sink())
		assert_eq(events, [["hello", "ping"]])

	func test_emit_joins_multiple_data_lines() -> void:
		impl._emit_sse_event("data: a\ndata: b", _sink())
		assert_eq(events, [["a\nb", "message"]])

	func test_emit_strips_single_leading_space() -> void:
		impl._emit_sse_event("data:  two-spaces", _sink())
		assert_eq(events[0][0], " two-spaces")

	func test_emit_data_without_space() -> void:
		impl._emit_sse_event("data:nospace", _sink())
		assert_eq(events[0][0], "nospace")

	func test_emit_ignores_comment_lines() -> void:
		impl._emit_sse_event(": keep-alive\ndata: hi", _sink())
		assert_eq(events, [["hi", "message"]])

	func test_emit_drops_event_with_no_data() -> void:
		impl._emit_sse_event("event: ping\nid: 42", _sink())
		assert_eq(events, [])

	func test_emit_strips_trailing_cr_from_crlf_lines() -> void:
		impl._emit_sse_event("event: ping\r\ndata: hi\r", _sink())
		assert_eq(events, [["hi", "ping"]])

	func test_emit_empty_string_emits_nothing() -> void:
		impl._emit_sse_event("", _sink())
		assert_eq(events, [])

	func test_emit_only_comments_emits_nothing() -> void:
		impl._emit_sse_event(": ping\n: pong", _sink())
		assert_eq(events, [])

	func test_emit_event_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("event: update", _sink())
		assert_eq(events, [])

	func test_emit_id_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("id: 42", _sink())
		assert_eq(events, [])

	func test_emit_retry_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("retry: 3000", _sink())
		assert_eq(events, [])

	func test_emit_id_with_data_emits_only_data() -> void:
		impl._emit_sse_event("id: 42\ndata: hello", _sink())
		assert_eq(events, [["hello", "message"]])

	func test_emit_retry_with_data_emits_only_data() -> void:
		impl._emit_sse_event("retry: 3000\ndata: hello", _sink())
		assert_eq(events, [["hello", "message"]])

	# _drain_sse_buffer
	func test_drain_emits_complete_lf_events() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\n\ndata: b\n\n".to_utf8_buffer(), _sink()
		)
		assert_eq(events, [["a", "message"], ["b", "message"]])
		assert_eq(rest.size(), 0)

	func test_drain_emits_complete_crlf_events() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\r\n\r\ndata: b\r\n\r\n".to_utf8_buffer(), _sink()
		)
		assert_eq(events, [["a", "message"], ["b", "message"]])
		assert_eq(rest.size(), 0)

	func test_drain_retains_trailing_partial_event() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\n\ndata: b".to_utf8_buffer(), _sink()
		)
		assert_eq(events, [["a", "message"]])
		assert_eq(rest.get_string_from_utf8(), "data: b")

	func test_drain_keeps_split_multibyte_char_intact() -> void:
		# "h😎" — the 😎 emoji is four UTF-8 bytes; the buffer ends mid-character with
		# no boundary yet, so nothing is dispatched and all bytes are retained.
		var partial := "data: h".to_utf8_buffer()
		partial.append(0xF0) # first byte of 😎 (U+1F60E, encoded F0 9F 98 8E)
		var rest := impl._drain_sse_buffer(partial, _sink())
		assert_eq(events, [])
		assert_eq(rest, partial)

	func test_drain_empty_buffer_emits_nothing() -> void:
		var rest := impl._drain_sse_buffer(PackedByteArray(), _sink())
		assert_eq(events, [])
		assert_eq(rest.size(), 0)

	# Multi-byte UTF-8 character split across two socket reads — the core reason
	# the parser buffers raw bytes and slices on the ASCII delimiter.
	func test_emoji_split_mid_payload_reassembled() -> void:
		# "data: a😀b\n\n" with the emoji's 4 bytes split 2/2 across reads.
		var emoji := _EMOJI.to_utf8_buffer()
		var first := "data: a".to_utf8_buffer()
		first.append_array(emoji.slice(0, 2))
		var second := emoji.slice(2)
		second.append_array("b\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_eq(events, [["a" + _EMOJI + "b", "message"]])

	func test_emoji_split_emits_no_replacement_char() -> void:
		# Guards against per-chunk decoding, which would leave U+FFFD on each half.
		var emoji := _EMOJI.to_utf8_buffer()
		var first := "data: ".to_utf8_buffer()
		first.append_array(emoji.slice(0, 2))
		var second := emoji.slice(2)
		second.append_array("\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_false(events[0][0].contains("�"), "no replacement char in payload")

	func test_em_dash_split_at_event_boundary_reassembled() -> void:
		# The em-dash is the last character before the \n\n boundary, split 1/2 so
		# it lands mid-character right at the event boundary.
		var dash := _EM_DASH.to_utf8_buffer()
		var first := "data: hi".to_utf8_buffer()
		first.append_array(dash.slice(0, 1))
		var second := dash.slice(1)
		second.append_array("\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_eq(events, [["hi" + _EM_DASH, "message"]])

	# _find_sse_boundary
	func test_find_boundary_lf() -> void:
		assert_eq(impl._find_sse_boundary("a\n\nb".to_utf8_buffer()), Vector2i(1, 3))

	func test_find_boundary_crlf() -> void:
		assert_eq(
			impl._find_sse_boundary("a\r\n\r\nb".to_utf8_buffer()), Vector2i(2, 5)
		)

	func test_find_boundary_none() -> void:
		assert_eq(
			impl._find_sse_boundary("data: a\n".to_utf8_buffer()), Vector2i(-1, -1)
		)


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

	func test_307_post_preserves_raw_body() -> void:
		var body := PackedByteArray([1, 2, 3])
		assert_eq(impl._redirect_body(HTTPClient.METHOD_POST, 307, body), body)

	func test_308_put_preserves_raw_body() -> void:
		var body := PackedByteArray([4, 5, 6])
		assert_eq(impl._redirect_body(HTTPClient.METHOD_PUT, 308, body), body)

	func test_303_drops_raw_body() -> void:
		assert_eq(
			impl._redirect_body(
				HTTPClient.METHOD_POST, 303, PackedByteArray([1, 2, 3])
			),
			""
		)

	func test_302_post_drops_raw_body() -> void:
		assert_eq(
			impl._redirect_body(
				HTTPClient.METHOD_POST, 302, PackedByteArray([1, 2, 3])
			),
			""
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


## Tests for the per-scheme proxy routing decision in [method _Impl._resolve_proxies].
class TestResolveProxies extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_no_proxy_returns_empty() -> void:
		assert_true(impl._resolve_proxies(C3HTTPRequest.Options.new()).is_empty())

	func test_both_schemes_routed_independently() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["http"], ["http.proxy.example", 8080])
		assert_eq(proxies["https"], ["https.proxy.example", 8443])

	func test_only_http_proxy_set() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["http"], ["http.proxy.example", 8080])
		assert_false(proxies.has("https"))

	func test_only_https_proxy_set() -> void:
		var opts := C3HTTPRequest.Options.new()
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["https"], ["https.proxy.example", 8443])
		assert_false(proxies.has("http"))


## Tests for the streaming download decompressor
## ([method _Impl._decode_chunk] / [method _Impl._drain_decoder]).
class TestStreamingDecompression extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	# Decodes [param compressed] by feeding it through _decode_chunk in slices of
	# [param piece] bytes — mirroring the body loop's per-chunk decode. Each chunk
	# is fully drained on arrival, so the complete output is gathered by the time
	# the last chunk (carrying the gzip footer) is consumed. Returns {"ok","data"}.
	func _decode_in_pieces(
		compressed: PackedByteArray, piece: int
	) -> Dictionary:
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)  # gzip
		var out := PackedByteArray()
		var pos := 0
		while pos < compressed.size():
			var end: int = mini(pos + piece, compressed.size())
			var res := impl._decode_chunk(decoder, compressed.slice(pos, end), 4096)
			if not res["ok"]:
				return {"ok": false, "data": out}
			out.append_array(res["data"])
			pos = end
		return {"ok": true, "data": out}

	func test_decode_gzip_single_chunk() -> void:
		var original := "The quick brown fox.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, compressed.size())
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_gzip_split_across_many_reads() -> void:
		# A byte-at-a-time feed must reassemble to the same bytes — the decoder
		# has to buffer state across chunks.
		var original := (
			"Streaming decompression across chunk boundaries!".to_utf8_buffer()
		)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, 1)
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_empty_input_is_ok_and_empty() -> void:
		var result := _decode_in_pieces(PackedByteArray(), 4096)
		assert_true(result["ok"])
		assert_eq(result["data"], PackedByteArray())

	func test_decode_large_body_round_trips() -> void:
		# A body well past a single buffer, to exercise multi-slice draining.
		var text := "C3HTTPRequest streaming gzip. ".repeat(2000)
		var original := text.to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, 512)
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_highly_compressible_single_chunk() -> void:
		# 4 MB of one byte compresses to a few KB, then expands ~1000x past the
		# decoder's internal buffer. Fed as ONE chunk, this would overflow a naive
		# put_data() call; _decode_chunk must drain incrementally and recover it.
		var original := PackedByteArray()
		original.resize(4 * 1024 * 1024)
		original.fill(65)  # "A"
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		assert_lt(compressed.size(), 65536, "fixture should compress below ring size")
		var result := _decode_in_pieces(compressed, compressed.size())
		assert_true(result["ok"])
		assert_eq((result["data"] as PackedByteArray).size(), original.size())
		assert_eq(result["data"], original)

	func test_decode_budget_stops_a_bomb_early() -> void:
		# 4 MB collapsing to a few KB is a decompression bomb. With a small budget,
		# _decode_chunk must bail out long before materializing all 4 MB, so the
		# size-limit guard can reject it without an unbounded allocation.
		var original := PackedByteArray()
		original.resize(4 * 1024 * 1024)
		original.fill(65)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)
		var result := impl._decode_chunk(decoder, compressed, 65536, 1024)
		assert_true(result["ok"])
		var produced: int = (result["data"] as PackedByteArray).size()
		assert_gt(produced, 1024, "should overshoot the budget by at most a buffer")
		assert_lt(produced, original.size(), "must not decode the whole bomb")


## Tests for request header assembly ([method _Impl._build_request_headers]).
class TestBuildRequestHeaders extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_adds_accept_encoding_when_enabled() -> void:
		var headers := impl._build_request_headers(
			PackedStringArray(), true, false
		)
		assert_true("Accept-Encoding: gzip" in headers)

	func test_does_not_advertise_deflate() -> void:
		# We advertise gzip only; deflate is intentionally unsupported because raw vs
		# zlib-wrapped deflate cannot be disambiguated reliably.
		var headers := impl._build_request_headers(
			PackedStringArray(), true, false
		)
		for header: String in headers:
			assert_false("deflate" in header.to_lower())

	func test_omits_accept_encoding_when_disabled() -> void:
		var headers := impl._build_request_headers(
			PackedStringArray(), false, false
		)
		assert_false("Accept-Encoding: gzip" in headers)

	func test_omits_accept_encoding_when_streaming() -> void:
		var headers := impl._build_request_headers(
			PackedStringArray(), true, true
		)
		assert_false("Accept-Encoding: gzip" in headers)

	func test_caller_accept_encoding_suppresses_ours() -> void:
		var custom := PackedStringArray(["Accept-Encoding: br"])
		var headers := impl._build_request_headers(custom, true, false)
		assert_false("Accept-Encoding: gzip" in headers)
		assert_true("Accept-Encoding: br" in headers)

	func test_caller_accept_encoding_match_is_case_insensitive() -> void:
		var custom := PackedStringArray(["accept-encoding: identity"])
		var headers := impl._build_request_headers(custom, true, false)
		assert_false("Accept-Encoding: gzip" in headers)

	func test_custom_headers_are_always_appended() -> void:
		var custom := PackedStringArray(["X-Test: 1", "Authorization: Bearer x"])
		var headers := impl._build_request_headers(custom, true, false)
		assert_true("X-Test: 1" in headers)
		assert_true("Authorization: Bearer x" in headers)


## Unit tests for the internal header-value lookup ([method _Impl._header_value]).
class TestHeaderValue extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_finds_value_with_space() -> void:
		var headers := PackedStringArray(["Accept-Encoding: gzip"])
		assert_eq(impl._header_value(headers, "Accept-Encoding"), "gzip")

	func test_finds_value_without_space() -> void:
		var headers := PackedStringArray(["Accept-Encoding:br"])
		assert_eq(impl._header_value(headers, "Accept-Encoding"), "br")

	func test_lookup_is_case_insensitive() -> void:
		var headers := PackedStringArray(["content-type: text/plain"])
		assert_eq(impl._header_value(headers, "Content-Type"), "text/plain")

	func test_returns_empty_when_not_found() -> void:
		assert_eq(impl._header_value(PackedStringArray(), "Accept-Encoding"), "")

	func test_does_not_match_prefix_of_another_header() -> void:
		var headers := PackedStringArray(["Accept-Encoding-Extra: gzip"])
		assert_eq(impl._header_value(headers, "Accept-Encoding"), "")


## Tests for the download decompressor factory
## ([method _Impl._make_download_decoder]).
class TestMakeDownloadDecoder extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_null_when_accept_gzip_false() -> void:
		# Regression guard: an opted-out caller must never get a decoder, even for a
		# compressed response.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		assert_null(impl._make_download_decoder(headers, false))

	func test_null_when_no_compression() -> void:
		assert_null(impl._make_download_decoder(PackedStringArray(), true))

	func test_null_for_identity_encoding() -> void:
		var headers := PackedStringArray(["Content-Encoding: identity"])
		assert_null(impl._make_download_decoder(headers, true))

	func test_decoder_for_gzip() -> void:
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		assert_not_null(impl._make_download_decoder(headers, true))

	func test_null_for_deflate() -> void:
		# Deflate is intentionally unsupported, so it never gets a decoder — the raw
		# bytes stream to disk unchanged.
		var headers := PackedStringArray(["Content-Encoding: deflate"])
		assert_null(impl._make_download_decoder(headers, true))


## Tests for in-memory body decompression ([method _Impl._maybe_decompress_body]).
class TestMaybeDecompressBody extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_decompresses_gzip_when_enabled() -> void:
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, -1
		)
		assert_eq(result, original)

	func test_deflate_response_is_not_decoded() -> void:
		# Deflate is intentionally unsupported: a deflate-encoded body is returned
		# raw rather than decoded, since we never request deflate in the first place.
		var compressed := "In-memory deflate body.".to_utf8_buffer().compress(
			FileAccess.COMPRESSION_DEFLATE
		)
		var headers := PackedStringArray(["Content-Encoding: deflate"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, -1
		)
		assert_eq(result, compressed)

	func test_leaves_compressed_body_raw_when_disabled() -> void:
		# Regression guard: with accept_gzip off, a compressed body is returned
		# untouched — never silently decoded.
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, false, -1
		)
		assert_eq(result, compressed)

	func test_unchanged_when_no_encoding_header() -> void:
		var body := "plain body".to_utf8_buffer()
		var result: Variant = impl._maybe_decompress_body(
			body, PackedStringArray(), true, -1
		)
		assert_eq(result, body)

	func test_unchanged_when_empty() -> void:
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			PackedByteArray(), headers, true, -1
		)
		assert_eq(result, PackedByteArray())

	# A real, valid gzip member whose decompressed content is empty — what a server
	# emits for an empty gzipped body. (PackedByteArray().compress() shortcuts empty
	# input to zero bytes, so it can't stand in for this; we need a genuine member.)
	func _empty_content_gzip() -> PackedByteArray:
		return PackedByteArray([
			0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x03, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x00,
		])

	func test_empty_gzipped_body_with_limit_is_ok() -> void:
		# Regression guard: a gzipped body that decodes to empty must not be mistaken
		# for an over-limit body. An empty result can never exceed a non-negative cap.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			_empty_content_gzip(), headers, true, 1024
		)
		assert_false(
			result is C3HTTPRequest.RequestError, "empty body must not error"
		)
		assert_eq(result, PackedByteArray())

	func test_empty_gzipped_body_no_limit_is_ok() -> void:
		# Without a limit, an empty gzipped body decodes to empty — not the raw
		# compressed bytes handed back undecoded.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			_empty_content_gzip(), headers, true, -1
		)
		assert_eq(result, PackedByteArray())

	func test_decompresses_within_limit() -> void:
		# A body that fits under the cap decodes normally — the limit only rejects
		# output that exceeds it.
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, 1024
		)
		assert_eq(result, original)

	func test_fails_when_decompressed_output_exceeds_limit() -> void:
		# Zip-bomb guard: 100 KB of zeros collapses to a ~130-byte gzip body that
		# passes any reasonable compressed-bytes check, then expands ~750x on decode.
		# With body_size_limit set, the streaming decoder's budget stops well short of
		# the full output and the post-decode check returns BODY_SIZE_LIMIT_EXCEEDED,
		# so the caller surfaces ok == false rather than an unbounded body.
		var original := PackedByteArray()
		original.resize(100000)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, 1024
		)
		assert_is(result, C3HTTPRequest.RequestError)
		assert_eq(
			(result as C3HTTPRequest.RequestError).kind,
			C3HTTPRequest.RequestError.Kind.BODY_SIZE_LIMIT_EXCEEDED
		)

	func test_corrupt_gzip_body_fails() -> void:
		# A garbage body labelled gzip can't be decoded; the streaming decoder reports
		# a decode error, which surfaces as a TRANSPORT failure (matching the download
		# branch) rather than being passed through as raw bytes.
		var garbage := PackedByteArray(
			[0x1f, 0x8b, 0x08, 0xff, 0xde, 0xad, 0xbe, 0xef]
		)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			garbage, headers, true, -1
		)
		assert_is(result, C3HTTPRequest.RequestError)
		assert_eq(
			(result as C3HTTPRequest.RequestError).kind,
			C3HTTPRequest.RequestError.Kind.TRANSPORT
		)
		# StreamPeerGZIP logs an engine error on malformed input; assert it so GUT
		# treats the expected log as handled rather than an unexpected failure.
		assert_engine_error("Returning: FAILED")


# A minimal loopback HTTP/1.1 server that announces a large Content-Length but
# only sends a short body prefix, then holds the connection open. This drives a
# real HTTPClient into STATUS_BODY (so the body-reading loop runs) without ever
# completing the response, letting a test abort the transfer mid-stream. Runs on
# its own thread so it can feed the socket while the client polls on the main
# thread.
class _PartialBodyServer:
	var port := 0
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	# Starts listening on a free loopback port and returns it, or 0 on failure.
	func start() -> int:
		for candidate in range(49500, 49600):
			if _server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				break
		if port == 0:
			return 0
		_thread.start(_serve)
		return port

	func stop() -> void:
		_stop = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_server.stop()

	func _serve() -> void:
		var peer: StreamPeerTCP = null
		while not _stop:
			if _server.is_connection_available():
				peer = _server.take_connection()
				break
			OS.delay_msec(5)
		if peer == null:
			return
		# Read (and discard) the request bytes so the client's send completes.
		var deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline:
			peer.poll()
			var available := peer.get_available_bytes()
			if available > 0:
				peer.get_data(available)
				break
			OS.delay_msec(5)
		# Promise 1000 bytes but send only a short prefix, then stall with the
		# connection open so the client sits in STATUS_BODY.
		var header := (
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Length: 1000\r\n"
			+ "Content-Type: application/octet-stream\r\n\r\n"
		)
		peer.put_data(header.to_utf8_buffer())
		peer.put_data("PARTIAL\n".to_utf8_buffer())
		while not _stop:
			peer.poll()
			OS.delay_msec(10)
		peer.disconnect_from_host()


## Integration tests asserting that aborting a download mid-stream deletes the
## partial file. These run a real HTTPClient against [_PartialBodyServer].
class TestDownloadFileCleanup extends GutTest:
	const _DOWNLOAD_PATH := "user://test_partial_download.bin"

	var _server: _PartialBodyServer

	func before_each() -> void:
		_server = _PartialBodyServer.new()
		if FileAccess.file_exists(_DOWNLOAD_PATH):
			DirAccess.remove_absolute(_DOWNLOAD_PATH)

	func after_each() -> void:
		_server.stop()
		if FileAccess.file_exists(_DOWNLOAD_PATH):
			DirAccess.remove_absolute(_DOWNLOAD_PATH)

	func _url() -> String:
		var port := _server.start()
		assert_ne(port, 0, "server failed to bind a port")
		return "http://127.0.0.1:%d/" % port

	func test_timeout_removes_partial_download_file() -> void:
		var url := _url()
		var opts := C3HTTPRequest.Options.new()
		opts.download_file = _DOWNLOAD_PATH
		opts.timeout = 0.2
		var res: C3HTTPRequest.Response = await (
			C3HTTPRequest
			. _Impl
			. new()
			. execute(url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.TIMEOUT)
		assert_false(
			FileAccess.file_exists(_DOWNLOAD_PATH),
			"partial download file should be deleted on timeout"
		)

	func test_cancellation_removes_partial_download_file() -> void:
		var url := _url()
		var token := C3HTTPRequest.CancellationToken.new()
		var opts := C3HTTPRequest.Options.new()
		opts.download_file = _DOWNLOAD_PATH
		opts.timeout = 5.0
		opts.cancellation_token = token
		# Cancel as soon as the first body bytes land — by then the partial file
		# exists, so the cancel path must clean it up.
		opts.on_progress = func(_received: int, _total: int) -> void:
			token.cancel()
		var res: C3HTTPRequest.Response = await (
			C3HTTPRequest
			. _Impl
			. new()
			. execute(url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.CANCELLED)
		assert_false(
			FileAccess.file_exists(_DOWNLOAD_PATH),
			"partial download file should be deleted on cancellation"
		)

	func test_no_file_created_when_aborted_before_body() -> void:
		# A request that fails before any body arrives must never create (and so never
		# truncate) the download file. We cancel while still connecting — past the point
		# the file was historically opened, but before the body phase. 192.0.2.1 is
		# TEST-NET-1 (RFC 5737): guaranteed unroutable, so the connection stays pending
		# (no DNS, no server, no completion), giving the poll loop a chance to yield once
		# — where _CancelWhileConnectingImpl cancels.
		var token := C3HTTPRequest.CancellationToken.new()
		var impl := _CancelWhileConnectingImpl.new()
		impl.token = token
		var opts := C3HTTPRequest.Options.new()
		opts.download_file = _DOWNLOAD_PATH
		opts.cancellation_token = token
		opts.timeout = 5.0  # safety net; the cancel fires on the first poll yield
		var res: C3HTTPRequest.Response = await impl.execute(
			"http://192.0.2.1/",
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		assert_false(res.ok)
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.CANCELLED)
		assert_false(
			FileAccess.file_exists(_DOWNLOAD_PATH),
			"no download file should be created when the request aborts before the body phase"
		)

	# Cancels its own request the first time the poll loop yields — i.e. while still
	# connecting, before any response or body. Lets a test reach a pre-body early
	# return deterministically, without depending on connection timing.
	class _CancelWhileConnectingImpl extends C3HTTPRequest._Impl:
		var token: C3HTTPRequest.CancellationToken

		func _pump(tree: SceneTree, on_worker: bool) -> void:
			token.cancel()
			await super._pump(tree, on_worker)
