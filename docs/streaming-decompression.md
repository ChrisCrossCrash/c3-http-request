# Streaming gzip decompression

Decompressing a gzip-compressed response **as it streams to disk** — handling each piece as it arrives off the network rather than waiting for the whole body and decompressing it in one shot — is the most involved thing `C3HTTPRequest` does internally. Doing it correctly means working around a couple of non-obvious traps, which makes the code hard to follow by reading it top to bottom, so it gets its own explainer here. Only the **file-download** path actually decodes incrementally like this. The **in-memory** path does not stream its decompression — it collects the whole body first and decodes it in one pass at the end — but it reuses the very same decompressor to do so, for reasons the next section explains. So one engine (`StreamPeerGZIP`) serves both ways a body can come back; only the file path is driven by it chunk-by-chunk as bytes arrive.

This page builds the picture from the ground up: what makes file downloads different, the Godot tool we lean on (`StreamPeerGZIP`), the feed-and-drain loop at the heart of it, and the safety checks around it. The code lives in `_Impl.execute()`, the in-memory entry point `_maybe_decompress_body()`, and the shared helpers `_decode_chunk()` / `_drain_decoder()` in [../c3_http_request/c3_http_request.gd](../c3_http_request/c3_http_request.gd).

## The problem

A response body can come back to you two ways:

- **In memory** — the body is collected into one `PackedByteArray` and handed back as `Response.body`. Simple, but the entire body sits in RAM.
- **To a file** — when `Options.download_file` is set, each piece is written to disk as it arrives and `Response.body` is left empty. This is how you download something too big to comfortably hold in memory.

Now add compression. To save bandwidth, a server can send the body compressed and set a `Content-Encoding: gzip` header to say so. We want to hand you the _decompressed_ content, so what lands on disk is the real file, not a compressed blob. (We handle `gzip` only — see the Caveats for why `deflate` is intentionally left out.)

The file path is what makes this hard. A file download exists precisely to handle bodies too big for RAM, so decompressing one in a single shot — holding the **entire** compressed body and producing the **entire** decompressed body at once — would defeat the purpose; a 2 GB download would blow up memory. So the file path needs **streaming** decompression: decompress the data in small pieces as it arrives off the network, write each decompressed piece to disk, and never keep more than a small working set in memory at once.

An in-memory response doesn't have that memory constraint — the whole body is already being collected into RAM, so you might expect it to skip the streaming machinery and decompress in one shot with `PackedByteArray.decompress_dynamic()`. We deliberately don't, and the reason isn't "we've already built the streaming path, so we may as well reuse it." It's that `decompress_dynamic()` is impossible to use correctly here. Its binding returns a `PackedByteArray`, and an **empty** result is all you get back for three completely different outcomes: a body that validly decompressed to nothing, a body that blew past the size limit, and a body that was corrupt. There's no error code, no way to tell them apart. So a legitimately empty gzipped body — which servers really do send — is indistinguishable from a failure, and you're forced to either reject valid empty bodies or wave through corrupt ones.

`StreamPeerGZIP` has no such ambiguity: feeding bytes in and draining them out reports decode errors distinctly from a validly empty result, so an empty body and a corrupt one are never confused. That's why the in-memory path feeds its fully-collected body through the **same** streaming decompressor as a single chunk, rather than taking the one-shot shortcut. Both paths run on one engine — `StreamPeerGZIP` driven by `_decode_chunk()` — and behave identically, right down to how they treat an empty or corrupt body. The rest of this page describes that shared engine; the only difference between the two callers is that the file path drains each decompressed piece to disk as chunks arrive, while the in-memory path hands the whole body in at the end.

## Why `StreamPeerGZIP`

