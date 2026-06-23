# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C3 HTTP Request for Godot is a Godot 4 addon providing a static, async HTTP client that requires no scene tree. Callers `await C3HTTPRequest.request(...)` and check `response.ok` — a single check that covers transport failures, timeouts, and non-2xx statuses alike. The implementation uses `HTTPClient` (a `RefCounted`) with a cooperative polling loop, so it works from any script context without adding a `Node`.

## Commands

**Run all tests:**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**Run a single test file:**

```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gtest=res://tests/test_public_api.gd
```

If GUT reports "does not extend GutTest" or "Nothing was run" after files or classes have been renamed, the global script class cache is stale — rebuild it first with `godot --headless --path . --import`.

Tests require Godot 4.6+ on `$PATH`. CI runs on ubuntu-latest with Godot 4.6.2-stable via `.github/workflows/tests.yml` (which runs the `--import` step before GUT).

**Build asset for distribution:**

```
python scripts/build_asset.py <version>
```

## Architecture

The addon is a single script: [c3_http_request/c3_http_request.gd](c3_http_request/c3_http_request.gd).

**`C3HTTPRequest`** — No `extends`, no `@tool`. Public surface:

- `static func request(url, custom_headers, method, request_data, options)` → `Response` — the one async entry point. Delegates to `_impl._execute()`.
- `static var _impl: _Impl` — swapped in tests via `Mock.install()` / `Mock.uninstall()` to intercept calls without touching the network.

**Inner classes:**

- `Method` enum — `GET`, `HEAD`, `POST`, `PUT`, `DELETE`, `OPTIONS`, `PATCH`
- `Options` — `timeout`, `body_size_limit`, `download_chunk_size`, `accept_gzip`, `max_redirects`, `use_threads` (run the loop on a background thread, marshaling callbacks back to the main thread), `download_file`, `tls_options`, `http_proxy_host`, `http_proxy_port`, `https_proxy_host`, `https_proxy_port`, `cancellation_token`, `on_sse_event` (SSE streaming sink), `on_progress` (download progress sink), `on_status_changed` (HTTPClient status sink)
- `Response` — `ok: bool`, `error: RequestError`, `status: int`, `headers: PackedStringArray`, `body: String`
- `RequestError` — `Kind` enum (`TRANSPORT`, `HTTP`, `CLIENT`, `CANCELLED`, `TIMEOUT`, `BODY_SIZE_LIMIT_EXCEEDED`), `kind`, `message`, `status`, factory methods, `_to_string()`
- `CancellationToken` — `cancel()`, `is_cancelled()`
- `_Stub` — builder returned by `Mock.stub()`; configures a canned response via `ok()`, `fail()`, or `returns()`
- `Mock` — extends `_Impl`; install/uninstall into `_impl`, register stubs with `stub()`, inspect outgoing calls via `calls` / `call_count` / `last_call`, reset with `reset()`
- `_Impl` — contains `_execute()` with the `HTTPClient` polling loop, plus `_pump()` (the per-poll yield), `_run_threaded()`/`_threads_available()` (background-thread orchestration for `use_threads`), `_emit()` (callback dispatch, main-thread-marshaled when threaded), `_parse_url()`, `_resolve_proxies()` (per-scheme proxy routing), `_timed_out()`, `_cancelled()`, `_emit_status_change()`, `_header_value()`, `_fail()` helpers, the streaming download decompressor (`_decode_chunk()`/`_drain_decoder()`, driving a `StreamPeerGZIP` so gzip `download_file` bodies are decoded on the fly — gzip only; deflate is intentionally unsupported), and the SSE parser (`_drain_sse_buffer()`, `_find_sse_boundary()`, `_emit_sse_event()`)

**Transport** is Godot's `HTTPClient` (a `RefCounted`), created per call inside `_Impl._execute()`. The polling loop's single yield point is `_pump()`: in the default cooperative mode it yields to `SceneTree.process_frame` via `Engine.get_main_loop()` (no scene tree membership required from the caller); when `Options.use_threads` is set, `_execute()` runs on a worker `Thread` and `_pump()` becomes a synchronous `OS.delay_usec()` so the coroutine runs straight through off the main thread.

**Tests** are in [tests/](tests/) using the GUT framework (in [addons/gut/](addons/gut/)). Each file covers a focused area: `test_public_api.gd` (public API and types), `test_mock.gd` (Mock lifecycle, stubs, call recording), `test_sse_parsing.gd`, `test_url_and_routing.gd`, `test_compression.gd`, `test_headers.gd`, `test_download_file_cleanup.gd`. `TestableImpl` inside `tests/test_public_api.gd` overrides `_execute()` so no real HTTP calls are made.

## GDScript Style Guide

Follow [CONTRIBUTING.md](CONTRIBUTING.md) strictly. Key rules:

- **Tabs** for indentation (never spaces), one tab per level.
- **Type hints are mandatory** on all parameters and return types. Use `:=` for inference; use explicit type when inference would be too broad (e.g., `instantiate()` calls).
- Signal awaits require explicit type annotation (GDScript limitation); function awaits may use `:=`.
- Multi-line function signatures: closing `)` goes on its own line at zero indent, before `->`.
- `##` doc comments for classes, `@export` vars, and public methods. `#` for private methods only when non-obvious. Comments explain _why_, not _what_.
- Private members and methods prefixed with `_`.

**Declaration order within a class:**

1. `class_name` / `extends`
2. Class-level `##` doc comment
3. Signals → Enums → Constants → `@export` vars → public vars → private vars → `@onready` vars
4. Built-in virtual methods (`_ready`, `_process`, …)
5. Public methods
6. Private methods
7. Inner classes
