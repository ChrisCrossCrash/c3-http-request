class_name C3HTTPRequest
## General-purpose async HTTP client that requires no scene tree.
##
## Call the static [method request] from anywhere — no [Node] to add or
## configure. Every call [code]await[/code]s a [Response] carrying
## [member Response.ok] as a single failure check that covers transport
## errors, timeouts, and non-2xx statuses alike.

## HTTP method for [method request].
enum Method { GET = 0, HEAD, POST, PUT, DELETE, OPTIONS, PATCH }

const _METHOD_MAP: Dictionary = {
	Method.GET: HTTPClient.METHOD_GET,
	Method.HEAD: HTTPClient.METHOD_HEAD,
	Method.POST: HTTPClient.METHOD_POST,
	Method.PUT: HTTPClient.METHOD_PUT,
	Method.DELETE: HTTPClient.METHOD_DELETE,
	Method.OPTIONS: HTTPClient.METHOD_OPTIONS,
	Method.PATCH: HTTPClient.METHOD_PATCH,
}

static var _impl: _Impl = _Impl.new()


## Sends an HTTP request to [param url] and returns the response. [br]
## [param custom_headers] are sent alongside any headers injected by
## [member Options.accept_gzip]. [br]
## [param method] is a [enum Method] value; defaults to [code]GET[/code]. [br]
## [param request_data] is the raw request body string. [br]
## [param options] controls timeout, redirects, and other per-request
## settings; [code]null[/code] uses all defaults.
static func request(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: Method = Method.GET,
	request_data: String = "",
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.execute(
		url, custom_headers, _METHOD_MAP[method], request_data, opts
	)


## Sends an HTTP request with a raw byte-array body, like [method request] but
## the body is sent as-is without UTF-8 encoding. Use for binary payloads
## (encoded files, serialized data, custom binary protocols). [br]
## [param request_data_raw] is the raw request body bytes. [br]
## [param method] defaults to [code]POST[/code]; a raw body is ignored on
## [code]GET[/code]. [br]
## See [method request] for the remaining parameters.
static func request_raw(
	url: String,
	custom_headers: PackedStringArray = PackedStringArray(),
	method: Method = Method.POST,
	request_data_raw: PackedByteArray = PackedByteArray(),
	options: Options = null
) -> Response:
	var opts: Options = options if options != null else Options.new()
	return await _impl.execute(
		url, custom_headers, _METHOD_MAP[method], request_data_raw, opts
	)


## Per-request configuration. Defaults match [HTTPRequest] node defaults.
class Options:
	## Maximum seconds to wait for a response. [code]0.0[/code] disables the timeout.
	var timeout: float = 0.0
	## Maximum response body size in bytes. [code]-1[/code] is unlimited.
	var body_size_limit: int = -1
	## Size of each read buffer in bytes. Lower values reduce peak memory use
	## during large downloads.
	var download_chunk_size: int = 65536
	## When [code]true[/code], sends [code]Accept-Encoding: gzip, deflate[/code]
	## and decompresses the response body automatically. Has no effect when
	## [member download_file] is set.
	var accept_gzip: bool = true
	## Maximum number of redirects to follow. [code]0[/code] disables following.
	var max_redirects: int = 8
	## Path to write the response body to on disk. When non-empty,
	## [member Response.body] is empty and the data is in the file. A partial
	## file may be left on disk if the request fails after the connection opens.
	var download_file: String = ""
	## TLS options for HTTPS connections. [code]null[/code] uses
	## [method TLSOptions.client] (validates the server certificate). Override
	## with [method TLSOptions.client_unsafe] for self-signed certificates.
	var tls_options: TLSOptions = null
	## Host of an HTTP/HTTPS proxy to route this request through. Empty means no
	## proxy (a direct connection). Applies to both [code]http://[/code] and
	## [code]https://[/code] requests.
	var proxy_host: String = ""
	## Port of the proxy named by [member proxy_host]. Ignored when
	## [member proxy_host] is empty.
	var proxy_port: int = -1
	## Token for cancelling this request from another coroutine or signal
	## handler. [code]null[/code] means no cancellation support.
	var cancellation_token: CancellationToken = null
	## Optional [Callable] invoked once per Server-Sent Event as the response
	## streams in, as
	## [code]on_event.call(data: String, event_type: String)[/code]. When set,
	## a 2xx response body is parsed as an SSE stream rather than collected:
	## [member Response.body] stays empty and [method C3HTTPRequest.request]
	## resolves only when the stream closes (use [member cancellation_token] to
	## stop it early). While streaming, [member accept_gzip] and
	## [member download_file] are ignored, and [member timeout] becomes an idle
	## timeout (maximum seconds between events) rather than a total deadline. A
	## non-2xx response is collected normally, so [member Response.ok],
	## [member Response.error], and the error body still work as usual. Both LF
	## ([code]\n\n[/code]) and CRLF ([code]\r\n\r\n[/code]) event delimiters are
	## supported.
	var on_event: Callable = Callable()
	## Optional [Callable] invoked as the response body downloads, as
	## [code]on_progress.call(bytes_received: int, total_bytes: int)[/code].
	## [code]bytes_received[/code] is the cumulative byte count;
	## [code]total_bytes[/code] is the [code]Content-Length[/code], or
	## [code]-1[/code] when unknown (e.g. a chunked response). Fires once per
	## non-empty chunk for both in-memory and [member download_file] downloads.
	## Has no effect in SSE mode (see [member on_event]), where [member on_event]
	## is the incremental signal instead.
	var on_progress: Callable = Callable()
	## Optional [Callable] invoked as the underlying connection advances, as
	## [code]on_status_changed.call(status: HTTPClient.Status)[/code] — one of
	## [code]STATUS_RESOLVING[/code], [code]STATUS_CONNECTING[/code],
	## [code]STATUS_CONNECTED[/code], [code]STATUS_REQUESTING[/code],
	## [code]STATUS_BODY[/code], etc. Fires once per change, in every mode
	## (including SSE), and repeats the cycle for each hop when redirects are
	## followed. Purely observational: the request's outcome is still reported via
	## the returned [Response]. Very brief intermediate states may be coalesced.
	var on_status_changed: Callable = Callable()


## The response returned by [method C3HTTPRequest.request].
class Response:
	## [code]true[/code] when a response was received with a 2xx status code.
	var ok := true
	## Error details when [member ok] is [code]false[/code]; [code]null[/code] otherwise.
	var error: RequestError = null
	## HTTP status code, e.g. [code]200[/code] or [code]404[/code].
	## [code]0[/code] when no HTTP response was received (transport failure).
	var status: int = 0
	## Response headers as [code]"Name: Value"[/code] strings.
	## Empty when no HTTP response was received.
	var headers: PackedStringArray = PackedStringArray()
	## Raw response body bytes. Empty when [member Options.download_file] is set
	## or when no body was received. Use [member text] for a decoded string view.
	var body: PackedByteArray = PackedByteArray()
	## The response body decoded as UTF-8. Computed lazily on first access and
	## cached, so binary responses never pay the decode cost. Returns
	## [code]""[/code] for an empty or non-UTF-8 body.
	var text: String:
		get:
			if _text_cache == null:
				_text_cache = body.get_string_from_utf8()
				if _text_cache == "" and not body.is_empty():
					push_error(
						"C3HTTPRequest: response body is not valid UTF-8."
					)
			return _text_cache

	var _text_cache: Variant = null

	## The response body parsed as JSON. Parsed lazily on first access and cached,
	## reusing the [member text] decode. On a parse failure this pushes an error
	## (once, at parse time) and returns [code]null[/code]. Note that a successful
	## parse of a literal JSON [code]null[/code] body also returns [code]null[/code].
	var json: Variant:
		get:
			if not _json_parsed:
				_json_parsed = true
				var parser := JSON.new()
				var err := parser.parse(text)
				if err == OK:
					_json_cache = parser.data
				else:
					push_error(
						"C3HTTPRequest: response body is not valid JSON: "
						+ parser.get_error_message()
					)
					_json_cache = null
			return _json_cache

	var _json_parsed := false
	var _json_cache: Variant = null


## Structured error placed on [member Response.error] when
## [member Response.ok] is [code]false[/code].
class RequestError:
	## Broad category of failure.
	enum Kind {
		## No usable HTTP response (DNS, TLS, connection, or request-start failure).
		TRANSPORT,
		## A non-2xx status was received.
		HTTP,
		## The request was rejected before being sent (e.g. an invalid argument).
		CLIENT,
		## The caller aborted the request.
		CANCELLED,
		## No response was received before the timeout elapsed.
		TIMEOUT,
		## The response body exceeded [member Options.body_size_limit].
		BODY_SIZE_LIMIT_EXCEEDED,
	}
	## Broad category of failure. One of the [enum Kind] values.
	var kind: Kind = Kind.TRANSPORT
	## Human-readable description. Never empty.
	var message := ""
	## HTTP status code, or [code]0[/code] when not applicable.
	var status := 0

	## Builds an error for a transport-level failure with no usable HTTP response.
	static func transport(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.TRANSPORT
		e.message = p_message
		return e

	## Builds an error for a request that received no response before the timeout.
	static func timed_out(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.TIMEOUT
		e.message = p_message
		return e

	## Builds an error for a request rejected before being sent.
	static func client_error(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.CLIENT
		e.message = p_message
		return e

	## Builds an error for a caller-initiated cancellation.
	static func cancelled(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.CANCELLED
		e.message = p_message
		return e

	## Builds an error for a response body that exceeded [member Options.body_size_limit].
	static func body_size_limit_exceeded(p_message: String) -> RequestError:
		var e := RequestError.new()
		e.kind = Kind.BODY_SIZE_LIMIT_EXCEEDED
		e.message = p_message
		return e

	func _to_string() -> String:
		var kind_name: String = Kind.find_key(kind)
		var parts := PackedStringArray(["[%s]" % kind_name.to_lower()])
		if status != 0:
			parts.append("status=%d" % status)
		parts.append(message)
		return " ".join(parts)


## Token passed to [member Options.cancellation_token] to cancel an in-flight
## request from another coroutine or signal handler.
class CancellationToken:
	var _cancelled := false

	## Cancels any in-flight request holding this token. Subsequent calls have
	## no effect.
	func cancel() -> void:
		_cancelled = true

	## Returns [code]true[/code] if [method cancel] has been called.
	func is_cancelled() -> bool:
		return _cancelled


class _Impl:
	func execute(
		url: String,
		custom_headers: PackedStringArray,
		method: int,
		request_data: Variant,
		options: C3HTTPRequest.Options,
		_redirects_left: int = -1
	) -> C3HTTPRequest.Response:
		if _cancelled(options):
			return _fail(C3HTTPRequest.RequestError.cancelled("Request was cancelled."))
		var redirects_left := (
			options.max_redirects if _redirects_left < 0 else _redirects_left
		)
		# A valid on_event sink switches a 2xx body to incremental SSE parsing.
		var streaming := options.on_event.is_valid()

		var parsed := _parse_url(url)
		if parsed.is_empty():
			return _fail(C3HTTPRequest.RequestError.client_error(
					'Invalid URL: "%s".' % url
			))

		var file: FileAccess = null
		if not options.download_file.is_empty() and not streaming:
			file = FileAccess.open(options.download_file, FileAccess.WRITE)
			if file == null:
				return _fail(C3HTTPRequest.RequestError.client_error(
					"Cannot open download file: \"%s\"." % options.download_file
				))

		var all_headers := PackedStringArray()
		if options.accept_gzip and options.download_file.is_empty() and not streaming:
			all_headers.append("Accept-Encoding: gzip, deflate")
		all_headers.append_array(custom_headers)

		var client := HTTPClient.new()
		client.set_read_chunk_size(options.download_chunk_size)
		if not options.proxy_host.is_empty():
			client.set_http_proxy(options.proxy_host, options.proxy_port)
			client.set_https_proxy(options.proxy_host, options.proxy_port)

		var err: int
		if parsed["tls"]:
			var tls: TLSOptions = (
				options.tls_options
				if options.tls_options != null
				else TLSOptions.client()
			)
			err = client.connect_to_host(parsed["host"], parsed["port"], tls)
		else:
			err = client.connect_to_host(parsed["host"], parsed["port"])
		if err != OK:
			return _fail(C3HTTPRequest.RequestError.transport(
				"Failed to start connection (error %d)." % err
			))

		var tree := Engine.get_main_loop() as SceneTree
		var start_ms := Time.get_ticks_msec()
		var last_status := HTTPClient.STATUS_DISCONNECTED

		while true:
			client.poll()
			last_status = _emit_status_change(client, last_status, options)
			if client.get_status() not in [
				HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING
			]:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(C3HTTPRequest.RequestError.timed_out(
					"Timed out while connecting."
				))
			if _cancelled(options):
				return _fail(C3HTTPRequest.RequestError.cancelled(
						"Request was cancelled."
				))
			await tree.process_frame

		if client.get_status() != HTTPClient.STATUS_CONNECTED:
			return _fail(C3HTTPRequest.RequestError.transport(
				"Could not connect (status %d)." % client.get_status()
			))

		if request_data is PackedByteArray:
			err = client.request_raw(
				method, parsed["path"], all_headers, request_data
			)
		else:
			err = client.request(
				method, parsed["path"], all_headers, request_data
			)
		if err != OK:
			return _fail(C3HTTPRequest.RequestError.transport(
				"Failed to send request (error %d)." % err
			))

		while true:
			client.poll()
			last_status = _emit_status_change(client, last_status, options)
			if client.get_status() != HTTPClient.STATUS_REQUESTING:
				break
			if _timed_out(start_ms, options.timeout):
				return _fail(C3HTTPRequest.RequestError.timed_out(
					"Timed out waiting for response."
				))
			if _cancelled(options):
				return _fail(C3HTTPRequest.RequestError.cancelled(
					"Request was cancelled."
				))
			await tree.process_frame

		if not client.has_response():
			return _fail(C3HTTPRequest.RequestError.transport(
				"No response received."
			))

		var status := client.get_response_code()
		var resp_headers: PackedStringArray = client.get_response_headers()

		# A 2xx body with a sink set is parsed as an SSE stream; everything else
		# (non-2xx error bodies, redirect bodies) is collected normally.
		var sse_mode := streaming and status >= 200 and status < 300
		var body_bytes := PackedByteArray()
		var sse_buffer := PackedByteArray()
		var last_recv_ms := start_ms
		# Content-Length if the server sent one, else -1 (e.g. chunked responses).
		var total_bytes := client.get_response_body_length()
		var bytes_received := 0
		while client.get_status() == HTTPClient.STATUS_BODY:
			# While streaming, timeout is idle time since the last bytes, not total
			# stream duration — a healthy long-lived stream must not be cut off.
			if _timed_out(last_recv_ms if sse_mode else start_ms, options.timeout):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.timed_out(
					"Stream idle for too long." if sse_mode
					else "Timed out while reading body."
				))
			if _cancelled(options):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.cancelled(
					"Request was cancelled."
				))
			client.poll()
			last_status = _emit_status_change(client, last_status, options)
			var chunk: PackedByteArray = client.read_response_body_chunk()
			if chunk.is_empty():
				await tree.process_frame
				continue
			last_recv_ms = Time.get_ticks_msec()
			if sse_mode:
				# Accumulate raw bytes and slice on the ASCII event delimiter so a
				# multi-byte UTF-8 character split across reads is never mangled.
				if (
					options.body_size_limit >= 0
					and sse_buffer.size() + chunk.size() > options.body_size_limit
				):
					return _fail(C3HTTPRequest.RequestError.body_size_limit_exceeded(
						"SSE event exceeded limit of %d bytes."
						% options.body_size_limit
					))
				sse_buffer.append_array(chunk)
				sse_buffer = _drain_sse_buffer(sse_buffer, options.on_event)
				continue
			if (
				options.body_size_limit >= 0
				and body_bytes.size() + chunk.size() > options.body_size_limit
			):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.body_size_limit_exceeded(
					"Response body exceeded limit of %d bytes."
					% options.body_size_limit
				))
			if file != null:
				file.store_buffer(chunk)
			else:
				body_bytes.append_array(chunk)
			bytes_received += chunk.size()
			if options.on_progress.is_valid():
				options.on_progress.call(bytes_received, total_bytes)

		if file != null:
			file.close()

		# A server may end the final event without a trailing blank line; flush
		# what remains. Every byte has arrived, so decode the tail in one pass.
		if sse_mode:
			var tail := sse_buffer.get_string_from_utf8()
			if not tail.strip_edges().is_empty():
				_emit_sse_event(tail, options.on_event)

		if options.accept_gzip and file == null and not body_bytes.is_empty():
			var encoding := _header_value(resp_headers, "Content-Encoding").to_lower()
			var mode := -1
			if encoding == "gzip":
				mode = FileAccess.COMPRESSION_GZIP
			elif encoding == "deflate":
				mode = FileAccess.COMPRESSION_DEFLATE
			if mode != -1:
				var decompressed := body_bytes.decompress_dynamic(-1, mode)
				if not decompressed.is_empty():
					body_bytes = decompressed

		if status >= 300 and status < 400 and redirects_left > 0:
			var location := _header_value(resp_headers, "Location")
			if not location.is_empty():
				return await execute(
					_resolve_redirect_url(
						location,
						parsed["host"],
						parsed["port"],
						parsed["tls"],
						parsed["path"]
					),
					custom_headers,
					_redirect_method(method, status),
					_redirect_body(method, status, request_data),
					options,
					redirects_left - 1
				)

		var res := C3HTTPRequest.Response.new()
		res.status = status
		res.headers = resp_headers
		res.body = body_bytes if file == null else PackedByteArray()
		if status < 200 or status >= 300:
			res.ok = false
			var e := C3HTTPRequest.RequestError.new()
			e.kind = C3HTTPRequest.RequestError.Kind.HTTP
			e.status = status
			e.message = "Request failed with status %d." % status
			res.error = e
		return res

	func _parse_url(url: String) -> Dictionary:
		var sep := url.find("://")
		if sep == -1:
			return {}
		var scheme := url.substr(0, sep).to_lower()
		if scheme != "http" and scheme != "https":
			return {}
		var rest := url.substr(sep + 3)
		var slash := rest.find("/")
		var host_part: String
		var path: String
		if slash == -1:
			host_part = rest
			path = "/"
		else:
			host_part = rest.substr(0, slash)
			path = rest.substr(slash)
		if host_part.is_empty():
			return {}
		var fragment := path.find("#")
		if fragment != -1:
			path = path.substr(0, fragment)
		var port := 443 if scheme == "https" else 80
		var host := host_part
		if host_part.begins_with("["):
			var bracket_close := host_part.find("]")
			if bracket_close == -1:
				return {}
			host = host_part.substr(1, bracket_close - 1)
			var after_bracket := host_part.substr(bracket_close + 1)
			if after_bracket.begins_with(":"):
				var port_str := after_bracket.substr(1)
				if port_str.is_valid_int():
					port = port_str.to_int()
		else:
			var colon := host_part.find(":")
			if colon != -1:
				var port_str := host_part.substr(colon + 1)
				if port_str.is_valid_int():
					port = port_str.to_int()
				host = host_part.substr(0, colon)
		return {
			"host": host,
			"port": port,
			"path": path,
			"tls": scheme == "https"
		}

	func _timed_out(start_ms: int, timeout: float) -> bool:
		if timeout <= 0.0:
			return false
		return (Time.get_ticks_msec() - start_ms) / 1000.0 >= timeout

	func _cancelled(options: C3HTTPRequest.Options) -> bool:
		return (
			options.cancellation_token != null
			and options.cancellation_token.is_cancelled()
		)

	# Emits on_status_changed when the client's status differs from last_status,
	# returning the current status to carry forward to the next poll.
	func _emit_status_change(
		client: HTTPClient,
		last_status: HTTPClient.Status,
		options: C3HTTPRequest.Options
	) -> HTTPClient.Status:
		var current := client.get_status()
		if current != last_status and options.on_status_changed.is_valid():
			options.on_status_changed.call(current)
		return current

	func _header_value(headers: PackedStringArray, name: String) -> String:
		var prefix := name.to_lower() + ": "
		for header: String in headers:
			if header.to_lower().begins_with(prefix):
				return header.substr(prefix.length()).strip_edges()
		return ""

	# Resolves a Location header value against the original request per RFC 3986 §5.2.
	func _resolve_redirect_url(
		location: String, host: String, port: int, tls: bool, base_path: String
	) -> String:
		if location.begins_with("http://") or location.begins_with("https://"):
			return location
		var scheme := "https" if tls else "http"
		var default_port := 443 if tls else 80
		var authority := host if port == default_port else "%s:%d" % [host, port]
		if location.begins_with("//"):
			return scheme + ":" + location
		if location.begins_with("/"):
			return scheme + "://" + authority + _normalize_path(location)
		var slash := base_path.rfind("/")
		return (
			scheme
			+ "://"
			+ authority
			+ _normalize_path(base_path.substr(0, slash + 1) + location)
		)

	# Removes . and .. segments from an absolute path per RFC 3986 §5.2.4.
	func _normalize_path(path: String) -> String:
		var out: Array[String] = []
		for seg: String in path.split("/"):
			if seg == "..":
				if out.size() > 1:
					out.pop_back()
			elif seg != ".":
				out.append(seg)
		return "/".join(out)

	# RFC 9110 §15.4: 303 always redirects as GET (any original method); 301/302
	# historically switch POST to GET but preserve other methods (§15.4.2–15.4.3).
	# 307/308 explicitly require preserving the original method and body (§15.4.8–15.4.9).
	func _redirect_method(method: int, status: int) -> int:
		if (
			status == 303
			or (status in [301, 302] and method == HTTPClient.METHOD_POST)
		):
			return HTTPClient.METHOD_GET
		return method

	func _redirect_body(
		method: int, status: int, request_data: Variant
	) -> Variant:
		if (
			status == 303
			or (status in [301, 302] and method == HTTPClient.METHOD_POST)
		):
			return ""
		return request_data

	# Carves every complete event out of [param buffer], dispatching each to
	# [param on_event], and returns the trailing partial bytes (an incomplete
	# event, possibly mid-character) to keep for the next read.
	func _drain_sse_buffer(
		buffer: PackedByteArray, on_event: Callable
	) -> PackedByteArray:
		var bound := _find_sse_boundary(buffer)
		while bound.x != -1:
			_emit_sse_event(buffer.slice(0, bound.x).get_string_from_utf8(), on_event)
			buffer = buffer.slice(bound.y)
			bound = _find_sse_boundary(buffer)
		return buffer

	# Locates the first SSE event boundary (a blank line) in [param buffer],
	# handling both LF (\n\n) and CRLF (\r\n\r\n) terminators. Returns a Vector2i
	# of (content_end, next_start) byte offsets, or (-1, -1) if no complete event
	# has arrived. The delimiter is pure ASCII, so it is found at the byte level
	# without decoding — a multi-byte UTF-8 character can never straddle it.
	func _find_sse_boundary(buffer: PackedByteArray) -> Vector2i:
		var size := buffer.size()
		var i := 0
		while i < size:
			if buffer[i] == 0x0A:
				var j := i + 1
				if j < size and buffer[j] == 0x0D:
					j += 1
				if j < size and buffer[j] == 0x0A:
					return Vector2i(i, j + 1)
			i += 1
		return Vector2i(-1, -1)

	# Parses one raw SSE event block and, if it carries data, invokes
	# [param on_event] with (data, event_type). Multiple data: lines are joined
	# with newlines; event_type defaults to "message" per the SSE spec. Comment
	# lines (":") and events with no data: lines (bare keep-alives, id-only
	# blocks) are dropped. The id: and retry: fields are ignored — this client
	# does not reconnect.
	func _emit_sse_event(raw_event: String, on_event: Callable) -> void:
		var data_lines := PackedStringArray()
		var event_type := "message"
		for line: String in raw_event.split("\n"):
			line = line.trim_suffix("\r")
			if line.begins_with(":"):
				continue
			if line.begins_with("data:"):
				var value := line.substr(5)
				if value.begins_with(" "):
					value = value.substr(1)
				data_lines.append(value)
			elif line.begins_with("event:"):
				var value := line.substr(6)
				if value.begins_with(" "):
					value = value.substr(1)
				event_type = value
		if data_lines.is_empty():
			return
		on_event.call("\n".join(data_lines), event_type)

	func _fail(error: C3HTTPRequest.RequestError) -> C3HTTPRequest.Response:
		var res := C3HTTPRequest.Response.new()
		res.ok = false
		res.error = error
		return res