Godot already ships a tool for exactly this: [`StreamPeerGZIP`](https://docs.godotengine.org/en/stable/classes/class_streampeergzip.html). You feed it compressed bytes and it hands back decompressed bytes incrementally — a little in, a little out — so you never need the whole thing at once. We let it do the actual gzip math (it wraps zlib, the library that implements DEFLATE — the compression algorithm gzip is built on) rather than implementing decompression ourselves.

It's the same class Godot's own [`HTTPRequest`](https://docs.godotengine.org/en/stable/classes/class_httprequest.html) node uses internally for this job, and its API hasn't changed since Godot 4.0 across the versions this addon supports. The docs mark it "experimental," which means its API could change in a future release — that's worth watching. The `TestStreamingDecompression` tests exercise it directly, so any API breakage on a new Godot version will surface as test failures rather than silent misbehavior.

We create one `StreamPeerGZIP` per download, in decompression mode — but only when the caller has opted into compression via `accept_gzip`:

```gdscript
func _make_download_decoder(
    resp_headers: PackedStringArray, accept_gzip: bool
) -> StreamPeerGZIP:
    if not accept_gzip:
        return null
    if _header_value(resp_headers, "Content-Encoding").to_lower() != "gzip":
        return null
    var decoder := StreamPeerGZIP.new()
    decoder.start_decompression(false)   # false = gzip
    return decoder
```

The decision is **gated on `accept_gzip`**, matching native `HTTPRequest` — but it's worth being precise about what that option actually does, because the name is a little misleading.

`accept_gzip` controls two things together: whether we send an `Accept-Encoding: gzip` request header, and whether we decode a compressed response. When it's true, we advertise a preference for compression, which nudges servers that are on the fence to compress and save bandwidth; then, if the response comes back compressed, we decode it. When it's false, we send no `Accept-Encoding` at all and perform no decoding — the body is handed back exactly as received.

The misleading part: `accept_gzip = false` does **not** mean "I refuse gzip." Omitting `Accept-Encoding` tells the server any encoding is acceptable, so a server is still free to return a compressed body. What changes is only what we do with it — the raw bytes come through verbatim, and the `Content-Encoding` header in `Response.headers` tells you what encoding they are. If you specifically want to forbid compression, set `Accept-Encoding: identity` in `custom_headers` (which takes precedence over ours when `accept_gzip` is true).

When `accept_gzip` is true, we decode the response only when `Content-Encoding` is `gzip`. Anything else — including `deflate` — gets no decoder, and the chunks pass through unchanged. The in-memory path (`_maybe_decompress_body`) shares both this gating and the very same `StreamPeerGZIP` decoder: it feeds the whole collected body through `_decode_chunk` as one chunk, so the two paths behave identically — right down to how they handle an empty or corrupt body. (This is also how native `HTTPRequest` decodes every response; it never uses the one-shot `PackedByteArray.decompress_dynamic`, whose binding can't tell a validly-empty body apart from an over-limit or corrupt one.)

## The complication: a small, fixed buffer

Almost all the complexity below comes from one detail. `StreamPeerGZIP` holds its decompressed output in a small, fixed-size internal buffer — about 64 KB — until you read it back out. (Internally it's a _ring buffer_, also called a circular FIFO: a fixed block of memory the decoder fills while you empty it, with both ends wrapping around. The "fixed size" is the part that matters here.)

Picture the decoder as a box, with compressed bytes going in one side and decompressed bytes coming out the other:

```
 compressed bytes                                   decompressed bytes
 (chunk.slice(pos))   ┌──────────────────────────┐  (get_partial_data)
 ──put_partial_data──▶│  zlib inflate → 64 KB box│──get_partial_data──▶ to disk
                      │  (fixed size)            │
                      └──────────────────────────┘
```

Here's the rub: that buffer is small and fixed, but decompression can _expand_ data enormously. A 64 KB compressed chunk can easily decompress to many megabytes. So you can't just push a whole chunk in and expect all the output to fit, and you can't assume a single read pulls out everything it produced.

Two things the API tells you make this workable:

- **`put_partial_data(data)` returns `[err, sent]`** — `sent` is how many _compressed_ bytes the decoder actually accepted. If its output box fills up partway through, it takes less than you offered and reports the smaller number. This is **back-pressure**: the decoder saying "I'm full — empty me before I'll take more."
- **`get_partial_data(n)` returns `[err, part]`** — this reads decompressed bytes back out. An empty `part` means the box is empty for now.

(Don't confuse this 64 KB output box with `Options.download_chunk_size`. That option controls how many _compressed_ bytes we read off the network per poll; it has nothing to do with the decoder's internal buffer.)

## The feed-and-drain loop

Each compressed chunk that arrives is handed to `_decode_chunk()`. It pushes the chunk in and pulls decompressed bytes out, repeating until the whole chunk has been accepted:

```gdscript
func _decode_chunk(
    decoder: StreamPeerGZIP,
    chunk: PackedByteArray,
    read_size: int,
    budget: int = -1
) -> Dictionary:
    var out := PackedByteArray()
    var pos := 0
    while pos < chunk.size():
        var fed: Array = decoder.put_partial_data(chunk.slice(pos))
        var feed_error: Error = fed[0]
        var sent: int = fed[1]
        if feed_error != OK:
            return {"ok": false, "data": out}
        pos += sent
        var drained := _drain_decoder(decoder, read_size)
        out.append_array(drained["data"])
        if not drained["ok"]:
            return {"ok": false, "data": out}
        if budget >= 0 and out.size() > budget:
            # Past the allowance — stop; the caller will reject this as over-limit.
            break
        if sent == 0 and (drained["data"] as PackedByteArray).is_empty():
            # No input consumed and nothing decoded means no further progress is
            # possible (e.g. trailing bytes past the stream end) — stop spinning.
            break
    return {"ok": true, "data": out}
```

The key detail is **`pos += sent`, not `pos += chunk.size()`**. Because the decoder's output box can fill before it has accepted the whole chunk, a single `put_partial_data` may only take part of it. The loop keeps re-feeding whatever's left over after each drain frees up room. So a 64 KB compressed chunk that expands to 60 MB is handled in waves — feed a little, drain it out to disk, feed more, drain again — and we never hold more than roughly one box's worth at a time instead of all 60 MB.

Draining is just a small loop that reads decompressed bytes until the box is empty:

```gdscript
func _drain_decoder(decoder: StreamPeerGZIP, read_size: int) -> Dictionary:
    var out := PackedByteArray()
    while true:
        var result: Array = decoder.get_partial_data(read_size)
        var drain_error: Error = result[0]
        var part: PackedByteArray = result[1]
        if drain_error != OK:
            return {"ok": false, "data": out}
        if part.is_empty():
            break
        out.append_array(part)
    return {"ok": true, "data": out}
```

## The two early exits

The feed loop has two extra `break`s, and each guards against a specific failure:

- **Stopping a "zip bomb."** A zip bomb is a tiny compressed file crafted to explode into a huge amount of data when decompressed — a few kilobytes becoming many gigabytes. `budget` is how many more bytes we're still allowed to produce (the `body_size_limit` minus what's already been written to disk). The moment the decompressed output passes that, we stop — rather than dutifully unpacking the rest of a bomb into memory. Because we check after each drain, the overshoot is at most about one box's worth. A negative `budget` means no limit was set, so this check is skipped.
- **No-progress guard.** If a feed accepts nothing (`sent == 0`) _and_ the drain produces nothing either, there's no way to move forward — this happens when the gzip stream has officially ended but a few stray bytes remain after it (a concatenated second gzip member, or junk appended after the stream). Without this check the loop would spin forever. We break cleanly instead. The trade-off is that a valid multi-member gzip stream is truncated at the first member rather than decoded in full (see Caveats) — but it never hangs.

## How the body loop uses it

Back in the main download loop, the file branch decompresses each chunk (when there's a decoder), checks the size limit, and writes the result to disk:

```gdscript
if file != null:
    var to_write := chunk
    if download_decoder != null:
        var budget := (
            options.body_size_limit - bytes_written
            if options.body_size_limit >= 0
            else -1
        )
        var decoded := _decode_chunk(
            download_decoder, chunk, options.download_chunk_size, budget
        )
        if not decoded["ok"]:
            file.close()
            DirAccess.remove_absolute(options.download_file)
            return _fail(RequestError.transport("Failed to decompress download stream."))
        to_write = decoded["data"]
    if (
        options.body_size_limit >= 0
        and bytes_written + to_write.size() > options.body_size_limit
    ):
        file.close()
        DirAccess.remove_absolute(options.download_file)
        return _fail(RequestError.body_size_limit_exceeded(
            "Response body exceeded limit of %d bytes." % options.body_size_limit
        ))
    file.store_buffer(to_write)
    bytes_written += to_write.size()
```

Three things worth highlighting:

- **`body_size_limit` counts decompressed bytes here.** It's checked against `bytes_written` — the bytes that actually land on disk — which is what truly bounds a zip bomb, since the compressed size could be tiny. This matches native `HTTPRequest`. (The in-memory path additionally bounds the _compressed_ received bytes as they stream in, then caps the decompressed output through the same `_decode_chunk` budget; that extra compressed-bytes check is the deliberate, unchanged difference between the two paths.)
- **Errors clean up the partial file.** On a decode failure or a size-limit breach, the file is closed and deleted, so a half-written or corrupt download is never left behind. A decode failure surfaces as a `TRANSPORT` error; a size breach as `BODY_SIZE_LIMIT_EXCEEDED`.
- **A failed download fails cleanly.** Bytes are already on disk by the time a later chunk fails to decode, so there's nothing to fall back to — the file is removed and the request errors. The in-memory path now mirrors this: a corrupt body returns a `TRANSPORT` error rather than passing the raw bytes through, so neither path ever silently hands back undecoded data.

## Caveats

- **`deflate` is intentionally unsupported.** We advertise `Accept-Encoding: gzip` only, never `deflate`, and we don't decode a `Content-Encoding: deflate` response — the raw bytes pass through unchanged. This is deliberate. HTTP `deflate` is [ambiguous](https://www.zlib.net/zlib_faq.html#faq39): it's supposed to be zlib-wrapped ([RFC 1950](https://datatracker.ietf.org/doc/html/rfc1950)), but many servers send raw deflate ([RFC 1951](https://datatracker.ietf.org/doc/html/rfc1951), no zlib header or adler32 trailer) instead, and the two can't be told apart with certainty — Godot exposes no raw-inflate primitive, so the only way to accept raw deflate is a header sniff that's still ~1-in-1000 wrong. Native `HTTPRequest` assumes zlib-wrapped and silently fails on raw deflate, a rare and hard-to-trace bug. Rather than inherit it or paper over it, we skip deflate entirely — gzip dominates the web, brotli is next, and `deflate` is a rounding error. ([Go's `net/http`](https://github.com/golang/go/blob/fd6f414c65e61a51cf12c98ef473957d73f97c44/src/net/http/transport.go#L3003-L3005) makes the same gzip-only choice for the same reason — its source comment reads "Deflate is ambiguous and not as universally supported anyway" and cites this same zlib FAQ.) A caller who genuinely needs deflate can request it via `custom_headers` and decode the raw bytes themselves.
- **Multi-member gzip is truncated.** RFC 1952 allows a gzip stream to be several members concatenated, and a fully compliant decoder decodes all of them. `StreamPeerGZIP` stops at the first member's end and doesn't reset for the next, so we decode only the first member and drop the rest — without raising an error. This is rare over HTTP (servers almost always send a single member), and the no-progress guard means we truncate cleanly rather than hang. Decoding all members would require detecting the leftover bytes and continuing them through a fresh decoder.
- **SSE is never decompressed.** When a streaming `on_sse_event` sink is active, the body is parsed as a `text/event-stream` and no decoder is created.
