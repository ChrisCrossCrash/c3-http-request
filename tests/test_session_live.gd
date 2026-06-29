extends GutTest


## Integration tests for the Session keep-alive and connection-reuse/retry flow.
##
## The retry paths — silent-close retry (has_response() == false) and send-failure
## retry — cannot be exercised by the mock-based unit suite because HTTPClient
## cannot be mocked. These tests run real HTTPClient instances against loopback
## TCP servers, following the pattern of test_sse_stream.gd and
## test_download_file_cleanup.gd.
##
## Two server classes:
##
##   _DropServer       — serves the first request on each TCP connection normally
##                       (Connection: keep-alive), then silently closes on the
##                       second. This deterministically triggers the silent-close
##                       retry path: seed → pool → reuse → drop → _force_fresh
##                       retry → fresh connection.
##
##   _KeepAliveServer  — serves every request normally via a per-path Callable
##                       dispatcher; used for happy-path reuse and desync cases.


# Pre-computed gzip encoding of b"hello" (Python gzip.compress, compresslevel=9).
const _GZIP_HELLO: PackedByteArray = [
	31, 139, 8, 0, 0, 0, 0, 0, 2, 255, 203, 72,
	205, 201, 201, 7, 0, 134, 166, 16, 54, 5, 0, 0, 0
]


# Runs a loopback TCP server on a background thread. For each accepted TCP
# connection: the first request receives `first_headers` (+ `first_body`, omitted
# for HEAD), then the second request is drained and the socket is closed silently.
# The server loops to accept the next connection so the retry's fresh socket is
# also served (and also gets `first_headers`/`first_body`).
class _DropServer:
	var port := 0
	var first_headers := (
		"HTTP/1.1 200 OK\r\n"
		+ "Content-Type: text/plain\r\n"
		+ "Content-Length: 2\r\n"
		+ "Connection: keep-alive\r\n"
		+ "\r\n"
	)
	var first_body: PackedByteArray = "ok".to_utf8_buffer()

	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start() -> int:
		for candidate: int in range(39100, 39200):
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
		while not _stop:
			var peer := _wait_for_connection()
			if peer == null:
				break
			_handle(peer)

	func _handle(peer: StreamPeerTCP) -> void:
		# Request 1: serve normally.
		var raw1 := _drain_headers(peer)
		if raw1.is_empty():
			peer.disconnect_from_host()
			return
		var is_head := raw1.begins_with("HEAD ")
		var resp := first_headers.to_utf8_buffer()
		if not is_head:
			resp.append_array(first_body)
		peer.put_data(resp)
		# Request 2: drain then close silently, reproducing a server that drops
		# a keep-alive connection after one use.
		_drain_headers(peer)
		peer.disconnect_from_host()

	func _wait_for_connection() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 8000
		while not _stop and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				return _server.take_connection()
			OS.delay_msec(5)
		return null

	func _drain_headers(peer: StreamPeerTCP) -> String:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					return raw
			OS.delay_msec(5)
		return ""


