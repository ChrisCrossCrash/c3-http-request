extends GutTest


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
