extends Node


func _ready() -> void:
	await demo_get()
	await demo_post()
	await demo_not_found()
	await demo_timeout()
	await demo_body_size_limit()
	await demo_download_file()
	await demo_progress()
	await demo_cancellation()
	await demo_sse()
	print("\nDone.")
	get_tree().quit()


func demo_get() -> void:
	print("\n--- GET ---")
	# accept_gzip is true by default: Accept-Encoding: gzip, deflate is
	# injected and the response body is transparently decompressed.
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1"
	)
	if not res.ok:
		print("error: ", str(res.error))
		return
	print("status:       ", res.status)
	print("content-type: ", _header_value(res.headers, "Content-Type"))
	print("body:         ", res.text)


func demo_post() -> void:
	print("\n--- POST ---")
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/posts",
		PackedStringArray(["Content-Type: application/json"]),
		C3HTTPRequest.Method.POST,
		'{"title": "hello", "body": "world", "userId": 1}'
	)
	if not res.ok:
		print("error: ", str(res.error))
		return
	print("status: ", res.status)
	print("body:   ", res.text)


func demo_not_found() -> void:
	print("\n--- 404 ---")
	# Any non-2xx status sets res.ok = false and populates res.error.
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/9999"
	)
	print("ok:     ", res.ok)
	print("status: ", res.status)
	print("error:  ", str(res.error))
	print("body:   ", res.text)


func demo_timeout() -> void:
	print("\n--- Timeout ---")
	# timeout lives in Options, so it is per-call and never leaks to others.
	var opts := C3HTTPRequest.Options.new()
	opts.timeout = 0.001  # 1 ms — fires before any real response arrives
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	print("ok:    ", res.ok)
	print("error: ", str(res.error))


func demo_body_size_limit() -> void:
	print("\n--- Body size limit ---")
	var opts := C3HTTPRequest.Options.new()
	opts.body_size_limit = 1000  # /posts returns ~27 KB
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/posts",
		PackedStringArray(),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	print("ok:    ", res.ok)
	print("error: ", str(res.error))


func demo_download_file() -> void:
	print("\n--- Download to file ---")
	var path := "user://c3_demo_download.json"
	var opts := C3HTTPRequest.Options.new()
	opts.download_file = path
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	if not res.ok:
		print("error: ", str(res.error))
		return
	# res.body is empty when download_file is set — data went straight to disk.
	print("res.body empty: ", res.body.is_empty())
	print("file:           ", FileAccess.get_file_as_string(path).strip_edges())


func demo_progress() -> void:
	print("\n--- Download progress ---")
	# httpbin returns a 100 KB body with a Content-Length, so total_bytes is
	# known and a percentage can be shown. A small download_chunk_size makes the
	# body arrive in several reads, so on_progress fires multiple times.
	# accept_gzip is disabled so the transferred bytes match the Content-Length
	# (gzip would report the compressed size instead).
	var opts := C3HTTPRequest.Options.new()
	opts.accept_gzip = false
	opts.download_chunk_size = 16384
	opts.on_progress = func(bytes_received: int, total_bytes: int) -> void:
		if total_bytes > 0:
			var percent := int(float(bytes_received) / total_bytes * 100.0)
			print("progress: %d / %d bytes (%d%%)" % [
				bytes_received, total_bytes, percent
			])
		else:
			# Chunked responses have no Content-Length, so total_bytes is -1.
			print("progress: %d bytes (total unknown)" % bytes_received)
	var res := await C3HTTPRequest.request(
		"https://httpbin.org/bytes/102400",
		PackedStringArray(),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	if not res.ok:
		print("error: ", str(res.error))
		return
	print("status:     ", res.status)
	print("downloaded: ", res.body.size(), " bytes")


func demo_cancellation() -> void:
	print("\n--- Cancellation ---")
	var token := C3HTTPRequest.CancellationToken.new()
	var opts := C3HTTPRequest.Options.new()
	opts.cancellation_token = token
	# Pre-cancel: no connection is opened at all.
	# To cancel mid-flight, call token.cancel() from another coroutine while
	# this function is suspended at the await below.
	token.cancel()
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	print("ok:    ", res.ok)
	print("error: ", str(res.error))


func demo_sse() -> void:
	print("\n--- Server-Sent Events ---")
	# Wikimedia EventStreams is a real, public, never-ending SSE feed of recent
	# wiki edits (https://stream.wikimedia.org). Setting Options.on_event parses
	# the response as a stream and fires the callback per event; the await below
	# resolves only once the stream closes. Since the feed never ends, we cancel
	# the token from inside the callback after a few events — the same mechanism
	# used to tear down any long-lived stream.
	var token := C3HTTPRequest.CancellationToken.new()
	var opts := C3HTTPRequest.Options.new()
	opts.cancellation_token = token
	# A single-element Array so the callback's mutation is visible out here:
	# lambdas capture value types (like an int) by copy, but Array by reference.
	var counter := [0]
	opts.on_event = func(data: String, event_type: String) -> void:
		counter[0] += 1
		var title := "?"
		var parsed: Variant = JSON.parse_string(data)
		if parsed is Dictionary:
			title = str(parsed.get("title", "?"))
		print("event %d [%s]: %s" % [counter[0], event_type, title])
		if counter[0] >= 3:
			token.cancel()
	var res := await C3HTTPRequest.request(
		"https://stream.wikimedia.org/v2/stream/recentchange",
		PackedStringArray(["User-Agent: c3-http-request-demo (https://github.com)"]),
		C3HTTPRequest.Method.GET,
		"",
		opts
	)
	# Cancelling is how we chose to end the stream, so ok is false with a
	# CANCELLED error here — that is the expected, successful outcome.
	print("received: ", counter[0], " events")
	print("ended ok: ", res.ok)
	print("error:    ", str(res.error))


func _header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ": "
	for h: String in headers:
		if h.to_lower().begins_with(prefix):
			return h.substr(prefix.length()).strip_edges()
	return ""
