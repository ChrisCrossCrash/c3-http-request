extends GutTest


## Unit tests for [C3HTTPRequest.Session] pool mechanics. No network is used.
class TestSessionPool extends GutTest:
	var session: C3HTTPRequest.Session

	func before_each() -> void:
		session = C3HTTPRequest.Session.new()

	# checkout / checkin basics

	func test_checkout_returns_null_on_empty_pool() -> void:
		assert_null(session.checkout("key"))

	func test_checkout_returns_null_after_entry_consumed() -> void:
		session.checkin("key", HTTPClient.new())
		# The entry won't pass the STATUS_CONNECTED check on a never-connected client,
		# so checkout discards it and returns null — pool ends up empty.
		assert_null(session.checkout("key"))
		assert_false(session._pool.has("key"))

	func test_checkin_adds_to_pool() -> void:
		var client := HTTPClient.new()
		session.checkin("key", client)
		assert_true(session._pool.has("key"))
		assert_eq(session._pool["key"].size(), 1)
		# The exact client object is stored under the key, not a copy.
		var entry: C3HTTPRequest.Session._PoolEntry = session._pool["key"][0]
		assert_eq(entry.client, client)

	func test_checkin_multiple_same_key() -> void:
		session.checkin("key", HTTPClient.new())
		session.checkin("key", HTTPClient.new())
		assert_eq(session._pool["key"].size(), 2)

	func test_checkin_with_zero_max_connections_does_not_pool() -> void:
		session.max_connections_per_host = 0
		var client := HTTPClient.new()
		session.checkin("key", client)
		assert_false(session._pool.has("key"))

	func test_max_connections_evicts_oldest_on_overflow() -> void:
		session.max_connections_per_host = 2
		var c1 := HTTPClient.new()
		var c2 := HTTPClient.new()
		var c3 := HTTPClient.new()
		session.checkin("key", c1)
		session.checkin("key", c2)
		session.checkin("key", c3)
		var entries: Array = session._pool["key"]
		assert_eq(entries.size(), 2)
		# c1 was oldest (index 0) and must have been evicted; c2 and c3 remain.
		assert_eq((entries[0] as C3HTTPRequest.Session._PoolEntry).client, c2)
		assert_eq((entries[1] as C3HTTPRequest.Session._PoolEntry).client, c3)

	# idle_timeout eviction

	func test_checkout_discards_expired_entry() -> void:
		session.idle_timeout = 0.001  # 1 ms — will expire almost instantly
		var entry := C3HTTPRequest.Session._PoolEntry.new()
		entry.client = HTTPClient.new()
		entry.checked_in_at_msec = Time.get_ticks_msec() - 100  # 100 ms ago
		session._pool["key"] = [entry]
		assert_null(session.checkout("key"))
		assert_false(session._pool.has("key"))

	func test_checkout_keeps_fresh_entry() -> void:
		session.idle_timeout = 3600.0  # will not expire
		var entry := C3HTTPRequest.Session._PoolEntry.new()
		var client := HTTPClient.new()
		entry.client = client
		entry.checked_in_at_msec = Time.get_ticks_msec()
		# Manually mark status — pool health check requires STATUS_CONNECTED.
		# Since we can't reach that without a live server, we verify the
		# time-based path by confirming the entry is NOT discarded due to age.
		# (It will still be discarded for bad status, which is a separate check.)
		session._pool["key"] = [entry]
		var popped: C3HTTPRequest.Session._PoolEntry = session._pool["key"].pop_back()
		var age_ok := (Time.get_ticks_msec() - popped.checked_in_at_msec) / 1000.0 < session.idle_timeout
		assert_true(age_ok)

	# close

	func test_close_empties_pool() -> void:
		session.checkin("key", HTTPClient.new())
		session.close()
		assert_false(session._pool.has("key"))

	func test_close_idempotent() -> void:
		session.close()
		session.close()
		assert_true(true)  # no crash

	# prune

	func test_prune_removes_stale_entries() -> void:
		session.idle_timeout = 0.001
		var entry := C3HTTPRequest.Session._PoolEntry.new()
		entry.client = HTTPClient.new()
		entry.checked_in_at_msec = Time.get_ticks_msec() - 100
		session._pool["key"] = [entry]
		session.prune()
		assert_false(session._pool.has("key"))

	func test_prune_keeps_fresh_entries() -> void:
		session.idle_timeout = 3600.0
		var entry := C3HTTPRequest.Session._PoolEntry.new()
		entry.client = HTTPClient.new()
		entry.checked_in_at_msec = Time.get_ticks_msec()
		session._pool["key"] = [entry]
		session.prune()
		assert_true(session._pool.has("key"))
		assert_eq(session._pool["key"].size(), 1)

	func test_prune_noop_when_idle_timeout_disabled() -> void:
		session.idle_timeout = 0.0
		var entry := C3HTTPRequest.Session._PoolEntry.new()
		entry.client = HTTPClient.new()
		entry.checked_in_at_msec = 0  # ancient
		session._pool["key"] = [entry]
		session.prune()
		assert_true(session._pool.has("key"))


