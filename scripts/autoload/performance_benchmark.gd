extends Node

signal session_started(name: String)
signal session_ended(name: String, report: Dictionary)

var _sessions: Dictionary = {}
var _current_session: String = ""
var _session_start_time: float = 0.0

var _auto_benchmark_active: bool = false
var _auto_benchmark_duration: float = 0.0
var _auto_benchmark_elapsed: float = 0.0

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS

func start_session(name: String) -> void:
    _current_session = name
    _session_start_time = Time.get_unix_time_from_system()
    _sessions[name] = {
        "frames": [],
        "start_time": _session_start_time,
        "end_time": 0.0,
        "avg_fps": 0.0,
        "min_fps": 0.0,
        "max_fps": 0.0,
        "avg_frame_time": 0.0,
        "avg_memory": 0.0,
        "total_atoms": 0,
        "peak_draw_calls": 0,
    }
    session_started.emit(name)
    var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
    if logger:
        logger.info("PerformanceBenchmark", "Session started: %s" % name)

func record_frame() -> void:
    if _current_session.is_empty() or not _sessions.has(_current_session):
        return
    var fps := Engine.get_frames_per_second()
    var frame_time_ms := 1000.0 / maxf(fps, 0.001)
    var memory_static := Performance.get_monitor(Performance.MEMORY_STATIC)
    var memory_mb := memory_static / (1024.0 * 1024.0)
    var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
    var physics_time := Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
    var atoms := _get_atoms_count()
    var frame_data := {
        "fps": fps,
        "frame_time_ms": frame_time_ms,
        "memory_mb": memory_mb,
        "atoms": atoms,
        "draw_calls": draw_calls,
        "physics_time_ms": physics_time * 1000.0,
    }
    _sessions[_current_session]["frames"].append(frame_data)

func end_session() -> void:
    if _current_session.is_empty() or not _sessions.has(_current_session):
        return
    var session = _sessions[_current_session]
    session["end_time"] = Time.get_unix_time_from_system()
    var frames: Array = session["frames"]
    if frames.is_empty():
        session["avg_fps"] = 0.0
        session["min_fps"] = 0.0
        session["max_fps"] = 0.0
        session["avg_frame_time"] = 0.0
        session["avg_memory"] = 0.0
        session["total_atoms"] = 0
        session["peak_draw_calls"] = 0
    else:
        var total_fps := 0.0
        var min_fps := 9999.0
        var max_fps := 0.0
        var total_frame_time := 0.0
        var total_memory := 0.0
        var peak_atoms := 0
        var peak_draw_calls := 0
        for f in frames:
            total_fps += f["fps"]
            min_fps = minf(min_fps, f["fps"])
            max_fps = maxf(max_fps, f["fps"])
            total_frame_time += f["frame_time_ms"]
            total_memory += f["memory_mb"]
            peak_atoms = maxi(peak_atoms, f["atoms"])
            peak_draw_calls = maxi(peak_draw_calls, f["draw_calls"])
        var count := frames.size()
        session["avg_fps"] = total_fps / count
        session["min_fps"] = min_fps if min_fps < 9999.0 else 0.0
        session["max_fps"] = max_fps
        session["avg_frame_time"] = total_frame_time / count
        session["avg_memory"] = total_memory / count
        session["total_atoms"] = peak_atoms
        session["peak_draw_calls"] = peak_draw_calls
    var report := generate_report(_current_session)
    session_ended.emit(_current_session, report)
    var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
    if logger:
        logger.info("PerformanceBenchmark", "Session ended: %s | Avg FPS: %.1f" % [_current_session, report.get("avg_fps", 0.0)])
    _current_session = ""

func generate_report(name: String) -> Dictionary:
    if not _sessions.has(name):
        return {}
    var session = _sessions[name].duplicate(true)
    var frames: Array = session.get("frames", [])
    session["frame_count"] = frames.size()
    var start_time: float = session.get("start_time", 0.0)
    var end_time: float = session.get("end_time", 0.0)
    session["duration"] = end_time - start_time
    session["name"] = name
    return session

