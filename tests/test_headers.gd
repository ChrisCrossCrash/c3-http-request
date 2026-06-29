extends GutTest


## Tests for request header assembly ([method _Impl._build_request_headers]).
class TestBuildRequestHeaders extends GutTest:
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

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
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

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