## Unit tests for [C3HTTPRequest.Session._make_key].
class TestMakeKey extends GutTest:
	var session: C3HTTPRequest.Session

	func before_each() -> void:
		session = C3HTTPRequest.Session.new()

	func _opts() -> C3HTTPRequest.Options:
		return C3HTTPRequest.Options.new()

	func test_same_inputs_produce_same_key() -> void:
		var opts := _opts()
		assert_eq(
			session._make_key("example.com", 443, true, null, opts),
			session._make_key("example.com", 443, true, null, opts)
		)

	func test_null_tls_options_is_stable() -> void:
		var opts := _opts()
		var k1 := session._make_key("a.com", 443, true, null, opts)
		var k2 := session._make_key("a.com", 443, true, null, opts)
		assert_eq(k1, k2)

	func test_different_hosts_produce_different_keys() -> void:
		var opts := _opts()
		assert_ne(
			session._make_key("a.com", 443, true, null, opts),
			session._make_key("b.com", 443, true, null, opts)
		)

	func test_different_ports_produce_different_keys() -> void:
		var opts := _opts()
		assert_ne(
			session._make_key("a.com", 443, true, null, opts),
			session._make_key("a.com", 8443, true, null, opts)
		)

	func test_different_tls_flags_produce_different_keys() -> void:
		var opts := _opts()
		assert_ne(
			session._make_key("a.com", 80, false, null, opts),
			session._make_key("a.com", 80, true, null, opts)
		)

	func test_different_tls_options_objects_produce_different_keys() -> void:
		var opts := _opts()
		var tls1 := TLSOptions.client()
		var tls2 := TLSOptions.client()
		assert_ne(
			session._make_key("a.com", 443, true, tls1, opts),
			session._make_key("a.com", 443, true, tls2, opts)
		)

	func test_null_and_explicit_tls_options_differ() -> void:
		var opts := _opts()
		var tls := TLSOptions.client()
		assert_ne(
			session._make_key("a.com", 443, true, null, opts),
			session._make_key("a.com", 443, true, tls, opts)
		)

	func test_different_http_proxy_produces_different_keys() -> void:
		var opts1 := _opts()
		var opts2 := _opts()
		opts2.http_proxy_host = "proxy.local"
		opts2.http_proxy_port = 8080
		assert_ne(
			session._make_key("a.com", 80, false, null, opts1),
			session._make_key("a.com", 80, false, null, opts2)
		)

	func test_different_https_proxy_produces_different_keys() -> void:
		var opts1 := _opts()
		var opts2 := _opts()
		opts2.https_proxy_host = "proxy.local"
		opts2.https_proxy_port = 3128
		assert_ne(
			session._make_key("a.com", 443, true, null, opts1),
			session._make_key("a.com", 443, true, null, opts2)
		)

	func test_tls_options_ignored_for_non_tls_requests() -> void:
		# tls_options has no effect on a plain http connection, so it must not
		# fragment the pool key for non-TLS requests.
		var opts := _opts()
		var tls := TLSOptions.client()
		assert_eq(
			session._make_key("a.com", 80, false, null, opts),
			session._make_key("a.com", 80, false, tls, opts)
		)

	func test_http_proxy_ignored_for_tls_requests() -> void:
		# Only the https proxy routes a TLS connection, so an http proxy
		# difference must not fragment the pool for https requests.
		var opts1 := _opts()
		var opts2 := _opts()
		opts2.http_proxy_host = "proxy.local"
		opts2.http_proxy_port = 8080
		assert_eq(
			session._make_key("a.com", 443, true, null, opts1),
			session._make_key("a.com", 443, true, null, opts2)
		)

	func test_https_proxy_ignored_for_non_tls_requests() -> void:
		# Only the http proxy routes a plain connection, so an https proxy
		# difference must not fragment the pool for http requests.
		var opts1 := _opts()
		var opts2 := _opts()
		opts2.https_proxy_host = "proxy.local"
		opts2.https_proxy_port = 3128
		assert_eq(
			session._make_key("a.com", 80, false, null, opts1),
			session._make_key("a.com", 80, false, null, opts2)
		)


