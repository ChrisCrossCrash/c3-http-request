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
	## Token for cancelling this request from another coroutine or signal
	## handler. [code]null[/code] means no cancellation support.
	var cancellation_token: CancellationToken = null


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
			return _text_cache

	var _text_cache: Variant = null


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
		request_data: String,
		options: C3HTTPRequest.Options,
		_redirects_left: int = -1
	) -> C3HTTPRequest.Response:
		if _cancelled(options):
			return _fail(C3HTTPRequest.RequestError.cancelled("Request was cancelled."))
		var redirects_left := (
			options.max_redirects if _redirects_left < 0 else _redirects_left
		)

		var parsed := _parse_url(url)
		if parsed.is_empty():
			return _fail(C3HTTPRequest.RequestError.client_error(
					'Invalid URL: "%s".' % url
			))

		var file: FileAccess = null
		if not options.download_file.is_empty():
			file = FileAccess.open(options.download_file, FileAccess.WRITE)
			if file == null:
				return _fail(C3HTTPRequest.RequestError.client_error(
					"Cannot open download file: \"%s\"." % options.download_file
				))

		var all_headers := PackedStringArray()
		if options.accept_gzip and options.download_file.is_empty():
			all_headers.append("Accept-Encoding: gzip, deflate")
		all_headers.append_array(custom_headers)

		var client := HTTPClient.new()
		client.set_read_chunk_size(options.download_chunk_size)

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

		while true:
			client.poll()
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

		err = client.request(method, parsed["path"], all_headers, request_data)
		if err != OK:
			return _fail(C3HTTPRequest.RequestError.transport(
				"Failed to send request (error %d)." % err
			))

		while true:
			client.poll()
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

		var body_bytes := PackedByteArray()
		while client.get_status() == HTTPClient.STATUS_BODY:
			if _timed_out(start_ms, options.timeout):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.timed_out(
					"Timed out while reading body."
				))
			if _cancelled(options):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.cancelled(
					"Request was cancelled."
				))
			client.poll()
			var chunk: PackedByteArray = client.read_response_body_chunk()
			if chunk.is_empty():
				await tree.process_frame
				continue
			if (
				options.body_size_limit >= 0
				and body_bytes.size() + chunk.size() > options.body_size_limit
			):
				if file != null:
					file.close()
				return _fail(C3HTTPRequest.RequestError.transport(
					"Response body exceeded limit of %d bytes."
					% options.body_size_limit
				))
			if file != null:
				file.store_buffer(chunk)
			else:
				body_bytes.append_array(chunk)

		if file != null:
			file.close()

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
		method: int, status: int, request_data: String
	) -> String:
		if (
			status == 303
			or (status in [301, 302] and method == HTTPClient.METHOD_POST)
		):
			return ""
		return request_data

	func _fail(error: C3HTTPRequest.RequestError) -> C3HTTPRequest.Response:
		var res := C3HTTPRequest.Response.new()
		res.ok = false
		res.error = error
		return res
