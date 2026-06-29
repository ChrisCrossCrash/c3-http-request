extends Node
## Benchmark: C3Http vs Godot's HTTPRequest, each in cooperative
## and threaded modes, plus a keep-alive C3 (session) variant.
##
## Targets the hosted benchmark API at api.chriskumm.com by default. To run
## locally instead, start [code]python benchmark_server.py[/code] and change
## SERVER_BASE to [code]"http://127.0.0.1:8927"[/code].
##
## Auth is sent only when PERSONAL_API_KEY is set. The local server needs no key;
## set the variable (and run it with a matching --token) to hit a protected host.
##
## Numbers are reported as medians (robust to the occasional GC/scheduler hiccup).
##
## Each scenario prints GitHub-flavored markdown tables — a main four-variant
## table (C3/native × cooperative/threaded) and a session sub-table — ready to
## paste straight into BENCHMARK.md.

# Base URL of the benchmark server. This server is configured to not slow-start
# after long idle periods (net.ipv4.tcp_slow_start_after_idle=0), which is a
# common but not universal configuration.
const SERVER_BASE := "https://api.chriskumm.com"
const LATENCY_URL := SERVER_BASE + "/api/benchmark/ping/"
# Returns exactly <bytes> zero bytes with a Content-Length header.
const DOWNLOAD_URL := SERVER_BASE + "/api/benchmark/download/%d/"
# Frame caps to sweep for the latency benchmark. 0 means uncapped (the headless
# default) — the control case where no per-frame gate exists.
const FRAME_CAPS: Array[int] = [0, 120, 60, 30]
const WARMUPS := 3
const RUNS := 25
const SLOW_START_SIZES_KB: Array[int] = [
	10, # Control: fits inside IW10, so no extra RTT is needed.
	20, # >14.6 KB, so a fresh connection needs an extra RTT, warm session does not.
	400 # Large: significantly exceeds IW10, so fresh connections need many RTTs.
]
const SLOW_START_REPS := 25
const SLOW_START_FPS := 60
# File download benchmark: body sizes in MB, streamed to disk, run at 60 fps.
const DOWNLOAD_SIZES_MB: Array[int] = [1, 8, 32]
const DOWNLOAD_REPS := 25
# One warmup per variant is enough here — these transfers are large, and the
# warmup's only job is to prime DNS, TLS, and routing before timing.
const DOWNLOAD_WARMUPS := 1
const DOWNLOAD_CHUNK := 65536
const DOWNLOAD_FPS := 60
const DOWNLOAD_PATH := "user://benchmark_download.bin"
# Number of recent frames the on-screen FPS readout averages over.
const FPS_WINDOW := 30
# Status-label colors: client (C3 vs native) and mode (cooperative vs threaded).
const COLOR_C3 := "#4ec9b0"        # teal — C3Http
const COLOR_SESSION := "#dcdcaa"   # gold — C3 (session)
const COLOR_NATIVE := "#e0a060"    # amber — HTTPRequest
const COLOR_COOP := "#569cd6"      # blue — cooperative
const COLOR_THREADED := "#c586c0"  # purple — threaded
const COLOR_DIM := "#888888"       # gray — throttle line

# The six measured variants, defined once as data and timed by a single _time().
# Each scenario runs every trial; the markdown emitters pick columns by id. Order
# here sets the interleave order within a run (variants share machine-load drift
# evenly) and the on-screen status sequence.
var _trials: Array[_TrialConfig] = [
	_TrialConfig.new("c3_coop",  "C3Http",       false, false, false),
	_TrialConfig.new("c3_thr",   "C3Http",       false, true,  false),
	_TrialConfig.new("c3s_coop", "C3 (session)",        false, false, true),
	_TrialConfig.new("c3s_thr",  "C3 (session)",        false, true,  true),
	_TrialConfig.new("nat_coop", "HTTPRequest",  true,  false, false),
	_TrialConfig.new("nat_thr",  "HTTPRequest",  true,  true,  false),
]

# Human-readable description of the benchmark phase currently running, shown in
# the status label alongside the client and mode of each timed call.
var _auth_headers: PackedStringArray = []
var _output: PackedStringArray = []
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
	await _bench_latency(LATENCY_URL)
	await _bench_slow_start()
	await _bench_download()
	_save_output()
	_print("\nDone.")
	_phase = "Done."
	_show_status()


