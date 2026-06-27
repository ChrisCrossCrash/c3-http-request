extends Node

# How many Server-Sent Events to collect before cancelling the stream.
const SSE_EVENT_COUNT := 10

# The output overlay wraps lines past this width, so SSE event lines (indent +
# "[message] " prefix + title) are truncated to fit on one line.
const SSE_LINE_MAX_LEN := 112

@onready var output_overlay: OutputOverlay = $CanvasLayer/OutputOverlay


func _ready() -> void:
	await demo_get()
	await demo_post()
	await demo_not_found()
	await demo_timeout()
	await demo_body_size_limit()
	await demo_redirect_limit()
	await demo_download_file()
	await demo_progress()
	await demo_status()
	await demo_cancellation()
	await demo_sse()
	output_overlay.print_with_overlay("\nDone.")


func demo_get() -> void:
	output_overlay.print_with_overlay("\n--- GET ---")
	# accept_gzip is true by default: Accept-Encoding: gzip is injected and
	# the response body is transparently decompressed.
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1"
	)
	if not res.ok:
		output_overlay.print_with_overlay("error: ", str(res.error))
		return
	output_overlay.print_with_overlay("status:       ", res.status)
	output_overlay.print_with_overlay("content-type: ", _header_value(res.headers, "Content-Type"))
	output_overlay.print_with_overlay("body:         ", res.text)
	# res.json parses the body once and caches it; pull out a field directly.
	var parsed: Variant = res.json
	if parsed is Dictionary:
		output_overlay.print_with_overlay("json.title:   ", parsed.get("title", ""))


func demo_post() -> void:
	output_overlay.print_with_overlay("\n--- POST ---")
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/posts",
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		'{"title": "hello", "body": "world", "userId": 1}'
	)
	if not res.ok:
		output_overlay.print_with_overlay("error: ", str(res.error))
		return
	output_overlay.print_with_overlay("status: ", res.status)
	output_overlay.print_with_overlay("body:   ", res.text)


func demo_not_found() -> void:
	output_overlay.print_with_overlay("\n--- 404 ---")
	# Any non-2xx status sets res.ok = false and populates res.error.
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/9999"
	)
	output_overlay.print_with_overlay("ok:     ", res.ok)
	output_overlay.print_with_overlay("status: ", res.status)
	output_overlay.print_with_overlay("error:  ", str(res.error))
	output_overlay.print_with_overlay("body:   ", res.text)


func demo_timeout() -> void:
	output_overlay.print_with_overlay("\n--- Timeout ---")
	# timeout lives in Options, so it is per-call and never leaks to others.
	var opts := C3HTTPRequest.Options.new()
	opts.timeout = 0.001  # 1 ms — fires before any real response arrives
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	output_overlay.print_with_overlay("ok:    ", res.ok)
	output_overlay.print_with_overlay("error: ", str(res.error))


func demo_body_size_limit() -> void:
	output_overlay.print_with_overlay("\n--- Body size limit ---")
	var opts := C3HTTPRequest.Options.new()
	opts.body_size_limit = 1000  # /posts returns ~27 KB
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/posts",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	output_overlay.print_with_overlay("ok:    ", res.ok)
	output_overlay.print_with_overlay("error: ", str(res.error))


