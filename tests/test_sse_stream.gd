extends GutTest


## Integration tests for SSE streaming behavior that needs a live connection,
## using a local TCP server (the parser itself is unit-tested in
## test_sse_parsing.gd). Covers the failure paths through request(), which the
## pure parser tests can't reach.
class TestSSEStream extends GutTest:
	var _server: _IdleSSEServer

	func before_each() -> void:
		_server = _IdleSSEServer.new()

	func after_each() -> void:
		_server.stop()

	# A stream that sends a retry: hint and then stalls must surface that hint on
	# the timed-out Response — the idle timeout is how a severed long-lived stream
	# usually ends, and it's exactly when a reconnecting caller needs the backoff.
	func test_idle_timeout_preserves_parsed_retry() -> void:
		var port := _server.start("retry: 5000\n\n")
		assert_ne(port, 0, "server failed to bind")

		var opts := C3HTTPRequest.Options.new()
		opts.timeout = 0.5  # idle timeout: the server sends the retry block, then stalls
		opts.on_sse_event = func(_data: String, _event_type: String, _id: String) -> void:
			pass

		var res: C3HTTPRequest.Response = await (
			C3HTTPRequest
			._Impl
			.new()
			.request(
				"http://127.0.0.1:%d/" % port,
				PackedStringArray(),
				HTTPClient.METHOD_GET,
				"",
				opts
			)
		)

		assert_false(res.ok, "a stalled stream should time out")
		assert_eq(res.error.kind, C3HTTPRequest.RequestError.Kind.TIMEOUT)
		assert_eq(res.sse_retry_ms, 5000, "the parsed retry: hint must survive the timeout")


# Accepts one connection, sends a 200 text/event-stream response (chunked) with a
# caller-supplied SSE preamble, then holds the socket open and idle — never
# sending the terminating chunk — so the client hits its idle timeout rather than
# a clean stream close.
class _IdleSSEServer:
	var port := 0
	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false
	var _preamble := ""

	func start(preamble: String) -> int:
		for candidate: int in range(38900, 39000):
			if _server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				break
		if port == 0:
			return 0
		_preamble = preamble
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
		_drain_request(peer)
		# Chunked so the client stays in STATUS_BODY awaiting more chunks; the
		# preamble is ASCII, so its character count is its byte length.
		var chunk := "%x\r\n%s\r\n" % [_preamble.length(), _preamble]
		peer.put_data((
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Type: text/event-stream\r\n"
			+ "Transfer-Encoding: chunked\r\n\r\n"
			+ chunk
		).to_utf8_buffer())
		# Stall: stay connected but send nothing more until the client gives up or
		# the test tears us down.
		var deadline := Time.get_ticks_msec() + 5000
		while not _stop and Time.get_ticks_msec() < deadline:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			OS.delay_msec(10)
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