# Runs a loopback TCP server that serves every request normally. Each connection
# is kept alive and all requests on it are dispatched via `dispatcher`:
#
#   dispatcher.call(method, path, body) -> PackedByteArray  # full HTTP response
class _KeepAliveServer:
	var port := 0
	var dispatcher: Callable

	var _server := TCPServer.new()
	var _thread := Thread.new()
	var _stop := false

	func start() -> int:
		for candidate: int in range(39200, 39300):
			if _server.listen(candidate, "127.0.0.1") == OK:
				port = candidate
				break
		if port == 0:
			return 0
		_thread.start(_serve)
		return port

	# Tracks per-connection threads so stop() can join them all.
	var _conn_threads: Array[Thread] = []

	func stop() -> void:
		_stop = true
		if _thread.is_started():
			_thread.wait_to_finish()
		for t: Thread in _conn_threads:
			if t.is_started():
				t.wait_to_finish()
		_conn_threads.clear()
		_server.stop()

	func _serve() -> void:
		while not _stop:
			var peer := _wait_for_connection()
			if peer == null:
				break
			# Spawn a thread per connection so multiple concurrent clients are
			# served in parallel rather than serially.
			var t := Thread.new()
			t.start(_handle.bind(peer))
			_conn_threads.append(t)

	func _handle(peer: StreamPeerTCP) -> void:
		while not _stop:
			var raw := _drain_headers(peer)
			if raw.is_empty():
				break
			var lines := raw.split("\r\n")
			var req_parts := (lines[0] if lines.size() > 0 else "").split(" ")
			var method := req_parts[0] if req_parts.size() > 0 else "GET"
			var path := req_parts[1] if req_parts.size() > 1 else "/"
			var body := _read_body(peer, raw)
			var response: PackedByteArray = dispatcher.call(method, path, body)
			peer.put_data(response)

	func _wait_for_connection() -> StreamPeerTCP:
		var deadline := Time.get_ticks_msec() + 8000
		while not _stop and Time.get_ticks_msec() < deadline:
			if _server.is_connection_available():
				return _server.take_connection()
			OS.delay_msec(5)
		return null

	func _drain_headers(peer: StreamPeerTCP) -> String:
		var raw := ""
		var deadline := Time.get_ticks_msec() + 5000
		while Time.get_ticks_msec() < deadline and not _stop:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var n := peer.get_available_bytes()
			if n > 0:
				var r: Array = peer.get_data(n)
				raw += (r[1] as PackedByteArray).get_string_from_utf8()
				if "\r\n\r\n" in raw:
					return raw
			OS.delay_msec(5)
		return ""

	func _read_body(peer: StreamPeerTCP, raw_headers: String) -> String:
		var content_length := 0
		for line: String in raw_headers.split("\r\n"):
			if line.to_lower().begins_with("content-length:"):
				content_length = line.split(":")[1].strip_edges().to_int()
				break
		if content_length <= 0:
			return ""
		# Body bytes may have arrived in the same TCP segment as the headers and
		# been consumed by _drain_headers. Extract anything past \r\n\r\n.
		var sep_idx := raw_headers.find("\r\n\r\n")
		var body := PackedByteArray()
		if sep_idx >= 0:
			body = raw_headers.substr(sep_idx + 4).to_utf8_buffer()
		var deadline := Time.get_ticks_msec() + 3000
		while body.size() < content_length and Time.get_ticks_msec() < deadline:
			peer.poll()
			if peer.get_status() != StreamPeerTCP.STATUS_CONNECTED:
				break
			var n := peer.get_available_bytes()
			if n > 0:
				var to_read := mini(n, content_length - body.size())
				var r: Array = peer.get_data(to_read)
				body.append_array(r[1] as PackedByteArray)
			else:
				OS.delay_msec(5)
		return body.get_string_from_utf8()


# --- Drop-server tests ---


## Verifies the silent-close retry path end-to-end in cooperative and threaded
## modes, and that methods unsafe to replay are not retried.
class TestDropRetry extends GutTest:
	var _drop: _DropServer
	var _impl: C3Http._Impl

	func before_each() -> void:
		_drop = _DropServer.new()
		_impl = C3Http._Impl.new()

	func after_each() -> void:
		_drop.stop()

	# Seeds the session with one successful GET so the connection is pooled.
	# Returns the session with the warmed pool entry, or null on seed failure.
	func _seed(url: String, use_threads: bool) -> C3Http.Session:
		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.use_threads = use_threads
		opts.timeout = 5.0
		var init_res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(init_res.ok, "seed request must succeed: %s" % str(init_res.error))
		return session

	# GET on a pooled connection the server dropped is retried transparently.
	func test_get_retry_cooperative() -> void:
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p
		var session := await _seed(url, false)

		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(res.ok, "retried GET should succeed: %s" % str(res.error))
		assert_eq(res.status, 200)
		assert_eq(res.text, "ok")

	# Same retry on a worker thread: _force_fresh recursion runs off the main thread.
	func test_get_retry_threaded() -> void:
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p
		var session := await _seed(url, true)

		var opts := C3Http.Options.new()
		opts.session = session
		opts.use_threads = true
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(res.ok, "threaded retried GET should succeed: %s" % str(res.error))
		assert_eq(res.status, 200)

	# HEAD is idempotent; confirm it recovers from a dropped pooled connection.
	func test_head_retry() -> void:
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p
		# Seed with GET so a connection is pooled, then trigger with HEAD.
		var session := await _seed(url, false)

		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_HEAD, "", opts
		)
		assert_true(res.ok, "retried HEAD should succeed: %s" % str(res.error))
		assert_eq(res.status, 200)

	# POST is not idempotent; a silent-close failure must surface as a transport error.
	func test_post_not_retried() -> void:
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p
		var session := await _seed(url, false)

		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_POST, "body", opts
		)
		assert_false(res.ok, "POST on a dropped connection must not be retried")
		assert_eq(res.error.kind, C3Http.RequestError.Kind.TRANSPORT)

	# Same gating check with use_threads=true.
	func test_post_not_retried_threaded() -> void:
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p
		var session := await _seed(url, true)

		var opts := C3Http.Options.new()
		opts.session = session
		opts.use_threads = true
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_POST, "body", opts
		)
		assert_false(res.ok, "threaded POST must not be retried")
		assert_eq(res.error.kind, C3Http.RequestError.Kind.TRANSPORT)

	# An SSE GET on a dropped pooled connection is retried transparently, and the
	# retry delivers exactly 3 events with no duplicates from the seed.
	func test_sse_retry() -> void:
		# Fixed-length SSE body so HTTPClient completes cleanly and pools the socket.
		const SSE_BODY := "data: event1\n\ndata: event2\n\ndata: event3\n\n"
		_drop.first_headers = (
			"HTTP/1.1 200 OK\r\n"
			+ "Content-Type: text/event-stream\r\n"
			+ "Content-Length: %d\r\n" % SSE_BODY.length()
			+ "Connection: keep-alive\r\n"
			+ "\r\n"
		)
		_drop.first_body = SSE_BODY.to_utf8_buffer()
		var p := _drop.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/sse/" % p

		var session := C3Http.Session.new()
		# Seed: consume 3 events and pool the connection.
		var seed_count := [0]
		var seed_opts := C3Http.Options.new()
		seed_opts.session = session
		seed_opts.timeout = 5.0
		seed_opts.on_sse_event = func(
			_data: String, _type: String, _id: String
		) -> void:
			seed_count[0] += 1
		await _impl.request(url, PackedStringArray(), HTTPClient.METHOD_GET, "", seed_opts)
		assert_eq(seed_count[0], 3, "seed should deliver 3 events")

		# Trigger: reuse → drop → retry → fresh connection → 3 events, no duplicates.
		var retry_count := [0]
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0
		opts.on_sse_event = func(
			_data: String, _type: String, _id: String
		) -> void:
			retry_count[0] += 1
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(res.ok, "SSE retry should succeed: %s" % str(res.error))
		assert_eq(
			retry_count[0], 3,
			"retry should deliver exactly 3 events, got %d" % retry_count[0]
		)


