extends Node
## Benchmark: C3HTTPRequest vs Godot's native HTTPRequest, each in cooperative
## and threaded modes.
##
## Targets the hosted benchmark API at api.chriskumm.com by default. To run
## locally instead, start [code]python benchmark_server.py[/code] and change
## SERVER_BASE to [code]"http://127.0.0.1:8927"[/code].
##
## Auth is sent only when PERSONAL_API_KEY is set. The local server needs no key;
## set the variable (and run it with a matching --token) to hit a protected host.
##
## Numbers are reported as medians (robust to the occasional GC/scheduler hiccup).

# Base URL of the benchmark server. The local benchmark_server.py listens here by
# default; change it to a remote host (e.g. "https://api.chriskumm.com") to
# benchmark over a real network link.
const SERVER_BASE := "https://api.chriskumm.com"
const LATENCY_URL := SERVER_BASE + "/api/benchmark/ping/"
const CONCURRENCY_URL := SERVER_BASE + "/api/benchmark/ping/"
# Returns exactly <bytes> zero bytes with a Content-Length header.
const DOWNLOAD_URL := SERVER_BASE + "/api/benchmark/download/%d/"
# Frame caps to sweep for the latency benchmark. 0 means uncapped (the headless
# default) — the control case where no per-frame gate exists.
const FRAME_CAPS: Array[int] = [0, 120, 60, 30]
const WARMUPS := 3
const RUNS := 100
# Concurrency benchmark: simultaneous request counts, run at a typical 60 fps.
const CONCURRENCY_LEVELS: Array[int] = [1, 2, 4, 8]
# How many times to repeat each batch; the reported figure is the median of
# these. Odd so the median is a real measured batch, not the mean of two.
const CONCURRENCY_REPS := 25
const CONCURRENCY_FPS := 60
# File download benchmark: body sizes in MB, streamed to disk, run at 60 fps.
const DOWNLOAD_SIZES_MB: Array[int] = [1, 8]
const DOWNLOAD_REPS := 25
const DOWNLOAD_CHUNK := 65536
const DOWNLOAD_FPS := 60
const DOWNLOAD_PATH := "user://benchmark_download.bin"
# Number of recent frames the on-screen FPS readout averages over.
const FPS_WINDOW := 30
# Status-label colors: client (C3 vs native) and mode (cooperative vs threaded).
const COLOR_C3 := "#4ec9b0"        # teal — C3HTTPRequest
const COLOR_NATIVE := "#e0a060"    # amber — native HTTPRequest
const COLOR_COOP := "#569cd6"      # blue — cooperative
const COLOR_THREADED := "#c586c0"  # purple — threaded
const COLOR_DIM := "#888888"       # gray — throttle line

# Human-readable description of the benchmark phase currently running, shown in
# the status label alongside the client and mode of each timed call.
var _auth_headers: PackedStringArray = []
var _phase := "idle"
var _server := ""
# Names the call currently running (phase + client + mode), shown in the status label.
var _current_label := "idle"
var _frame_times: Array[float] = []
# Last Engine.max_fps seen; a change resets the baseline window so frames at a new
# cap aren't compared against the previous cap's.
var _last_max_fps := -1

@onready var fps_label: Label = $CanvasLayer/FPSLabel
@onready var status_label: RichTextLabel = $CanvasLayer/StatusLabel
@onready var output_overlay: OutputOverlay = $CanvasLayer/OutputOverlay


