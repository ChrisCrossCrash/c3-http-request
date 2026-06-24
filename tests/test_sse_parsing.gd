extends GutTest


## Unit tests for the internal SSE event parser.
class TestSSEParsing extends GutTest:
	# 😀 U+1F600 — 4 bytes: F0 9F 98 80.
	const _EMOJI := "😀"
	# — U+2014 em-dash — 3 bytes: E2 80 94.
	const _EM_DASH := "—"

	var impl: C3HTTPRequest._Impl
	var events: Array = []
	# Persistent last-event-id / retry buffers, mirroring the boxes _execute()
	# threads through the parser across the whole stream.
	var id_box: Array = [""]
	var retry_box: Array = [-1]

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()
		events = []
		id_box = [""]
		retry_box = [-1]

	# Records each dispatched event as [data, event_type, last_event_id].
	func _sink() -> Callable:
		return func(data: String, event_type: String, last_event_id: String) -> void:
			events.append([data, event_type, last_event_id])

	# Feeds [param first] then [param second] as two separate socket reads,
	# draining after each — mirroring the body loop accumulating raw bytes across
	# frames. A character split across the two reads must survive reassembly.
	func _feed_two_reads(first: PackedByteArray, second: PackedByteArray) -> void:
		var rest := impl._drain_sse_buffer(first, _sink(), id_box, retry_box)
		rest.append_array(second)
		impl._drain_sse_buffer(rest, _sink(), id_box, retry_box)

	# _emit_sse_event
	func test_emit_basic_event_defaults_to_message() -> void:
		impl._emit_sse_event("data: hello", _sink(), id_box, retry_box)
		assert_eq(events, [["hello", "message", ""]])

	func test_emit_uses_event_type() -> void:
		impl._emit_sse_event("event: ping\ndata: hello", _sink(), id_box, retry_box)
		assert_eq(events, [["hello", "ping", ""]])

	func test_emit_joins_multiple_data_lines() -> void:
		impl._emit_sse_event("data: a\ndata: b", _sink(), id_box, retry_box)
		assert_eq(events, [["a\nb", "message", ""]])

	func test_emit_strips_single_leading_space() -> void:
		impl._emit_sse_event("data:  two-spaces", _sink(), id_box, retry_box)
		assert_eq(events[0][0], " two-spaces")

	func test_emit_data_without_space() -> void:
		impl._emit_sse_event("data:nospace", _sink(), id_box, retry_box)
		assert_eq(events[0][0], "nospace")

	func test_emit_ignores_comment_lines() -> void:
		impl._emit_sse_event(": keep-alive\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(events, [["hi", "message", ""]])

	func test_emit_drops_event_with_no_data() -> void:
		impl._emit_sse_event("event: ping\nid: 42", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_strips_trailing_cr_from_crlf_lines() -> void:
		impl._emit_sse_event("event: ping\r\ndata: hi\r", _sink(), id_box, retry_box)
		assert_eq(events, [["hi", "ping", ""]])

	func test_emit_empty_string_emits_nothing() -> void:
		impl._emit_sse_event("", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_only_comments_emits_nothing() -> void:
		impl._emit_sse_event(": ping\n: pong", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_event_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("event: update", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_id_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("id: 42", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_retry_field_alone_emits_nothing() -> void:
		impl._emit_sse_event("retry: 3000", _sink(), id_box, retry_box)
		assert_eq(events, [])

	func test_emit_id_with_data_emits_only_data() -> void:
		impl._emit_sse_event("id: 42\ndata: hello", _sink(), id_box, retry_box)
		assert_eq(events, [["hello", "message", "42"]])

	func test_emit_retry_with_data_emits_only_data() -> void:
		impl._emit_sse_event("retry: 3000\ndata: hello", _sink(), id_box, retry_box)
		assert_eq(events, [["hello", "message", ""]])

	# id: surfacing and persistence
	func test_emit_id_surfaced_with_data() -> void:
		impl._emit_sse_event("id: abc\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(events, [["hi", "message", "abc"]])
		assert_eq(id_box[0], "abc")

	func test_emit_id_persists_to_later_event_without_id() -> void:
		impl._emit_sse_event("id: 7\ndata: a", _sink(), id_box, retry_box)
		impl._emit_sse_event("data: b", _sink(), id_box, retry_box)
		assert_eq(events, [["a", "message", "7"], ["b", "message", "7"]])

	func test_emit_id_only_block_advances_buffer_for_next_event() -> void:
		# An id-only block dispatches nothing but still sets the resume cursor for
		# the following dispatched event.
		impl._emit_sse_event("id: 9", _sink(), id_box, retry_box)
		assert_eq(events, [])
		impl._emit_sse_event("data: after", _sink(), id_box, retry_box)
		assert_eq(events, [["after", "message", "9"]])

	func test_emit_id_strips_single_leading_space() -> void:
		impl._emit_sse_event("id:  spaced\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(id_box[0], " spaced")

	func test_emit_id_with_nul_is_ignored() -> void:
		# Per spec, an id value containing a NUL char is ignored entirely — the
		# previous cursor stands.
		impl._emit_sse_event("id: x\ndata: a", _sink(), id_box, retry_box)
		impl._emit_sse_event("id: bad%sid\ndata: b" % char(0), _sink(), id_box, retry_box)
		assert_eq(id_box[0], "x")
		assert_eq(events[1][2], "x")

	# retry:
	func test_emit_retry_sets_value() -> void:
		impl._emit_sse_event("retry: 5000\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(retry_box[0], 5000)

	func test_emit_retry_persists_across_events() -> void:
		impl._emit_sse_event("retry: 2500\ndata: a", _sink(), id_box, retry_box)
		impl._emit_sse_event("data: b", _sink(), id_box, retry_box)
		assert_eq(retry_box[0], 2500)

	func test_emit_retry_only_block_updates_value() -> void:
		impl._emit_sse_event("retry: 1200", _sink(), id_box, retry_box)
		assert_eq(events, [])
		assert_eq(retry_box[0], 1200)

	func test_emit_retry_non_integer_is_ignored() -> void:
		impl._emit_sse_event("retry: later\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(retry_box[0], -1)

	func test_emit_retry_negative_is_ignored() -> void:
		# Per spec retry is ASCII digits only — a signed value must not slip through,
		# and "-1" must not clobber the last good value or hit the -1 sentinel.
		impl._emit_sse_event("retry: 4000\ndata: a", _sink(), id_box, retry_box)
		impl._emit_sse_event("retry: -1\ndata: b", _sink(), id_box, retry_box)
		assert_eq(retry_box[0], 4000)

	func test_emit_retry_signed_positive_is_ignored() -> void:
		impl._emit_sse_event("retry: +3000\ndata: hi", _sink(), id_box, retry_box)
		assert_eq(retry_box[0], -1)

	# _drain_sse_buffer
	func test_drain_emits_complete_lf_events() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\n\ndata: b\n\n".to_utf8_buffer(), _sink(), id_box, retry_box
		)
		assert_eq(events, [["a", "message", ""], ["b", "message", ""]])
		assert_eq(rest.size(), 0)

	func test_drain_emits_complete_crlf_events() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\r\n\r\ndata: b\r\n\r\n".to_utf8_buffer(), _sink(), id_box, retry_box
		)
		assert_eq(events, [["a", "message", ""], ["b", "message", ""]])
		assert_eq(rest.size(), 0)

	func test_drain_threads_id_across_events() -> void:
		var rest := impl._drain_sse_buffer(
			"id: 1\ndata: a\n\ndata: b\n\n".to_utf8_buffer(), _sink(), id_box, retry_box
		)
		assert_eq(events, [["a", "message", "1"], ["b", "message", "1"]])
		assert_eq(rest.size(), 0)

	func test_drain_retains_trailing_partial_event() -> void:
		var rest := impl._drain_sse_buffer(
			"data: a\n\ndata: b".to_utf8_buffer(), _sink(), id_box, retry_box
		)
		assert_eq(events, [["a", "message", ""]])
		assert_eq(rest.get_string_from_utf8(), "data: b")

	func test_drain_keeps_split_multibyte_char_intact() -> void:
		# "h😎" — the 😎 emoji is four UTF-8 bytes; the buffer ends mid-character with
		# no boundary yet, so nothing is dispatched and all bytes are retained.
		var partial := "data: h".to_utf8_buffer()
		partial.append(0xF0) # first byte of 😎 (U+1F60E, encoded F0 9F 98 8E)
		var rest := impl._drain_sse_buffer(partial, _sink(), id_box, retry_box)
		assert_eq(events, [])
		assert_eq(rest, partial)

	func test_drain_empty_buffer_emits_nothing() -> void:
		var rest := impl._drain_sse_buffer(PackedByteArray(), _sink(), id_box, retry_box)
		assert_eq(events, [])
		assert_eq(rest.size(), 0)

	# Multi-byte UTF-8 character split across two socket reads — the core reason
	# the parser buffers raw bytes and slices on the ASCII delimiter.
	func test_emoji_split_mid_payload_reassembled() -> void:
		# "data: a😀b\n\n" with the emoji's 4 bytes split 2/2 across reads.
		var emoji := _EMOJI.to_utf8_buffer()
		var first := "data: a".to_utf8_buffer()
		first.append_array(emoji.slice(0, 2))
		var second := emoji.slice(2)
		second.append_array("b\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_eq(events, [["a" + _EMOJI + "b", "message", ""]])

	func test_emoji_split_emits_no_replacement_char() -> void:
		# Guards against per-chunk decoding, which would leave U+FFFD on each half.
		var emoji := _EMOJI.to_utf8_buffer()
		var first := "data: ".to_utf8_buffer()
		first.append_array(emoji.slice(0, 2))
		var second := emoji.slice(2)
		second.append_array("\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_false(events[0][0].contains("�"), "no replacement char in payload")

	func test_em_dash_split_at_event_boundary_reassembled() -> void:
		# The em-dash is the last character before the \n\n boundary, split 1/2 so
		# it lands mid-character right at the event boundary.
		var dash := _EM_DASH.to_utf8_buffer()
		var first := "data: hi".to_utf8_buffer()
		first.append_array(dash.slice(0, 1))
		var second := dash.slice(1)
		second.append_array("\n\n".to_utf8_buffer())
		_feed_two_reads(first, second)
		assert_eq(events, [["hi" + _EM_DASH, "message", ""]])

	# _find_sse_boundary
	func test_find_boundary_lf() -> void:
		assert_eq(impl._find_sse_boundary("a\n\nb".to_utf8_buffer()), Vector2i(1, 3))

	func test_find_boundary_crlf() -> void:
		assert_eq(
			impl._find_sse_boundary("a\r\n\r\nb".to_utf8_buffer()), Vector2i(2, 5)
		)

	func test_find_boundary_none() -> void:
		assert_eq(
			impl._find_sse_boundary("data: a\n".to_utf8_buffer()), Vector2i(-1, -1)
		)