func demo_redirect_limit() -> void:
	output_overlay.print_with_overlay("\n--- Redirect limit ---")
	# httpbin's /redirect/5 issues a 5-hop chain of 302s. With a budget of 2 we
	# stop partway and get the next 302 back: ok is false, kind is HTTP, status
	# is 302, and the message explains the budget was spent.
	var opts := C3HTTPRequest.Options.new()
	opts.max_redirects = 2
	var res := await C3HTTPRequest.request(
		"https://httpbin.org/redirect/5",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	output_overlay.print_with_overlay("ok:     ", res.ok)
	output_overlay.print_with_overlay("status: ", res.status)
	output_overlay.print_with_overlay("error:  ", str(res.error))


func demo_download_file() -> void:
	output_overlay.print_with_overlay("\n--- Download to file ---")
	var path := "user://c3_demo_download.json"
	var opts := C3HTTPRequest.Options.new()
	opts.download_file = path
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	if not res.ok:
		output_overlay.print_with_overlay("error: ", str(res.error))
		return
	# res.body is empty when download_file is set — data went straight to disk.
	output_overlay.print_with_overlay("res.body empty: ", res.body.is_empty())
	output_overlay.print_with_overlay("file:           ", FileAccess.get_file_as_string(path).strip_edges())


func demo_progress() -> void:
	output_overlay.print_with_overlay("\n--- Download progress ---")
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
			output_overlay.print_with_overlay("progress: %d / %d bytes (%d%%)" % [
				bytes_received, total_bytes, percent
			])
		else:
			# Chunked responses have no Content-Length, so total_bytes is -1.
			output_overlay.print_with_overlay("progress: %d bytes (total unknown)" % bytes_received)
	var res := await C3HTTPRequest.request(
		"https://httpbin.org/bytes/102400",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	if not res.ok:
		output_overlay.print_with_overlay("error: ", str(res.error))
		return
	output_overlay.print_with_overlay("status:     ", res.status)
	output_overlay.print_with_overlay("downloaded: ", res.body.size(), " bytes")


func demo_status() -> void:
	output_overlay.print_with_overlay("\n--- Connection status ---")
	# on_status_changed fires as the underlying HTTPClient advances through its
	# lifecycle — resolving, connecting, requesting, then reading the body. It is
	# observational only; the request's outcome still arrives via the Response.
	var opts := C3HTTPRequest.Options.new()
	opts.on_status_changed = func(status: HTTPClient.Status) -> void:
		output_overlay.print_with_overlay("status: ", _status_name(status))
	var res := await C3HTTPRequest.request(
		"https://jsonplaceholder.typicode.com/todos/1",
		PackedStringArray(),
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	output_overlay.print_with_overlay("ok:     ", res.ok)
	output_overlay.print_with_overlay("status: ", res.status)


func demo_cancellation() -> void:
	output_overlay.print_with_overlay("\n--- Cancellation ---")
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
		HTTPClient.METHOD_GET,
		"",
		opts
	)
	output_overlay.print_with_overlay("ok:    ", res.ok)
	output_overlay.print_with_overlay("error: ", str(res.error))


func demo_sse() -> void:
	output_overlay.print_with_overlay("\n--- Server-Sent Events ---")
	# Wikimedia EventStreams is a real, public, never-ending SSE feed of recent
	# wiki edits (https://stream.wikimedia.org). Setting Options.on_sse_event parses
	# the response as a stream and fires the callback per event; the await resolves
	# only once the stream closes. Since the feed never ends, we cancel the token
	# from inside the callback after SSE_EVENT_COUNT events to keep the demo bounded.
	#
	# The while loop is a reconnect loop: SSE connections are routinely severed
	# (servers and proxies often cap a response at 30-60 s), and a long-lived
	# consumer is expected to resume by echoing the last event's id back as a
	# Last-Event-ID header after waiting the server's suggested retry backoff. In
	# practice the reconnect branch won't fire here — Wikimedia doesn't cap
	# connection time, so a single connection delivers all SSE_EVENT_COUNT events
	# before we cancel — but the loop shows the shape a production consumer needs.
	#
	# Single-element Arrays so the callback's writes are visible out here: GDScript
	# lambdas capture value types (like an int or String) by copy, but Array by
	# reference.
	var token := C3HTTPRequest.CancellationToken.new()
	var last_id := [""]
	var counter := [0]
	var res: C3HTTPRequest.Response = null
	while true:
		var headers := PackedStringArray([
			"User-Agent: c3-http-request-demo (https://github.com)"
		])
		if not last_id[0].is_empty():
			headers.append("Last-Event-ID: " + last_id[0])
		var opts := C3HTTPRequest.Options.new()
		opts.cancellation_token = token
		opts.on_sse_event = func(data: String, event_type: String, id: String) -> void:
			last_id[0] = id  # remember where to resume from
			counter[0] += 1
			var title := "?"
			var parsed: Variant = JSON.parse_string(data)
			if parsed is Dictionary:
				title = str(parsed.get("title", "?"))
			# Indent event lines two spaces so they read as a block, set apart from
			# the reconnect notices below even without relying on color.
			var line := "  [%s] %s" % [event_type, title]
			if line.length() > SSE_LINE_MAX_LEN:
				line = line.substr(0, SSE_LINE_MAX_LEN - 1) + "…"
			output_overlay.print_with_overlay(line)
			if counter[0] >= SSE_EVENT_COUNT:
				token.cancel()
		res = await C3HTTPRequest.request(
			"https://stream.wikimedia.org/v2/stream/recentchange",
			headers,
			HTTPClient.METHOD_GET,
			"",
			opts
		)
		# We hit our quota and cancelled on purpose — stop, don't reconnect.
		if counter[0] >= SSE_EVENT_COUNT:
			break
		# The stream closed on its own: honor the server's backoff hint if any,
		# else fall back, then reconnect from the last id seen.
		var backoff_ms := res.sse_retry_ms if res.sse_retry_ms >= 0 else 3000
		# A clean close (EOF on a 2xx) leaves res.error null; avoid printing "<null>".
		var reason := str(res.error) if res.error != null else "closed"
		output_overlay.print_rich_with_overlay(
			"[color=gold]↻ stream ended (%s) — reconnecting in %d ms…[/color]"
			% [reason, backoff_ms]
		)
		await get_tree().create_timer(backoff_ms / 1000.0).timeout
	# Cancelling is how we chose to end the stream, so ok is false with a
	# CANCELLED error here — that is the expected, successful outcome.
	output_overlay.print_with_overlay("received: ", counter[0], " events")
	output_overlay.print_with_overlay("ended ok: ", res.ok)
	output_overlay.print_with_overlay("error:    ", str(res.error))


func _status_name(status: HTTPClient.Status) -> String:
	match status:
		HTTPClient.STATUS_DISCONNECTED: return "DISCONNECTED"
		HTTPClient.STATUS_RESOLVING: return "RESOLVING"
		HTTPClient.STATUS_CANT_RESOLVE: return "CANT_RESOLVE"
		HTTPClient.STATUS_CONNECTING: return "CONNECTING"
		HTTPClient.STATUS_CANT_CONNECT: return "CANT_CONNECT"
		HTTPClient.STATUS_CONNECTED: return "CONNECTED"
		HTTPClient.STATUS_REQUESTING: return "REQUESTING"
		HTTPClient.STATUS_BODY: return "BODY"
		HTTPClient.STATUS_CONNECTION_ERROR: return "CONNECTION_ERROR"
		HTTPClient.STATUS_TLS_HANDSHAKE_ERROR: return "TLS_HANDSHAKE_ERROR"
	return "UNKNOWN(%d)" % status


func _header_value(headers: PackedStringArray, header_name: String) -> String:
	var prefix := header_name.to_lower() + ": "
	for h: String in headers:
		if h.to_lower().begins_with(prefix):
			return h.substr(prefix.length()).strip_edges()
	return ""