func _ready() -> void:
	# Disable V-Sync so the loop can run past the monitor's refresh rate: with it
	# on, presentation (and thus Engine.max_fps) is capped to the display, so the
	# uncapped and 120 fps benchmark sections couldn't exceed a 60 Hz monitor.
	if DisplayServer.get_name() != "headless":
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	# The local server needs no auth; send a token only when one is configured,
	# for runs against a protected host (server started with a matching --token).
	var api_key := OS.get_environment("PERSONAL_API_KEY")
	if not api_key.is_empty():
		_auth_headers = PackedStringArray(["Authorization: Token %s" % api_key])
	status_label.bbcode_enabled = true
	_phase = "starting"
	_show_status()
	_print_environment()
	# Let things settle before starting.
	# Without this, the first frame often shows as a stutter.
	await get_tree().create_timer(0.5).timeout
	await _bench_latency(LATENCY_URL)
	await _bench_concurrency(CONCURRENCY_URL)
	await _bench_download()
	output_overlay.print_with_overlay("\nDone.")
	_phase = "Done."
	_show_status()
	# The editor's remote debugger forwards print output asynchronously, so quitting
	# immediately drops the final batch (results + report). Give it time to drain
	# when attached; a single frame is enough over direct stdout (headless/CLI).
	if EngineDebugger.is_active():
		await get_tree().create_timer(0.5).timeout
	else:
		await get_tree().process_frame
	get_tree().quit()


func _process(delta: float) -> void:
	# A cap change makes the new cap's frames incomparable to the old; start fresh.
	if Engine.max_fps != _last_max_fps:
		_last_max_fps = Engine.max_fps
		_frame_times.clear()
	_frame_times.append(delta)
	if _frame_times.size() > FPS_WINDOW:
		_frame_times.remove_at(0)
	var total := 0.0
	for t in _frame_times:
		total += t
	var fps := _frame_times.size() / total if total > 0.0 else 0.0
	fps_label.text = "%d fps (actual)" % roundi(fps)


# Refreshes the on-screen status from the current [member _phase]. With a client
# given, a second line names the client and mode of the call now running.
func _show_status(client := "", threaded := false) -> void:
	var phase_label := "%s · %s" % [_phase, _server] if not _server.is_empty() else _phase
	if client.is_empty():
		_current_label = phase_label
		status_label.text = "[b]%s[/b]" % phase_label
		return
	var mode := "threaded" if threaded else "cooperative"
	var cap := "uncapped" if Engine.max_fps == 0 else "%d fps" % Engine.max_fps
	var client_color := COLOR_C3 if client.begins_with("C3") else COLOR_NATIVE
	var mode_color := COLOR_THREADED if threaded else COLOR_COOP
	_current_label = "%s @ %s · %s %s" % [phase_label, cap, client, mode]
	var throttle := (
		"uncapped"
		if Engine.max_fps == 0
		else "throttled to %d fps" % Engine.max_fps
	)
	status_label.text = (
		"[b]%s[/b]\n[color=%s]%s[/color] — [color=%s]%s[/color]\n[color=%s]%s[/color]"
		% [phase_label, client_color, client, mode_color, mode, COLOR_DIM, throttle]
	)


func _print_environment() -> void:
	var v := Engine.get_version_info()
	var renderer := ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"
	) as String
	output_overlay.print_with_overlay("C3HTTPRequest benchmark vs native HTTPRequest")
	output_overlay.print_with_overlay("commit %s" % _git_commit())
	output_overlay.print_with_overlay("Godot %s | %s | %s | %s renderer" % [
		v.get("string", "?"), OS.get_name(), OS.get_processor_name(), renderer
	])


# --- Latency: one request at a time, swept across frame caps ---