func export_report_json(name: String, path: String) -> void:
    var report := generate_report(name)
    if report.is_empty():
        push_warning("PerformanceBenchmark: no session named '%s' to export" % name)
        return
    var json := JSON.stringify(report, "\t")
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(json)
        file.close()
        var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
        if logger:
            logger.info("PerformanceBenchmark", "Exported report to %s" % path)
    else:
        push_error("PerformanceBenchmark: failed to write %s" % path)

func compare_reports(name_a: String, name_b: String) -> Dictionary:
    var report_a := generate_report(name_a)
    var report_b := generate_report(name_b)
    if report_a.is_empty() or report_b.is_empty():
        return {"error": "One or both reports not found"}
    var fps_a := report_a.get("avg_fps", 0.0) as float
    var fps_b := report_b.get("avg_fps", 0.0) as float
    var mem_a := report_a.get("avg_memory", 0.0) as float
    var mem_b := report_b.get("avg_memory", 0.0) as float
    var dc_a := report_a.get("peak_draw_calls", 0) as int
    var dc_b := report_b.get("peak_draw_calls", 0) as int
    var fps_delta_pct := 0.0
    if fps_a > 0.0:
        fps_delta_pct = ((fps_b - fps_a) / fps_a) * 100.0
    var mem_delta_pct := 0.0
    if mem_a > 0.0:
        mem_delta_pct = ((mem_b - mem_a) / mem_a) * 100.0
    var dc_delta_pct := 0.0
    if dc_a > 0:
        dc_delta_pct = ((dc_b - dc_a) / float(dc_a)) * 100.0
    return {
        "name_a": name_a,
        "name_b": name_b,
        "fps_delta_pct": fps_delta_pct,
        "memory_delta_pct": mem_delta_pct,
        "draw_calls_delta_pct": dc_delta_pct,
        "fps_a": fps_a,
        "fps_b": fps_b,
        "memory_a_mb": mem_a,
        "memory_b_mb": mem_b,
        "draw_calls_a": dc_a,
        "draw_calls_b": dc_b,
    }

func run_auto_benchmark(duration: float = 10.0) -> void:
    _auto_benchmark_duration = duration
    _auto_benchmark_elapsed = 0.0
    _auto_benchmark_active = true
    start_session("auto_benchmark")
    var logger = Engine.get_main_loop().root.get_node_or_null("/root/GameLogger")
    if logger:
        logger.info("PerformanceBenchmark", "Auto benchmark started for %.1f seconds" % duration)

func _process(delta: float) -> void:
    if _auto_benchmark_active:
        _auto_benchmark_elapsed += delta
        record_frame()
        _rotate_camera(delta)
        if _auto_benchmark_elapsed >= _auto_benchmark_duration:
            _auto_benchmark_active = false
            end_session()

func _rotate_camera(delta: float) -> void:
    var canvas = Engine.get_main_loop().root.get_node_or_null("ConstructionCanvas")
    if canvas and canvas.has_node("Camera3D"):
        var cam = canvas.get_node("Camera3D")
        cam.rotate_y(delta * 0.5)

func get_current_stats() -> Dictionary:
    var fps := Engine.get_frames_per_second()
    var memory_mb := Performance.get_monitor(Performance.MEMORY_STATIC) / (1024.0 * 1024.0)
    var draw_calls := RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
    var atoms := _get_atoms_count()
    return {
        "fps": fps,
        "frame_time_ms": 1000.0 / maxf(fps, 0.001),
        "memory_mb": memory_mb,
        "atoms": atoms,
        "draw_calls": draw_calls,
        "in_session": not _current_session.is_empty(),
        "session_name": _current_session,
    }

func _get_atoms_count() -> int:
    var canvas = Engine.get_main_loop().root.get_node_or_null("ConstructionCanvas")
    if canvas:
        var atoms = canvas.get_node_or_null("Atoms")
        if atoms:
            return atoms.get_child_count()
    return 0