func _process(delta: float) -> void:
	# A cap change makes the new cap's frames incomparable to the old; start fresh.
	if Engine.max_fps != _last_max_fps:
		_last_max_fps = Engine.max_fps
		_frame_times.clear()
	_frame_times.append(delta)
	if _frame_times.size() > FPS_WINDOW:
		_frame_times.remove_at(0)
	var total := 0.0
	for t: float in _frame_times:
		total += t
	var fps := _frame_times.size() / total if total > 0.0 else 0.0
	fps_label.text = "%d fps (actual)" % roundi(fps)


# --- Latency: one request at a time, swept across frame caps ---


func _bench_latency(url: String) -> void:
	_server = _host_from_url(url)
	_print("\n## Single-request latency (median of %d requests)" % RUNS)
	_print("Round-trip time for a single small GET request across frame-rate caps.")
	var rows: Array[Dictionary] = []
	for cap: int in FRAME_CAPS:
		Engine.max_fps = cap
		_phase = "Latency"
		_show_status()
		var label := "uncapped" if cap == 0 else "%d fps" % cap
		# A fresh session per cap so each section starts with an empty pool.
		# Warmup calls pre-fill it before timing begins.
		var session := C3Http.Session.new()
		var samples := await _collect(url, session, WARMUPS, RUNS)
		Engine.max_fps = 0
		rows.append({label = label, samples = samples})
	_emit_tables("Frame rate", rows)


# --- Small download: shows TCP slow-start savings on a warm session ---


func _bench_slow_start() -> void:
	_server = _host_from_url(DOWNLOAD_URL % 0)
	_print(
		"\n## Small download: slow-start control vs. straddled IW10"
		+ " (median of %d runs, %d fps)" % [SLOW_START_REPS, SLOW_START_FPS]
	)
	_print("Tests how TCP slow-start affects small responses.")
	Engine.max_fps = SLOW_START_FPS
	# A single session shared across all sizes so the cwnd is already warm by the
	# time the 20 KB and 400 KB rows run.
	var session := C3Http.Session.new()
	var rows: Array[Dictionary] = []
	for kb: int in SLOW_START_SIZES_KB:
		var url := DOWNLOAD_URL % (kb * 1024)
		_phase = "Small download · %d KB" % kb
		_show_status()
		var samples := await _collect(url, session, WARMUPS, SLOW_START_REPS)
		rows.append({label = "%d KB" % kb, samples = samples})
	Engine.max_fps = 0
	_emit_tables("Body size", rows)


# --- File download: stream a large body to disk, swept across body sizes ---


func _bench_download() -> void:
	_server = _host_from_url(DOWNLOAD_URL)
	_print(
		"\n## File download to disk (median of %d runs, %d fps)" % [
			DOWNLOAD_REPS, DOWNLOAD_FPS
		]
	)
	_print(
		"Target: %s" % DOWNLOAD_URL.replace("%d", "{byte_count}")
	)
	_print("Measures throughput for downloading bodies of increasing size to disk.")
	Engine.max_fps = DOWNLOAD_FPS
	# A session shared across sizes so its connections are already warm by the
	# time timing begins.
	var session := C3Http.Session.new()
	var rows: Array[Dictionary] = []
	for mb: int in DOWNLOAD_SIZES_MB:
		var url := DOWNLOAD_URL % (mb * 1024 * 1024)
		_phase = "Download · %d MB" % mb
		_show_status()
		var samples := await _collect(
			url, session, DOWNLOAD_WARMUPS, DOWNLOAD_REPS, DOWNLOAD_PATH, DOWNLOAD_CHUNK
		)
		rows.append({label = "%d MB" % mb, samples = samples})
	Engine.max_fps = 0
	DirAccess.remove_absolute(DOWNLOAD_PATH)
	_emit_tables("Body size", rows)


# --- Measurement ---


# Runs every trial through `warmups` priming passes (not recorded) and then `reps`
# timed passes, interleaving the variants within each pass. Returns a dictionary
# keyed by trial id, each value an Array[int] of per-run elapsed microseconds.
func _collect(
	url: String, session: C3Http.Session, warmups: int, reps: int,
	download_path := "", download_chunk := 0
) -> Dictionary:
	for _i: int in warmups:
		for trial: _TrialConfig in _trials:
			await _time(trial, url, session, download_path, download_chunk)
	var samples := {}
	for trial: _TrialConfig in _trials:
		var arr: Array[int] = []
		samples[trial.id] = arr
	for _r: int in reps:
		for trial: _TrialConfig in _trials:
			var elapsed := await _time(
				trial, url, session, download_path, download_chunk
			)
			(samples[trial.id] as Array[int]).append(elapsed)
	return samples