func _bench_latency(url: String) -> void:
	_server = _host_from_url(url)
	output_overlay.print_with_overlay("\n== Single-request latency (median of %d requests) ==" % RUNS)
	for cap: int in FRAME_CAPS:
		Engine.max_fps = cap
		var label := "uncapped" if cap == 0 else "%d fps" % cap
		_phase = "Latency"
		_show_status()
		# A fresh session per cap so each section starts with an empty pool.
		# Warmup calls pre-fill it before timing begins.
		var session := C3HTTPRequest.Session.new()
		for _i in WARMUPS:
			await _time_c3(url, false)
			await _time_c3(url, true)
			await _time_c3_session(url, session, false)
			await _time_c3_session(url, session, true)
			await _time_native(url, false)
			await _time_native(url, true)
		var c3_coop: Array[int] = []
		var c3_threaded: Array[int] = []
		var c3_session_coop: Array[int] = []
		var c3_session_threaded: Array[int] = []
		var native_coop: Array[int] = []
		var native_threaded: Array[int] = []
		# Interleave the variants within each run so any slow drift in machine
		# load is shared evenly rather than penalizing whichever runs last.
		for _i in RUNS:
			c3_coop.append(await _time_c3(url, false))
			c3_threaded.append(await _time_c3(url, true))
			c3_session_coop.append(await _time_c3_session(url, session, false))
			c3_session_threaded.append(await _time_c3_session(url, session, true))
			native_coop.append(await _time_native(url, false))
			native_threaded.append(await _time_native(url, true))
		Engine.max_fps = 0
		output_overlay.print_with_overlay("\n%-12s         cooperative   threaded" % label)
		output_overlay.print_with_overlay("C3HTTPRequest:        %7.2f ms   %7.2f ms" % [
			_median_ms(c3_coop), _median_ms(c3_threaded)
		])
		output_overlay.print_with_overlay("C3 (session):         %7.2f ms   %7.2f ms" % [
			_median_ms(c3_session_coop), _median_ms(c3_session_threaded)
		])
		output_overlay.print_with_overlay("native HTTPRequest:   %7.2f ms   %7.2f ms" % [
			_median_ms(native_coop), _median_ms(native_threaded)
		])


# --- Concurrency: many simultaneous requests, at a fixed frame rate ---


func _bench_concurrency(url: String) -> void:
	_server = _host_from_url(url)
	output_overlay.print_with_overlay(
		"\n== Concurrency: wall-clock to complete N simultaneous requests"
		+ " (median of %d batches, %d fps) ==" % [CONCURRENCY_REPS, CONCURRENCY_FPS]
	)
	Engine.max_fps = CONCURRENCY_FPS
	output_overlay.print_with_overlay("    N   C3 coop      nat coop     C3 thread    nat thread")
	for n: int in CONCURRENCY_LEVELS:
		_phase = "Concurrency · N=%d" % n
		_show_status()
		await _time_c3_concurrent(url, n, false)  # warmup
		await _time_c3_concurrent(url, n, true)
		await _time_native_concurrent(url, n, false)
		await _time_native_concurrent(url, n, true)
		var c3_coop: Array[int] = []
		var c3_threaded: Array[int] = []
		var native_coop: Array[int] = []
		var native_threaded: Array[int] = []
		for _r in CONCURRENCY_REPS:
			c3_coop.append(await _time_c3_concurrent(url, n, false))
			c3_threaded.append(await _time_c3_concurrent(url, n, true))
			native_coop.append(await _time_native_concurrent(url, n, false))
			native_threaded.append(await _time_native_concurrent(url, n, true))
		output_overlay.print_with_overlay(
			"%5d   %8.2f ms   %8.2f ms   %8.2f ms   %8.2f ms"
			% [n, _median_ms(c3_coop), _median_ms(native_coop), _median_ms(c3_threaded), _median_ms(native_threaded)]
		)
	Engine.max_fps = 0


# --- Single-request timers (microseconds) ---


func _time_c3(url: String, use_threads: bool) -> int:
	_show_status("C3HTTPRequest", use_threads)
	var opts := C3HTTPRequest.Options.new()
	opts.use_threads = use_threads
	var start := Time.get_ticks_usec()
	var res := await C3HTTPRequest.request(
		url, _auth_headers, C3HTTPRequest.Method.GET, "", opts
	)
	var elapsed := Time.get_ticks_usec() - start
	if not res.ok:
		push_error("C3HTTPRequest failed: %s" % str(res.error))
	return elapsed


