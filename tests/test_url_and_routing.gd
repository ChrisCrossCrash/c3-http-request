extends GutTest


## Unit tests for redirect method and body downgrade logic.
class TestRedirectSemantics extends GutTest:
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

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
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

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
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

	func test_https_default_port() -> void:
		var r := impl._parse_url("https://example.com/path")
		assert_eq(r.port, 443)
		assert_true(r.tls)

	func test_http_default_port() -> void:
		var r := impl._parse_url("http://example.com/path")
		assert_eq(r.port, 80)
		assert_false(r.tls)

	func test_explicit_port() -> void:
		var r := impl._parse_url("http://localhost:8080/api")
		assert_eq(r.host, "localhost")
		assert_eq(r.port, 8080)

	func test_host_extracted() -> void:
		var r := impl._parse_url("https://api.example.com/v1/users")
		assert_eq(r.host, "api.example.com")

	func test_path_extracted() -> void:
		var r := impl._parse_url("https://example.com/v1/items")
		assert_eq(r.path, "/v1/items")

	func test_no_path_defaults_to_slash() -> void:
		var r := impl._parse_url("https://example.com")
		assert_eq(r.path, "/")

	func test_missing_scheme_returns_empty() -> void:
		assert_true(impl._parse_url("example.com/path") == null)

	func test_unsupported_scheme_returns_empty() -> void:
		assert_true(impl._parse_url("ftp://example.com") == null)

	func test_empty_host_returns_empty() -> void:
		assert_true(impl._parse_url("https:///path") == null)

	func test_fragment_stripped_from_path() -> void:
		var r := impl._parse_url("https://example.com/page#section")
		assert_eq(r.path, "/page")

	func test_fragment_stripped_after_query() -> void:
		var r := impl._parse_url("https://example.com/page?q=1#section")
		assert_eq(r.path, "/page?q=1")

	func test_ipv6_bare_address_default_port() -> void:
		var r := impl._parse_url("http://[::1]/path")
		assert_eq(r.host, "::1")
		assert_eq(r.port, 80)
		assert_false(r.tls)

	func test_ipv6_with_explicit_port() -> void:
		var r := impl._parse_url("http://[::1]:8080/path")
		assert_eq(r.host, "::1")
		assert_eq(r.port, 8080)

	func test_ipv6_https_default_port() -> void:
		var r := impl._parse_url("https://[::1]/path")
		assert_eq(r.host, "::1")
		assert_eq(r.port, 443)
		assert_true(r.tls)

	func test_ipv6_full_address() -> void:
		var r := impl._parse_url("https://[2001:db8::1]/path")
		assert_eq(r.host, "2001:db8::1")
		assert_eq(r.port, 443)

	func test_ipv6_no_path_defaults_to_slash() -> void:
		var r := impl._parse_url("http://[::1]")
		assert_eq(r.path, "/")

	func test_ipv6_unclosed_bracket_returns_empty() -> void:
		assert_true(impl._parse_url("http://[::1/path") == null)


## Tests for the per-scheme proxy routing decision in [method _Impl._resolve_proxies].
class TestResolveProxies extends GutTest:
	var impl: C3Http._Impl

	func before_each() -> void:
		impl = C3Http._Impl.new()

	func test_no_proxy_returns_empty() -> void:
		assert_true(impl._resolve_proxies(C3Http.Options.new()).is_empty())

	func test_both_schemes_routed_independently() -> void:
		var opts := C3Http.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["http"], ["http.proxy.example", 8080])
		assert_eq(proxies["https"], ["https.proxy.example", 8443])

	func test_only_http_proxy_set() -> void:
		var opts := C3Http.Options.new()
		opts.http_proxy_host = "http.proxy.example"
		opts.http_proxy_port = 8080
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["http"], ["http.proxy.example", 8080])
		assert_false(proxies.has("https"))

	func test_only_https_proxy_set() -> void:
		var opts := C3Http.Options.new()
		opts.https_proxy_host = "https.proxy.example"
		opts.https_proxy_port = 8443
		var proxies := impl._resolve_proxies(opts)
		assert_eq(proxies["https"], ["https.proxy.example", 8443])
		assert_false(proxies.has("http"))