# Times one trial's single request, returning elapsed microseconds. A C3 trial
# builds Options from its fields (threading, session, download); a native trial
# routes to the HTTPRequest node path.
func _time(
	trial: _TrialConfig, url: String, session: C3Http.Session,
	download_path := "", download_chunk := 0
) -> int:
	_show_status(trial)
	if trial.is_native:
		return await _time_native(
			url, trial.use_threads, download_path, download_chunk
		)
	var opts := C3Http.Options.new()
	opts.use_threads = trial.use_threads
	if trial.use_session:
		opts.session = session
	if not download_path.is_empty():
		opts.download_file = download_path
		opts.download_chunk_size = download_chunk
	var start := Time.get_ticks_usec()
	var res := await C3Http.request(
		url, _auth_headers, HTTPClient.METHOD_GET, "", opts
	)
	var elapsed := Time.get_ticks_usec() - start
	if not res.ok:
		push_error("%s failed: %s" % [trial.client_name, str(res.error)])
	return elapsed


func _time_native(
	url: String, use_threads: bool, download_path := "", download_chunk := 0
) -> int:
	var http := HTTPRequest.new()
	http.use_threads = use_threads
	if not download_path.is_empty():
		http.download_file = download_path
		http.download_chunk_size = download_chunk
	add_child(http)
	var start := Time.get_ticks_usec()
	var err := http.request(url, _auth_headers)
	if err != OK:
		push_error("HTTPRequest failed to start: %d" % err)
		http.queue_free()
		return 0
	# request_completed(result, response_code, headers, body) — a multi-arg
	# signal await yields an Array of the arguments.
	var completed: Array = await http.request_completed
	var elapsed := Time.get_ticks_usec() - start
	var response_code: int = completed[1]
	if response_code != 200:
		push_error("HTTPRequest got status %d" % response_code)
	http.queue_free()
	return elapsed


# --- Output ---


# Prints a merged median table (all six variants) followed by the five-number
# summary table. col0 is the swept dimension's header; rows each carry a `label`
# and the `samples` dict from _collect.
func _emit_tables(col0: String, rows: Array[Dictionary]) -> void:
	var headers: Array[String] = [
		col0, "nat_coop", "c3_coop", "c3s_coop", "nat_thr", "c3_thr", "c3s_thr"
	]
	var cells: Array[Array] = []
	for row: Dictionary in rows:
		var s: Dictionary = row["samples"]
		cells.append([
			row["label"],
			_fmt(s["nat_coop"]), _fmt(s["c3_coop"]), _fmt(s["c3s_coop"]),
			_fmt(s["nat_thr"]), _fmt(s["c3_thr"]), _fmt(s["c3s_thr"]),
		])
	_print_markdown_table(headers, cells)
	_emit_stats_table(rows)


# Prints a GitHub-flavored markdown table, each column padded to its widest cell
# (header or value, minimum 3 for the separator) so the raw output stays aligned
# and readable, not just the rendered form.
func _print_markdown_table(headers: Array[String], rows: Array[Array]) -> void:
	var widths: Array[int] = []
	for header: String in headers:
		widths.append(maxi(3, header.length()))
	for row: Array in rows:
		for i: int in row.size():
			widths[i] = maxi(widths[i], (row[i] as String).length())
	var separators: Array[String] = []
	for w: int in widths:
		separators.append("-".repeat(w))
	_print("")
	_print(_md_row(headers, widths))
	_print(_md_row(separators, widths))
	for row: Array in rows:
		_print(_md_row(row, widths))


# Joins one row's cells into a padded "| a | b | c |" markdown line.
func _md_row(cells: Array, widths: Array[int]) -> String:
	var parts: PackedStringArray = []
	for i: int in cells.size():
		parts.append((cells[i] as String).rpad(widths[i]))
	return "| " + " | ".join(parts) + " |"


func _print(text: String) -> void:
	output_overlay.print_with_overlay(text)
	_output.append(text)


func _save_output() -> void:
	var file := FileAccess.open("res://BENCHMARK.md", FileAccess.WRITE)
	if file == null:
		push_error("Failed to open BENCHMARK.md for writing: %d" % FileAccess.get_open_error())
		return
	file.store_string("\n".join(_output) + "\n")


