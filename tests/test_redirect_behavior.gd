extends GutTest


# Accepts one connection, returns a 302 redirect to a caller-specified URL.
class _RedirectServer:
	var port := 0
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start(location: String) -> int:
		for candidate: int in range(49700, 49750):
			if _server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				break
		if port == 0:
			return 0
		_thread.start(func() -> void: _serve(location))
		return port

	func stop() -> void:
		_stop = true
		if _thread.is_started():
			_thread.wait_to_finish()
		_server.stop()

	func _serve(location: String) -> void:
		var peer := _wait_for_connection()
		if peer == null:
			return
		_drain_request(peer)
		peer.put_data((
			"HTTP/1.1 302 Found\r\nLocation: " + location
			+ "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		).to_utf8_buffer())
		peer.disconnect_from_host()

	func _wait_for_connection() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 3000
		while not _stop and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				return _server.take_connection()
			OS.delay_msec(5)
		return null

	func _drain_request(peer: StreamPeerTCP) -> void:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					return
			OS.delay_msec(5)


# Accepts one connection, records its HTTP request headers, and returns 200 OK.
class _HeaderRecordingServer:
	var port := 0
	var recorded_headers := PackedStringArray()
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start() -> int:
		for candidate: int in range(49750, 49800):
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
		var peer := _wait_for_connection()
		if peer == null:
			return
		var raw := _read_request(peer)
		recorded_headers = _parse_request_headers(raw)
		peer.put_data(
			"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
			.to_utf8_buffer()
		)
		peer.disconnect_from_host()

	func _wait_for_connection() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 3000
		while not _stop and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				return _server.take_connection()
			OS.delay_msec(5)
		return null

	func _read_request(peer: StreamPeerTCP) -> String:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					break
			OS.delay_msec(5)
		return raw

	func _parse_request_headers(raw: String) -> PackedStringArray:
		var out := PackedStringArray()
		var lines := raw.split("\r\n")
		for i: int in range(1, lines.size()):
			var line := lines[i].strip_edges()
			if line.is_empty():
				break
			out.append(line)
		return out


# Handles two sequential connections on the same port, simulating a same-origin
# redirect. First connection gets 302 → /final on the same host:port. Second
# connection is recorded (for header inspection) and gets 200 OK.
class _SameOriginRedirectServer:
	var port := 0
	var recorded_second_request_headers := PackedStringArray()
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start() -> int:
		for candidate: int in range(49800, 49850):
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
		var peer1 := _wait_for_connection()
		if peer1 == null:
			return
		_drain_request(peer1)
		var location := "http://127.0.0.1:%d/final" % port
		peer1.put_data((
			"HTTP/1.1 302 Found\r\nLocation: " + location
			+ "\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
		).to_utf8_buffer())
		peer1.disconnect_from_host()

		var peer2 := _wait_for_connection()
		if peer2 == null:
			return
		var raw := _read_request(peer2)
		recorded_second_request_headers = _parse_request_headers(raw)
		peer2.put_data(
			"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
			.to_utf8_buffer()
		)
		peer2.disconnect_from_host()

	func _wait_for_connection() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 3000
		while not _stop and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				return _server.take_connection()
			OS.delay_msec(5)
		return null

	func _drain_request(peer: StreamPeerTCP) -> void:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					return
			OS.delay_msec(5)

	func _read_request(peer: StreamPeerTCP) -> String:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 2000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					break
			OS.delay_msec(5)
		return raw

	func _parse_request_headers(raw: String) -> PackedStringArray:
		var out := PackedStringArray()
		var lines := raw.split("\r\n")
		for i: int in range(1, lines.size()):
			var line := lines[i].strip_edges()
			if line.is_empty():
				break
			out.append(line)
		return out


# Records every distinct start_ms value passed to _timed_out(). After a redirected
# request, distinct_start_ms_count() == 1 means all hops shared one clock origin
# (correct); > 1 means each hop reset its own clock (the bug).
class _StartMsCapturingImpl extends C3HTTPRequest._Impl:
	var _seen: Array[int] = []

	func _timed_out(start_ms: int, timeout: float) -> bool:
		if start_ms not in _seen:
			_seen.append(start_ms)
		return super._timed_out(start_ms, timeout)

	func distinct_start_ms_count() -> int:
		return _seen.size()


# Runs the first execute() call normally but returns a transport error for every
# subsequent call (i.e. redirect follow-up hops). Simulates a connection failure
# on the redirected URL without needing an actual unroutable target.
class _FailOnSecondHopImpl extends C3HTTPRequest._Impl:
	var _hop := 0

	func execute(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: C3HTTPRequest.Options,
		_redirects_left: int = -1,
		_on_worker: bool = false,
		_start_ms: int = -1
	) -> C3HTTPRequest.Response:
		_hop += 1
		if _hop > 1:
			return _fail(
				C3HTTPRequest.RequestError.transport(
					"Simulated connection failure on redirect target."
				)
			)
		return await super.execute(
			url, custom_headers, method, request_data, options,
			_redirects_left, _on_worker
		)


## Cross-origin redirects (different port, host, or scheme) must strip the
## Authorization header so credentials are not leaked to unrelated servers.
class TestRedirectCrossOriginHeaders extends GutTest:
	var _redirect_server: _RedirectServer
	var _recording_server: _HeaderRecordingServer

	func before_each() -> void:
		_redirect_server = _RedirectServer.new()
		_recording_server = _HeaderRecordingServer.new()

	func after_each() -> void:
		_redirect_server.stop()
		_recording_server.stop()

	func test_authorization_not_forwarded_on_cross_origin_redirect() -> void:
		var rec_port := _recording_server.start()
		assert_ne(rec_port, 0, "recording server failed to bind")
		var redir_port := _redirect_server.start("http://127.0.0.1:%d/" % rec_port)
		assert_ne(redir_port, 0, "redirect server failed to bind")

		var res: C3HTTPRequest.Response = await (
			C3HTTPRequest
			._Impl
			.new()
			.execute(
				"http://127.0.0.1:%d/" % redir_port,
				PackedStringArray(["Authorization: Bearer secret"]),
				HTTPClient.METHOD_GET,
				"",
				C3HTTPRequest.Options.new()
			)
		)

		assert_true(res.ok)
		for header: String in _recording_server.recorded_headers:
			assert_false(
				header.to_lower().begins_with("authorization:"),
				"Authorization must not be forwarded to a cross-origin redirect target"
			)

	func test_non_sensitive_header_forwarded_on_cross_origin_redirect() -> void:
		var rec_port := _recording_server.start()
		assert_ne(rec_port, 0, "recording server failed to bind")
		var redir_port := _redirect_server.start("http://127.0.0.1:%d/" % rec_port)
		assert_ne(redir_port, 0, "redirect server failed to bind")

		await (
			C3HTTPRequest
			._Impl
			.new()
			.execute(
				"http://127.0.0.1:%d/" % redir_port,
				PackedStringArray(["X-Custom: my-value"]),
				HTTPClient.METHOD_GET,
				"",
				C3HTTPRequest.Options.new()
			)
		)

		var found := false
		for header: String in _recording_server.recorded_headers:
			if header.to_lower().begins_with("x-custom:"):
				found = true
		assert_true(found, "Non-sensitive headers must still be forwarded cross-origin")


## Same-origin redirects (same host and port) must preserve all caller headers,
## including Authorization, so authenticated API chains are not broken.
class TestRedirectSameOriginHeaders extends GutTest:
	var _server: _SameOriginRedirectServer

	func before_each() -> void:
		_server = _SameOriginRedirectServer.new()

	func after_each() -> void:
		_server.stop()

	func test_authorization_forwarded_on_same_origin_redirect() -> void:
		var p := _server.start()
		assert_ne(p, 0, "server failed to bind")

		await (
			C3HTTPRequest
			._Impl
			.new()
			.execute(
				"http://127.0.0.1:%d/" % p,
				PackedStringArray(["Authorization: Bearer secret"]),
				HTTPClient.METHOD_GET,
				"",
				C3HTTPRequest.Options.new()
			)
		)

		var found := false
		for header: String in _server.recorded_second_request_headers:
			if header.to_lower().begins_with("authorization:"):
				found = true
		assert_true(
			found,
			"Authorization must be forwarded to same-origin redirect targets"
		)


## The timeout budget must cover the entire request including all redirect hops.
## All _timed_out() checks across hops must use the same start timestamp so a
## tight timeout can fire mid-chain rather than restarting fresh on every hop.
class TestRedirectTimeoutClock extends GutTest:
	var _server: _SameOriginRedirectServer

	func before_each() -> void:
		_server = _SameOriginRedirectServer.new()

	func after_each() -> void:
		_server.stop()

	func test_timeout_clock_shared_across_redirect_hops() -> void:
		var p := _server.start()
		assert_ne(p, 0, "server failed to bind")

		var impl := _StartMsCapturingImpl.new()
		var opts := C3HTTPRequest.Options.new()
		opts.timeout = 5.0

		await impl.execute(
			"http://127.0.0.1:%d/" % p,
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)

		assert_eq(
			impl.distinct_start_ms_count(),
			1,
			(
				"All redirect hops must share one start timestamp; "
				+ "found %d distinct values" % impl.distinct_start_ms_count()
			)
		)


## After a redirect response is received, if the follow-up request fails before
## reaching the body phase, any download file created during the redirect hop
## must be cleaned up — not left on disk with stale redirect content.
class TestRedirectDownloadFileCleanup extends GutTest:
	const _DOWNLOAD_PATH := "user://test_redirect_download.bin"

	var _redirect_server: _RedirectServer

	func before_each() -> void:
		_redirect_server = _RedirectServer.new()
		if FileAccess.file_exists(_DOWNLOAD_PATH):
			DirAccess.remove_absolute(_DOWNLOAD_PATH)

	func after_each() -> void:
		_redirect_server.stop()
		if FileAccess.file_exists(_DOWNLOAD_PATH):
			DirAccess.remove_absolute(_DOWNLOAD_PATH)

	func test_download_file_not_left_after_redirect_follow_up_fails() -> void:
		# Redirect to an arbitrary location — _FailOnSecondHopImpl intercepts the
		# follow-up before making any network call, so the target URL is irrelevant.
		var redir_port := _redirect_server.start("http://127.0.0.1:1/unreachable")
		assert_ne(redir_port, 0, "redirect server failed to bind")

		var impl := _FailOnSecondHopImpl.new()
		var opts := C3HTTPRequest.Options.new()
		opts.download_file = _DOWNLOAD_PATH

		var res: C3HTTPRequest.Response = await impl.execute(
			"http://127.0.0.1:%d/" % redir_port,
			PackedStringArray(),
			HTTPClient.METHOD_GET,
			"",
			opts
		)

		assert_false(res.ok)
		assert_false(
			FileAccess.file_exists(_DOWNLOAD_PATH),
			(
				"Download file must not be left on disk when the redirect follow-up "
				+ "fails before the body phase"
			)
		)
