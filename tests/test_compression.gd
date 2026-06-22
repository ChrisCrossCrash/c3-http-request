extends GutTest


## Tests for the streaming download decompressor
## ([method _Impl._decode_chunk] / [method _Impl._drain_decoder]).
class TestStreamingDecompression extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	# Decodes [param compressed] by feeding it through _decode_chunk in slices of
	# [param piece] bytes — mirroring the body loop's per-chunk decode. Each chunk
	# is fully drained on arrival, so the complete output is gathered by the time
	# the last chunk (carrying the gzip footer) is consumed. Returns {"ok","data"}.
	func _decode_in_pieces(
		compressed: PackedByteArray, piece: int
	) -> Dictionary:
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)  # gzip
		var out := PackedByteArray()
		var pos := 0
		while pos < compressed.size():
			var end: int = mini(pos + piece, compressed.size())
			var res := impl._decode_chunk(decoder, compressed.slice(pos, end), 4096)
			if not res["ok"]:
				return {"ok": false, "data": out}
			out.append_array(res["data"])
			pos = end
		return {"ok": true, "data": out}

	func test_decode_gzip_single_chunk() -> void:
		var original := "The quick brown fox.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, compressed.size())
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_gzip_split_across_many_reads() -> void:
		# A byte-at-a-time feed must reassemble to the same bytes — the decoder
		# has to buffer state across chunks.
		var original := (
			"Streaming decompression across chunk boundaries!".to_utf8_buffer()
		)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, 1)
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_empty_input_is_ok_and_empty() -> void:
		var result := _decode_in_pieces(PackedByteArray(), 4096)
		assert_true(result["ok"])
		assert_eq(result["data"], PackedByteArray())

	func test_decode_large_body_round_trips() -> void:
		# A body well past a single buffer, to exercise multi-slice draining.
		var text := "C3HTTPRequest streaming gzip. ".repeat(2000)
		var original := text.to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var result := _decode_in_pieces(compressed, 512)
		assert_true(result["ok"])
		assert_eq(result["data"], original)

	func test_decode_highly_compressible_single_chunk() -> void:
		# 4 MB of one byte compresses to a few KB, then expands ~1000x past the
		# decoder's internal buffer. Fed as ONE chunk, this would overflow a naive
		# put_data() call; _decode_chunk must drain incrementally and recover it.
		var original := PackedByteArray()
		original.resize(4 * 1024 * 1024)
		original.fill(65)  # "A"
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		assert_lt(compressed.size(), 65536, "fixture should compress below ring size")
		var result := _decode_in_pieces(compressed, compressed.size())
		assert_true(result["ok"])
		assert_eq((result["data"] as PackedByteArray).size(), original.size())
		assert_eq(result["data"], original)

	func test_decode_budget_stops_a_bomb_early() -> void:
		# 4 MB collapsing to a few KB is a decompression bomb. With a small budget,
		# _decode_chunk must bail out long before materializing all 4 MB, so the
		# size-limit guard can reject it without an unbounded allocation.
		var original := PackedByteArray()
		original.resize(4 * 1024 * 1024)
		original.fill(65)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var decoder := StreamPeerGZIP.new()
		decoder.start_decompression(false)
		var result := impl._decode_chunk(decoder, compressed, 65536, 1024)
		assert_true(result["ok"])
		var produced: int = (result["data"] as PackedByteArray).size()
		assert_gt(produced, 1024, "should overshoot the budget by at most a buffer")
		assert_lt(produced, original.size(), "must not decode the whole bomb")


## Tests for the download decompressor factory
## ([method _Impl._make_download_decoder]).
class TestMakeDownloadDecoder extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_null_when_accept_gzip_false() -> void:
		# Regression guard: an opted-out caller must never get a decoder, even for a
		# compressed response.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		assert_null(impl._make_download_decoder(headers, false))

	func test_null_when_no_compression() -> void:
		assert_null(impl._make_download_decoder(PackedStringArray(), true))

	func test_null_for_identity_encoding() -> void:
		var headers := PackedStringArray(["Content-Encoding: identity"])
		assert_null(impl._make_download_decoder(headers, true))

	func test_decoder_for_gzip() -> void:
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		assert_not_null(impl._make_download_decoder(headers, true))

	func test_null_for_deflate() -> void:
		# Deflate is intentionally unsupported, so it never gets a decoder — the raw
		# bytes stream to disk unchanged.
		var headers := PackedStringArray(["Content-Encoding: deflate"])
		assert_null(impl._make_download_decoder(headers, true))