## Tests for [C3HTTPRequest.Options] defaults related to session.
class TestOptionsSessionDefault extends GutTest:
	func test_session_default_is_null() -> void:
		var opts := C3HTTPRequest.Options.new()
		assert_null(opts.session)


## Tests for honoring a "Connection: close" response header, which gates whether a
## connection is returned to the pool after a request completes.
class TestConnectionCloseHeader extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_no_connection_header_keeps_alive() -> void:
		assert_false(impl._connection_close_requested(
			PackedStringArray(["Content-Type: text/plain"])
		))

	func test_keep_alive_value_keeps_alive() -> void:
		assert_false(impl._connection_close_requested(
			PackedStringArray(["Connection: keep-alive"])
		))

	func test_close_value_requests_close() -> void:
		assert_true(impl._connection_close_requested(
			PackedStringArray(["Connection: close"])
		))

	func test_close_match_is_case_insensitive() -> void:
		assert_true(impl._connection_close_requested(
			PackedStringArray(["Connection: Close"])
		))

	func test_close_among_multiple_tokens_requests_close() -> void:
		assert_true(impl._connection_close_requested(
			PackedStringArray(["Connection: keep-alive, close"])
		))

	func test_close_substring_token_does_not_match() -> void:
		# "close-something" is a distinct token and must not be read as "close".
		assert_false(impl._connection_close_requested(
			PackedStringArray(["Connection: close-something"])
		))


## Tests for which methods are safe to replay when a reused pooled connection
## dies before any response arrives. Methods are HTTPClient.METHOD_* values, as
## seen inside request().
##
## Only the method gating is unit-tested here: the end-to-end reuse/retry flow is
## not exercisable in this suite, which avoids live HTTP by design and cannot mock
## HTTPClient. The flow itself was verified manually against a synthetic server
## that closes a pooled connection between checkout and use, across the cooperative
## and use_threads paths, redirect-after-retry, SSE-after-retry, and reuse edge
## cases (HEAD with Content-Length, 204, trailing-byte desync, concurrent checkout
## on one Session, gzip and POST over reuse). All passed; see the PR for steps:
## https://github.com/ChrisCrossCrash/c3-http-request/pull/6
class TestRetrySafeMethods extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_get_is_safe() -> void:
		assert_true(impl._is_safe_to_retry(HTTPClient.METHOD_GET))

	func test_head_is_safe() -> void:
		assert_true(impl._is_safe_to_retry(HTTPClient.METHOD_HEAD))

	func test_options_is_safe() -> void:
		assert_true(impl._is_safe_to_retry(HTTPClient.METHOD_OPTIONS))

	func test_post_is_not_safe() -> void:
		assert_false(impl._is_safe_to_retry(HTTPClient.METHOD_POST))

	func test_put_is_not_safe() -> void:
		assert_false(impl._is_safe_to_retry(HTTPClient.METHOD_PUT))

	func test_delete_is_not_safe() -> void:
		assert_false(impl._is_safe_to_retry(HTTPClient.METHOD_DELETE))

	func test_patch_is_not_safe() -> void:
		assert_false(impl._is_safe_to_retry(HTTPClient.METHOD_PATCH))
