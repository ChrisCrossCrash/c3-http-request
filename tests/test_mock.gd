extends GutTest


## Tests for [C3Http.Mock] install/uninstall lifecycle.
class TestMockLifecycle extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()

	func after_each() -> void:
		mock.uninstall()

	func test_install_sets_impl_to_mock() -> void:
		mock.install()
		assert_eq(C3Http._impl, mock)

	func test_uninstall_replaces_impl_with_non_mock() -> void:
		mock.install()
		mock.uninstall()
		assert_false(C3Http._impl is C3Http.Mock)

	func test_uninstall_without_install_is_safe() -> void:
		mock.uninstall()
		assert_false(C3Http._impl is C3Http.Mock)


## Tests for call recording: [member Mock.calls], [member Mock.call_count],
## and [member Mock.last_call].
class TestMockCallRecording extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_call_count_zero_initially() -> void:
		assert_eq(mock.call_count, 0)

	func test_last_call_empty_before_any_call() -> void:
		assert_true(mock.last_call.is_empty())

	func test_request_records_url() -> void:
		_request("https://example.com/path")
		assert_eq(mock.calls[0]["url"], "https://example.com/path")

	func test_request_records_method() -> void:
		_request("https://example.com", HTTPClient.METHOD_POST)
		assert_eq(mock.calls[0]["method"], HTTPClient.METHOD_POST)

	func test_request_records_headers() -> void:
		var headers := PackedStringArray(["X-Foo: bar"])
		mock.request(
			"https://example.com", headers,
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)
		assert_eq(mock.calls[0]["headers"], headers)

	func test_request_records_body() -> void:
		mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_POST, "hello", C3Http.Options.new()
		)
		assert_eq(mock.calls[0]["body"], "hello")

	func test_request_records_options() -> void:
		var opts := C3Http.Options.new()
		opts.timeout = 42.0
		mock.request("https://example.com", PackedStringArray(), HTTPClient.METHOD_GET, "", opts)
		assert_eq(mock.calls[0]["options"], opts)

	func test_call_count_increments() -> void:
		_request("https://example.com")
		_request("https://example.com")
		assert_eq(mock.call_count, 2)

	func test_last_call_reflects_most_recent() -> void:
		_request("https://first.example.com")
		_request("https://second.example.com")
		assert_eq(mock.last_call["url"], "https://second.example.com")

	func test_multiple_calls_all_in_log() -> void:
		_request("https://a.example.com")
		_request("https://b.example.com")
		_request("https://c.example.com")
		assert_eq(mock.calls.size(), 3)

	func _request(
		url: String, method: int = HTTPClient.METHOD_GET
	) -> C3Http.Response:
		return mock.request(
			url, PackedStringArray(), method, "", C3Http.Options.new()
		)


## Tests for [method Mock.reset].
class TestMockReset extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_reset_clears_calls() -> void:
		mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)
		mock.reset()
		assert_true(mock.calls.is_empty())

	func test_reset_clears_stubs() -> void:
		mock.stub().ok({"key": "value"})
		mock.reset()
		var res := mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)
		assert_eq(res.status, 0)
		assert_true(res.body.is_empty())


## Tests for [method _Stub.ok].
class TestStubOk extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_ok_sets_response_ok_true() -> void:
		mock.stub().ok()
		assert_true(_request().ok)

	func test_ok_default_status_is_200() -> void:
		mock.stub().ok()
		assert_eq(_request().status, 200)

	func test_ok_custom_status() -> void:
		mock.stub().ok({}, 201)
		assert_eq(_request().status, 201)

	func test_ok_json_body_round_trips() -> void:
		mock.stub().ok({"name": "Alice", "role": "admin"})
		var res := _request()
		assert_eq(res.json["name"], "Alice")
		assert_eq(res.json["role"], "admin")

	func test_ok_empty_dict_produces_valid_json() -> void:
		mock.stub().ok({})
		assert_eq(_request().json, {})

	func _request() -> C3Http.Response:
		return mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)


## Tests for [method _Stub.fail].
class TestStubFail extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_fail_sets_ok_false() -> void:
		mock.stub().fail(C3Http.RequestError.transport("err"))
		assert_false(_request().ok)

	func test_fail_passes_error_through() -> void:
		var error := C3Http.RequestError.transport("Connection refused")
		mock.stub().fail(error)
		assert_eq(_request().error, error)

	func test_fail_copies_status_from_error() -> void:
		var e := C3Http.RequestError.new()
		e.kind = C3Http.RequestError.Kind.HTTP
		e.status = 404
		e.message = "Not Found"
		mock.stub().fail(e)
		assert_eq(_request().status, 404)

	func _request() -> C3Http.Response:
		return mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)


## Tests for [method _Stub.returns].
class TestStubReturns extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_returns_passes_response_through() -> void:
		var preset := C3Http.Response.new()
		preset.ok = true
		preset.status = 202
		mock.stub().returns(preset)
		var res := mock.request(
			"https://example.com", PackedStringArray(),
			HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)
		assert_eq(res, preset)
		assert_eq(res.status, 202)


## Tests for stub URL matching via [method Mock._find_stub].
class TestStubMatching extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()

	func after_each() -> void:
		mock.uninstall()

	func test_exact_url_takes_priority_over_default() -> void:
		mock.stub().ok({"match": "default"})
		mock.stub("https://example.com/specific").ok({"match": "specific"})
		var res := _request("https://example.com/specific")
		assert_eq(res.json["match"], "specific")

	func test_default_stub_matches_when_no_exact_url() -> void:
		mock.stub().ok({"match": "default"})
		var res := _request("https://example.com/anything")
		assert_eq(res.json["match"], "default")

	func test_no_stub_returns_empty_response() -> void:
		var res := _request("https://example.com")
		assert_eq(res.status, 0)
		assert_true(res.body.is_empty())

	func test_multiple_stubs_match_correct_url() -> void:
		mock.stub("https://example.com/a").ok({"path": "a"})
		mock.stub("https://example.com/b").ok({"path": "b"})
		var res_a := _request("https://example.com/a")
		var res_b := _request("https://example.com/b")
		assert_eq(res_a.json["path"], "a")
		assert_eq(res_b.json["path"], "b")

	func test_exact_stub_does_not_match_different_url() -> void:
		mock.stub("https://example.com/specific").ok({"match": "specific"})
		var res := _request("https://example.com/other")
		assert_eq(res.status, 0)

	func _request(url: String) -> C3Http.Response:
		return mock.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", C3Http.Options.new()
		)


## Integration tests via the static [method C3Http.request] entry point.
class TestMockIntegration extends GutTest:
	var mock: C3Http.Mock

	func before_each() -> void:
		mock = C3Http.Mock.new()
		mock.install()
		mock.stub().ok({"result": "ok"})

	func after_each() -> void:
		mock.uninstall()

	func test_installed_mock_intercepts_request() -> void:
		var res := await C3Http.request("https://example.com")
		assert_true(res.ok)
		assert_eq(res.json["result"], "ok")

	func test_request_call_recorded_in_log() -> void:
		await C3Http.request("https://api.example.com/users")
		assert_eq(mock.call_count, 1)
		assert_eq(mock.last_call["url"], "https://api.example.com/users")

	func test_method_mapped_correctly() -> void:
		await C3Http.request(
			"https://example.com",
			PackedStringArray(),
			HTTPClient.METHOD_POST
		)
		assert_eq(mock.last_call["method"], HTTPClient.METHOD_POST)