func _time_c3_session(url: String, session: C3HTTPRequest.Session, use_threads: bool) -> int:
	_show_status("C3 (session)", use_threads)
	var opts := C3HTTPRequest.Options.new()
	opts.use_threads = use_threads
	opts.session = session
	var start := Time.get_ticks_usec()
	var res := await C3HTTPRequest.request(
		url, _auth_headers, C3HTTPRequest.Method.GET, "", opts
	)
	var elapsed := Time.get_ticks_usec() - start
	if not res.ok:
		push_error("C3HTTPRequest (session) failed: %s" % str(res.error))
	return elapsed


func _time_native(url: String, use_threads: bool) -> int:
	_show_status("native HTTPRequest", use_threads)
	var http := HTTPRequest.new()
	http.use_threads = use_threads
	add_child(http)
	var start := Time.get_ticks_usec()
	var err := http.request(url, _auth_headers)
	if err != OK:
		push_error("HTTPRequest failed to start: %d" % err)
		http.queue_free()
		return 0
	# request_completed(result, response_code, headers, body) — a multi-arg signal
	# await yields an Array of the arguments.
	var completed: Array = await http.request_completed
	var elapsed := Time.get_ticks_usec() - start
	var response_code: int = completed[1]
	if response_code != 200:
		push_error("HTTPRequest got status %d" % response_code)
	http.queue_free()
	return elapsed


# --- Concurrent timers (microseconds for the whole batch) ---


# Fires n C3HTTPRequest calls as detached coroutines, then waits for all to
# finish. They share the same per-frame polls, so they advance in parallel.
func _time_c3_concurrent(url: String, n: int, use_threads: bool) -> int:
	_show_status("C3HTTPRequest", use_threads)
	var done := [0]
	var start := Time.get_ticks_usec()
	for _i in n:
		_run_one_c3(url, done, use_threads)
	while done[0] < n:
		await get_tree().process_frame
	var elapsed := Time.get_ticks_usec() - start
	return elapsed


func _run_one_c3(url: String, done: Array, use_threads: bool) -> void:
	var opts := C3HTTPRequest.Options.new()
	opts.use_threads = use_threads
	var res := await C3HTTPRequest.request(
		url, _auth_headers, C3HTTPRequest.Method.GET, "", opts
	)
	if not res.ok:
		push_error("C3HTTPRequest failed: %s" % str(res.error))
	done[0] += 1


# Issues n native requests at once — which requires n nodes, since each
# HTTPRequest handles only one request at a time.
func _time_native_concurrent(url: String, n: int, use_threads: bool) -> int:
	_show_status("native HTTPRequest", use_threads)
	var nodes: Array[HTTPRequest] = []
	var done := [0]
	for _i in n:
		var http := HTTPRequest.new()
		http.use_threads = use_threads
		add_child(http)
		http.request_completed.connect(
			_count_completion.bind(done), CONNECT_ONE_SHOT
		)
		nodes.append(http)
	var start := Time.get_ticks_usec()
	for http in nodes:
		http.request(url, _auth_headers)
	while done[0] < n:
		await get_tree().process_frame
	var elapsed := Time.get_ticks_usec() - start
	for http in nodes:
		http.queue_free()
	return elapsed


func _count_completion(
	_result: int,
	_code: int,
	_headers: PackedStringArray,
	_body: PackedByteArray,
	done: Array
) -> void:
	done[0] += 1


# --- File download: stream a large body to disk, swept across body sizes ---


