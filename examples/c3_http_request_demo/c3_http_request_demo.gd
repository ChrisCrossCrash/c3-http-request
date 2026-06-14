extends Node


func _ready() -> void:
	await demo_get()
	await demo_post()
	await demo_not_found()
	await demo_timeout()
	await demo_body_size_limit()
	await demo_download_file()
	await demo_cancellation()
	print("\nDone.")


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
	print("body:         ", res.body)


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
	print("body:   ", res.body)


func demo_not_found() -> void:
	print("\n--- 404 ---")
	# Any non-2xx status sets res.ok = false and populates res.error.
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/9999"
	)
	print("ok:     ", res.ok)
	print("status: ", res.status)
	print("error:  ", str(res.error))
	print("body:   ", res.body)


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


func _header_value(headers: PackedStringArray, name: String) -> String:
	var prefix := name.to_lower() + ": "
	for h: String in headers:
		if h.to_lower().begins_with(prefix):
			return h.substr(prefix.length()).strip_edges()
	return ""