# Prints a five-number summary markdown table (min, Q1, median, Q3, max) for all
# trials and rows so the full spread is visible alongside the median tables.
func _emit_stats_table(rows: Array[Dictionary]) -> void:
	var headers: Array[String] = ["Label", "Trial", "Min", "Q1", "Median", "Q3", "Max"]
	var cells: Array[Array] = []
	for row: Dictionary in rows:
		var label: String = row["label"]
		var s: Dictionary = row["samples"]
		for trial: _TrialConfig in _trials:
			var samples: Array[int] = (s[trial.id] as Array[int]).duplicate()
			samples.sort()
			var n := samples.size()
			cells.append([
				label,
				trial.id,
				"%.1f" % (samples[0] / 1000.0),
				"%.1f" % (_percentile_us(samples, 0.25) / 1000.0),
				"%.1f" % _median_ms(samples),
				"%.1f" % (_percentile_us(samples, 0.75) / 1000.0),
				"%.1f" % (samples[n - 1] / 1000.0),
			])
	_print_markdown_table(headers, cells)


func _print_environment() -> void:
	var v := Engine.get_version_info()
	var renderer := ProjectSettings.get_setting(
		"rendering/renderer/rendering_method", "?"
	) as String
	_print("# C3Http vs. HTTPRequest benchmark")
	_print("```")
	_print("commit %s" % _git_commit())
	_print("Godot %s | %s | %s | %s renderer" % [
		v.get("string", "?"), OS.get_name(), OS.get_processor_name(), renderer
	])
	_print("```")
	_print(
		"All timing values are in milliseconds. Tables show medians; five-number summary follows each section."
	)
	_print("")
	_print("| ID       | Description                                         |")
	_print("| -------- | --------------------------------------------------- |")
	_print("| nat_coop | Native `HTTPRequest`, cooperative (default) polling |")
	_print("| c3_coop  | C3Http, cooperative (default) polling               |")
	_print("| c3s_coop | C3Http, cooperative polling, session (keep-alive)   |")
	_print("| nat_thr  | Native `HTTPRequest`, threaded polling              |")
	_print("| c3_thr   | C3Http, threaded polling                            |")
	_print("| c3s_thr  | C3Http, threaded polling, session (keep-alive)      |")


# Refreshes the on-screen status from the current _phase. With a trial given, a
# second line names the client and mode of the call now running.
func _show_status(trial: _TrialConfig = null) -> void:
	var phase_label := (
		"%s · %s" % [_phase, _server] if not _server.is_empty() else _phase
	)
	if trial == null:
		_current_label = phase_label
		status_label.text = "[b]%s[/b]" % phase_label
		return
	var threaded: bool = trial.use_threads
	var client_name: String = trial.client_name
	var mode := "threaded" if threaded else "cooperative"
	var cap := "uncapped" if Engine.max_fps == 0 else "%d fps" % Engine.max_fps
	var client_color := COLOR_NATIVE
	if not trial.is_native:
		client_color = COLOR_SESSION if trial.use_session else COLOR_C3
	var mode_color := COLOR_THREADED if threaded else COLOR_COOP
	_current_label = "%s @ %s · %s %s" % [phase_label, cap, client_name, mode]
	var throttle := (
		"uncapped"
		if Engine.max_fps == 0
		else "throttled to %d fps" % Engine.max_fps
	)
	status_label.text = (
		"[b]%s[/b]\n[color=%s]%s[/color] — [color=%s]%s[/color]\n[color=%s]%s[/color]"
		% [phase_label, client_color, client_name, mode_color, mode, COLOR_DIM, throttle]
	)


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


func _fmt(samples: Array[int]) -> String:
	samples.sort()
	return "%.1f" % _median_ms(samples)


func _median_ms(samples: Array[int]) -> float:
	var n := samples.size()
	if n == 0:
		return 0.0
	samples.sort()
	var mid := floori(float(n) / 2)
	if n % 2 == 1:
		return samples[mid] / 1000.0
	return (samples[mid - 1] + samples[mid]) / 2.0 / 1000.0


# The q-quantile (q in [0, 1]) of a sorted sample set, in microseconds, by linear
# interpolation between the two ranks the quantile falls between. Assumes samples
# is already sorted.
func _percentile_us(samples: Array[int], q: float) -> float:
	var n := samples.size()
	if n == 0:
		return 0.0
	if n == 1:
		return samples[0]
	var pos := q * (n - 1)
	var lo := floori(pos)
	if lo + 1 >= n:
		return samples[n - 1]
	return lerp(float(samples[lo]), float(samples[lo + 1]), pos - lo)


class _TrialConfig:
	var id: String
	var client_name: String
	var is_native: bool
	var use_threads: bool
	var use_session: bool

	func _init(
		p_id: String, p_client_name: String,
		p_is_native: bool, p_use_threads: bool, p_use_session: bool
	) -> void:
		id = p_id
		client_name = p_client_name
		is_native = p_is_native
		use_threads = p_use_threads
		use_session = p_use_session
