# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

C3 HTTP Request for Godot is a Godot 4 addon providing a static, async HTTP client that requires no scene tree. Callers `await C3HTTPRequest.request(...)` and check `response.ok` — a single check that covers transport failures, timeouts, and non-2xx statuses alike. The implementation uses `HTTPClient` (a `RefCounted`) with a cooperative polling loop, so it works from any script context without adding a `Node`.

Deliberately out of scope: retries, caching, cookies, middleware, typed deserialization, and JSON-specific handling.

## Commands

**Run all tests:**
```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit
```

**Run a single test file:**
```
godot --headless --path . -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit -gtest=res://tests/test_c3_http_request.gd
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
- `static func request(url, custom_headers, method, request_data, options)` → `Response` — the one async entry point. Delegates to `_impl.execute()`.
- `static var _impl: _Impl` — swapped in tests for a `TestableImpl` subclass that intercepts calls without making real network requests.

**Inner classes:**
- `Method` enum — `GET`, `HEAD`, `POST`, `PUT`, `DELETE`, `OPTIONS`, `PATCH`
- `Options` — `timeout`, `body_size_limit`, `download_chunk_size`, `accept_gzip`, `max_redirects`, `download_file`, `tls_options`, `cancellation_token`
- `Response` — `ok: bool`, `error: RequestError`, `status: int`, `headers: PackedStringArray`, `body: String`
- `RequestError` — `Kind` enum (`TRANSPORT`, `HTTP`, `CLIENT`, `CANCELLED`, `TIMEOUT`), `kind`, `message`, `status`, factory methods, `_to_string()`
- `CancellationToken` — `cancel()`, `is_cancelled()`
- `_Impl` — contains `execute()` with the `HTTPClient` polling loop, plus `_parse_url()`, `_timed_out()`, `_cancelled()`, `_header_value()`, `_fail()` helpers

**Transport** is Godot's `HTTPClient` (a `RefCounted`), created per call inside `_Impl.execute()`. The polling loop yields to `SceneTree.process_frame` via `Engine.get_main_loop()` — no scene tree membership required from the caller.

**Tests** are in [tests/](tests/) using the GUT framework (in [addons/gut/](addons/gut/)). `TestableImpl` inside `tests/test_c3_http_request.gd` overrides `execute()` so no real HTTP calls are made.

## GDScript Style Guide

Follow [CONTRIBUTING.md](CONTRIBUTING.md) strictly. Key rules:

- **Tabs** for indentation (never spaces), one tab per level.
- **Type hints are mandatory** on all parameters and return types. Use `:=` for inference; use explicit type when inference would be too broad (e.g., `instantiate()` calls).
- Signal awaits require explicit type annotation (GDScript limitation); function awaits may use `:=`.
- Multi-line function signatures: closing `)` goes on its own line at zero indent, before `->`.
- `##` doc comments for classes, `@export` vars, and public methods. `#` for private methods only when non-obvious. Comments explain *why*, not *what*.
- Private members and methods prefixed with `_`.

**Declaration order within a class:**
1. `class_name` / `extends`
2. Class-level `##` doc comment
3. Signals → Enums → Constants → `@export` vars → public vars → private vars → `@onready` vars
4. Built-in virtual methods (`_ready`, `_process`, …)
5. Public methods
6. Private methods
7. Inner classes