func _bench_download() -> void:
	_server = _host_from_url(DOWNLOAD_URL)
	output_overlay.print_with_overlay("\n== File download to disk (median of %d runs, %d fps) ==" % [
		DOWNLOAD_REPS, DOWNLOAD_FPS
	])
	output_overlay.print_with_overlay("Target: %s" % (DOWNLOAD_URL % (DOWNLOAD_SIZES_MB[0] * 1024 * 1024)))
	Engine.max_fps = DOWNLOAD_FPS
	for mb: int in DOWNLOAD_SIZES_MB:
		var url := DOWNLOAD_URL % (mb * 1024 * 1024)
		_phase = "Download · %d MB" % mb
		_show_status()
		# Warmup primes DNS, TLS, and routing before timing.
		await _time_c3_download(url, false)
		await _time_native_download(url, false)
		var c3_coop: Array[int] = []
		var c3_threaded: Array[int] = []
		var native_coop: Array[int] = []
		var native_threaded: Array[int] = []
		for _r in DOWNLOAD_REPS:
			c3_coop.append(await _time_c3_download(url, false))
			c3_threaded.append(await _time_c3_download(url, true))
			native_coop.append(await _time_native_download(url, false))
			native_threaded.append(await _time_native_download(url, true))
		output_overlay.print_with_overlay("\n%-12s         cooperative   threaded" % ("%d MB" % mb))
		output_overlay.print_with_overlay("C3HTTPRequest:        %7.2f ms   %7.2f ms" % [
			_median_ms(c3_coop), _median_ms(c3_threaded)
		])
		output_overlay.print_with_overlay("native HTTPRequest:   %7.2f ms   %7.2f ms" % [
			_median_ms(native_coop), _median_ms(native_threaded)
		])
	Engine.max_fps = 0
	DirAccess.remove_absolute(DOWNLOAD_PATH)


func _time_c3_download(url: String, use_threads: bool) -> int:
	_show_status("C3HTTPRequest", use_threads)
	var opts := C3HTTPRequest.Options.new()
	opts.use_threads = use_threads
	opts.download_file = DOWNLOAD_PATH
	opts.download_chunk_size = DOWNLOAD_CHUNK
	var start := Time.get_ticks_usec()
	var res := await C3HTTPRequest.request(
		url, _auth_headers, C3HTTPRequest.Method.GET, "", opts
	)
	var elapsed := Time.get_ticks_usec() - start
	if not res.ok:
		push_error("C3HTTPRequest download failed: %s" % str(res.error))
	return elapsed


func _time_native_download(url: String, use_threads: bool) -> int:
	_show_status("native HTTPRequest", use_threads)
	var http := HTTPRequest.new()
	http.use_threads = use_threads
	http.download_file = DOWNLOAD_PATH
	http.download_chunk_size = DOWNLOAD_CHUNK
	add_child(http)
	var start := Time.get_ticks_usec()
	var err := http.request(url, _auth_headers)
	if err != OK:
		push_error("HTTPRequest download failed to start: %d" % err)
		http.queue_free()
		return 0
	var completed: Array = await http.request_completed
	var elapsed := Time.get_ticks_usec() - start
	var response_code: int = completed[1]
	if response_code != 200:
		push_error("HTTPRequest download got status %d" % response_code)
	http.queue_free()
	return elapsed


func _host_from_url(url: String) -> String:
	var after_scheme := url.split("://", true, 1)
	var host_part := after_scheme[1] if after_scheme.size() > 1 else url
	return host_part.split("/")[0].split("?")[0]


# Short commit hash of the working tree, with a "-dirty" suffix when there are
# uncommitted changes, so a posted result names the exact version that produced
# it. Returns "unknown" when git is unavailable (e.g. an exported build).
func _git_commit() -> String:
	var output: Array = []
	if OS.execute("git", ["rev-parse", "--short", "HEAD"], output) != 0:
		return "unknown"
	var commit := (output[0] as String).strip_edges()
	if commit.is_empty():
		return "unknown"
	var status: Array = []
	OS.execute("git", ["status", "--porcelain"], status)
	if status.size() > 0 and not (status[0] as String).strip_edges().is_empty():
		commit += "-dirty"
	return commit


func _median_ms(samples: Array[int]) -> float:
	var n := samples.size()
	if n == 0:
		return 0.0
	samples.sort()
	var mid := floori(float(n) / 2)
	if n % 2 == 1:
		return samples[mid] / 1000.0
	return (samples[mid - 1] + samples[mid]) / 2.0 / 1000.0