# --- Keep-alive server tests ---


## Verifies happy-path reuse and that header/body parsing does not desync across
## pooled requests (HEAD phantom bytes, 204, gzip, POST echo, concurrent).
class TestKeepAliveReuse extends GutTest:
	var _keep: _KeepAliveServer
	var _impl: C3Http._Impl

	func before_each() -> void:
		_keep = _KeepAliveServer.new()
		_impl = C3Http._Impl.new()

	func after_each() -> void:
		_keep.stop()

	# HEAD followed by GET on the same pooled connection must not corrupt parsing:
	# the GET must receive its own body, not the HEAD's Content-Length-announced
	# but never-sent bytes.
	func test_head_then_get_no_desync() -> void:
		_keep.dispatcher = func(
			method: String, _path: String, _body: String
		) -> PackedByteArray:
			if method == "HEAD":
				return (
					"HTTP/1.1 200 OK\r\n"
					+ "Content-Type: text/plain\r\n"
					+ "Content-Length: 5\r\n"
					+ "Connection: keep-alive\r\n"
					+ "\r\n"
				).to_utf8_buffer()
			return (
				"HTTP/1.1 200 OK\r\n"
				+ "Content-Type: text/plain\r\n"
				+ "Content-Length: 5\r\n"
				+ "Connection: keep-alive\r\n"
				+ "\r\nhello"
			).to_utf8_buffer()
		var p := _keep.start()
		assert_ne(p, 0)
		var base := "http://127.0.0.1:%d" % p

		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0

		var head_res: C3Http.Response = await _impl.request(
			base + "/head/", PackedStringArray(), HTTPClient.METHOD_HEAD, "", opts
		)
		assert_true(head_res.ok, "HEAD should succeed")
		assert_eq(head_res.status, 200)

		var get_res: C3Http.Response = await _impl.request(
			base + "/get/", PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(get_res.ok, "GET after HEAD should succeed")
		assert_eq(get_res.text, "hello", "GET body must not include phantom HEAD bytes")

	# 204 responses twice on the same session must both complete cleanly.
	func test_204_reuse() -> void:
		_keep.dispatcher = func(
			_method: String, _path: String, _body: String
		) -> PackedByteArray:
			return (
				"HTTP/1.1 204 No Content\r\nContent-Length: 0\r\nConnection: keep-alive\r\n\r\n"
			).to_utf8_buffer()
		var p := _keep.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/204/" % p
		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0

		var r1: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(r1.ok, "first 204 should succeed")
		assert_eq(r1.status, 204)

		var r2: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(r2.ok, "second 204 on reused connection should succeed")
		assert_eq(r2.status, 204)

	# POST body echoed correctly on first and second reuse; verifies no body
	# bytes bleed from one pooled request to the next.
	func test_post_body_reuse() -> void:
		_keep.dispatcher = func(
			_method: String, _path: String, body: String
		) -> PackedByteArray:
			var b := body.to_utf8_buffer()
			return (
				"HTTP/1.1 200 OK\r\n"
				+ "Content-Type: text/plain\r\n"
				+ "Content-Length: %d\r\n" % b.size()
				+ "Connection: keep-alive\r\n"
				+ "\r\n"
			).to_utf8_buffer() + b
		var p := _keep.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/echo/" % p
		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0

		var r1: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_POST, "hello", opts
		)
		assert_true(r1.ok, "first POST should succeed")
		assert_eq(r1.text, "hello")

		var r2: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_POST, "world", opts
		)
		assert_true(r2.ok, "second POST on reused connection should succeed")
		assert_eq(r2.text, "world", "body must not be contaminated by prior reuse")

	# A 302 redirect from a reused connection is followed correctly.
	func test_redirect_with_reuse() -> void:
		var target := _KeepAliveServer.new()
		target.dispatcher = func(
			_method: String, _path: String, _body: String
		) -> PackedByteArray:
			return (
				"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 6\r\nConnection: keep-alive\r\n\r\ntarget"
			).to_utf8_buffer()
		var tp := target.start()
		assert_ne(tp, 0, "target server failed to bind")

		_keep.dispatcher = func(
			_method: String, path: String, _body: String
		) -> PackedByteArray:
			if path == "/redirect/":
				return (
					"HTTP/1.1 302 Found\r\n"
					+ "Location: http://127.0.0.1:%d/ping/\r\n" % tp
					+ "Content-Length: 0\r\n"
					+ "Connection: keep-alive\r\n"
					+ "\r\n"
				).to_utf8_buffer()
			return (
				"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok"
			).to_utf8_buffer()
		var p := _keep.start()
		assert_ne(p, 0)

		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0

		# Seed the pool: GET /ping/ → 200 "ok".
		var seed_res: C3Http.Response = await _impl.request(
			"http://127.0.0.1:%d/ping/" % p,
			PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(seed_res.ok, "seed should succeed")

		# Reuse: /redirect/ is served from the pooled connection → 302 → target.
		var res: C3Http.Response = await _impl.request(
			"http://127.0.0.1:%d/redirect/" % p,
			PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		assert_true(res.ok, "redirect from reused connection should succeed")
		assert_eq(res.status, 200)
		assert_eq(res.text, "target")

		target.stop()

	# Gzip-encoded body is decoded correctly on first and second reuse; verifies
	# the decompressor does not desync across pooled requests.
	func test_gzip_reuse() -> void:
		var gzip_body := _GZIP_HELLO.duplicate()
		_keep.dispatcher = func(
			_method: String, _path: String, _body: String
		) -> PackedByteArray:
			return (
				"HTTP/1.1 200 OK\r\n"
				+ "Content-Type: text/plain\r\n"
				+ "Content-Encoding: gzip\r\n"
				+ "Content-Length: %d\r\n" % gzip_body.size()
				+ "Connection: keep-alive\r\n"
				+ "\r\n"
			).to_utf8_buffer() + gzip_body
		var p := _keep.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/gzip/" % p
		var session := C3Http.Session.new()
		var opts := C3Http.Options.new()
		opts.session = session
		opts.accept_gzip = true
		opts.timeout = 5.0

		var r1: C3Http.Response = await _impl.request(
			url, PackedStringArray(["Accept-Encoding: gzip"]),
			HTTPClient.METHOD_GET, "", opts
		)
		assert_true(r1.ok, "first gzip request should succeed")
		assert_eq(r1.text, "hello")

		var r2: C3Http.Response = await _impl.request(
			url, PackedStringArray(["Accept-Encoding: gzip"]),
			HTTPClient.METHOD_GET, "", opts
		)
		assert_true(r2.ok, "second gzip request on reused connection should succeed")
		assert_eq(r2.text, "hello", "gzip body must decode correctly on reuse")

	# Four concurrent GETs on one Session open four separate sockets (pool capacity
	# allows it) and all complete successfully.
	func test_concurrent_separate_sockets() -> void:
		_keep.dispatcher = func(
			_method: String, _path: String, _body: String
		) -> PackedByteArray:
			return (
				"HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: 2\r\nConnection: keep-alive\r\n\r\nok"
			).to_utf8_buffer()
		var p := _keep.start()
		assert_ne(p, 0)
		var url := "http://127.0.0.1:%d/ping/" % p

		var session := C3Http.Session.new()
		session.max_connections_per_host = 4

		const N := 4
		var done := [0]
		var successes := [0]
		for _i: int in N:
			_fire_one(url, session, done, successes)
		while done[0] < N:
			await get_tree().process_frame
		assert_eq(successes[0], N, "all %d concurrent requests should succeed" % N)

	func _fire_one(
		url: String,
		session: C3Http.Session,
		done: Array,
		successes: Array,
	) -> void:
		var opts := C3Http.Options.new()
		opts.session = session
		opts.timeout = 5.0
		var res: C3Http.Response = await _impl.request(
			url, PackedStringArray(), HTTPClient.METHOD_GET, "", opts
		)
		if res.ok:
			successes[0] += 1
		done[0] += 1