## Tests for in-memory body decompression ([method _Impl._maybe_decompress_body]).
class TestMaybeDecompressBody extends GutTest:
	var impl: C3HTTPRequest._Impl

	func before_each() -> void:
		impl = C3HTTPRequest._Impl.new()

	func test_decompresses_gzip_when_enabled() -> void:
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, -1
		)
		assert_eq(result, original)

	func test_deflate_response_is_not_decoded() -> void:
		# Deflate is intentionally unsupported: a deflate-encoded body is returned
		# raw rather than decoded, since we never request deflate in the first place.
		var compressed := "In-memory deflate body.".to_utf8_buffer().compress(
			FileAccess.COMPRESSION_DEFLATE
		)
		var headers := PackedStringArray(["Content-Encoding: deflate"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, -1
		)
		assert_eq(result, compressed)

	func test_leaves_compressed_body_raw_when_disabled() -> void:
		# Regression guard: with accept_gzip off, a compressed body is returned
		# untouched — never silently decoded.
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, false, -1
		)
		assert_eq(result, compressed)

	func test_unchanged_when_no_encoding_header() -> void:
		var body := "plain body".to_utf8_buffer()
		var result: Variant = impl._maybe_decompress_body(
			body, PackedStringArray(), true, -1
		)
		assert_eq(result, body)

	func test_unchanged_when_empty() -> void:
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			PackedByteArray(), headers, true, -1
		)
		assert_eq(result, PackedByteArray())

	# A real, valid gzip member whose decompressed content is empty — what a server
	# emits for an empty gzipped body. (PackedByteArray().compress() shortcuts empty
	# input to zero bytes, so it can't stand in for this; we need a genuine member.)
	func _empty_content_gzip() -> PackedByteArray:
		return PackedByteArray([
			0x1f, 0x8b, 0x08, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x03, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00,
			0x00, 0x00, 0x00, 0x00,
		])

	func test_empty_gzipped_body_with_limit_is_ok() -> void:
		# Regression guard: a gzipped body that decodes to empty must not be mistaken
		# for an over-limit body. An empty result can never exceed a non-negative cap.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			_empty_content_gzip(), headers, true, 1024
		)
		assert_false(
			result is C3HTTPRequest.RequestError, "empty body must not error"
		)
		assert_eq(result, PackedByteArray())

	func test_empty_gzipped_body_no_limit_is_ok() -> void:
		# Without a limit, an empty gzipped body decodes to empty — not the raw
		# compressed bytes handed back undecoded.
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			_empty_content_gzip(), headers, true, -1
		)
		assert_eq(result, PackedByteArray())

	func test_decompresses_within_limit() -> void:
		# A body that fits under the cap decodes normally — the limit only rejects
		# output that exceeds it.
		var original := "Decoded in-memory body.".to_utf8_buffer()
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, 1024
		)
		assert_eq(result, original)

	func test_fails_when_decompressed_output_exceeds_limit() -> void:
		# Zip-bomb guard: 100 KB of zeros collapses to a ~130-byte gzip body that
		# passes any reasonable compressed-bytes check, then expands ~750x on decode.
		# With body_size_limit set, the streaming decoder's budget stops well short of
		# the full output and the post-decode check returns BODY_SIZE_LIMIT_EXCEEDED,
		# so the caller surfaces ok == false rather than an unbounded body.
		var original := PackedByteArray()
		original.resize(100000)
		var compressed := original.compress(FileAccess.COMPRESSION_GZIP)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			compressed, headers, true, 1024
		)
		assert_is(result, C3HTTPRequest.RequestError)
		assert_eq(
			(result as C3HTTPRequest.RequestError).kind,
			C3HTTPRequest.RequestError.Kind.BODY_SIZE_LIMIT_EXCEEDED
		)

	func test_corrupt_gzip_body_fails() -> void:
		# A garbage body labelled gzip can't be decoded; the streaming decoder reports
		# a decode error, which surfaces as a TRANSPORT failure (matching the download
		# branch) rather than being passed through as raw bytes.
		var garbage := PackedByteArray(
			[0x1f, 0x8b, 0x08, 0xff, 0xde, 0xad, 0xbe, 0xef]
		)
		var headers := PackedStringArray(["Content-Encoding: gzip"])
		var result: Variant = impl._maybe_decompress_body(
			garbage, headers, true, -1
		)
		assert_is(result, C3HTTPRequest.RequestError)
		assert_eq(
			(result as C3HTTPRequest.RequestError).kind,
			C3HTTPRequest.RequestError.Kind.TRANSPORT
		)
		# StreamPeerGZIP logs an engine error on malformed input; assert it so GUT
		# treats the expected log as handled rather than an unexpected failure.
		assert_engine_error("Returning: FAILED")
