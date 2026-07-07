# performance_lod_test.gd
# GdUnit4 测试: PerformanceBenchmark 和 LODManager

extends GdUnitTestSuite

const __source_perf = "res://scripts/autoload/performance_benchmark.gd"
const __source_lod = "res://scripts/autoload/lod_manager.gd"

var _perf: Node = null
var _lod: Node = null
var _test_json_path: String = ""

func before_test() -> void:
    var perf_ref = load(__source_perf)
    _perf = perf_ref.new()
    var lod_ref = load(__source_lod)
    _lod = lod_ref.new()
    _test_json_path = "user://benchmarks/test_auto_export.json"

func after_test() -> void:
    _perf = null
    _lod = null
    if FileAccess.file_exists(_test_json_path):
        DirAccess.remove_absolute(_test_json_path)
    var dir := DirAccess.open("user://benchmarks")
    if dir:
        dir.list_dir_begin()
        var file := dir.get_next()
        while file != "":
            if file.begins_with("test_") and file.ends_with(".json"):
                DirAccess.remove_absolute("user://benchmarks/" + file)
            file = dir.get_next()
        dir.list_dir_end()

func test_benchmark_start_session() -> void:
    var received := {"name": ""}
    var cb := func(name: String): received["name"] = name
    _perf.session_started.connect(cb)
    _perf.start_session("test_session")
    assert_str(received["name"]).is_equal("test_session")
    _perf.session_started.disconnect(cb)

func test_benchmark_record_frame() -> void:
    _perf.start_session("record_test")
    _perf.record_frame()
    _perf.record_frame()
    var report = _perf.generate_report("record_test")
    assert_int(report["frames"].size()).is_equal(2)
    assert_float(report["frames"][0]["fps"]).is_greater(0.0)

func test_benchmark_end_session_generates_stats() -> void:
    _perf.start_session("stats_test")
    _perf.record_frame()
    _perf.record_frame()
    _perf.record_frame()
    _perf.end_session()
    var report = _perf.generate_report("stats_test")
    assert_float(report["avg_fps"]).is_greater(0.0)
    assert_float(report["min_fps"]).is_greater(0.0)
    assert_float(report["max_fps"]).is_greater(0.0)
    assert_float(report["avg_frame_time"]).is_greater(0.0)
    assert_int(report["frame_count"]).is_equal(3)

func test_benchmark_report_export() -> void:
    _perf.start_session("export_test")
    _perf.record_frame()
    _perf.end_session()
    var dir := DirAccess.open("user://")
    if dir and not dir.dir_exists("benchmarks"):
        dir.make_dir("benchmarks")
    _perf.export_report_json("export_test", _test_json_path)
    assert_bool(FileAccess.file_exists(_test_json_path)).is_true()
    var file := FileAccess.open(_test_json_path, FileAccess.READ)
    assert_bool(file != null).is_true()
    if file:
        var content := file.get_as_text()
        file.close()
        assert_str(content).contains("export_test")
        assert_str(content).contains("avg_fps")

func test_benchmark_compare_reports() -> void:
    _perf.start_session("compare_a")
    _perf.record_frame()
    _perf.end_session()
    _perf.start_session("compare_b")
    _perf.record_frame()
    _perf.record_frame()
    _perf.end_session()
    var cmp = _perf.compare_reports("compare_a", "compare_b")
    assert_bool(cmp.has("fps_delta_pct")).is_true()
    assert_bool(cmp.has("memory_delta_pct")).is_true()
    assert_bool(cmp.has("draw_calls_delta_pct")).is_true()

func test_lod_manager_registers_atom() -> void:
    var atom := MeshInstance3D.new()
    atom.mesh = SphereMesh.new()
    _lod.register_atom(atom)
    assert_int(_lod._atoms.size()).is_equal(1)
    _lod.unregister_atom(atom)
    assert_int(_lod._atoms.size()).is_equal(0)
    atom.queue_free()

func test_lod_distance_thresholds() -> void:
    var level = _lod._get_lod_level(5.0)
    assert_str(level).is_equal("high")
    level = _lod._get_lod_level(15.0)
    assert_str(level).is_equal("medium")
    level = _lod._get_lod_level(35.0)
    assert_str(level).is_equal("low")
    level = _lod._get_lod_level(60.0)
    assert_str(level).is_equal("minimal")

func test_lod_updates_mesh_segments() -> void:
    var atom := MeshInstance3D.new()
    var sphere := SphereMesh.new()
    sphere.radial_segments = 24
    sphere.rings = 16
    atom.mesh = sphere
    _lod.update_lod_for_atom(atom, "low")
    assert_int(sphere.radial_segments).is_equal(8)
    assert_int(sphere.rings).is_equal(8)
    _lod.update_lod_for_atom(atom, "minimal")
    assert_int(sphere.radial_segments).is_equal(4)
    assert_int(sphere.rings).is_equal(4)
    atom.queue_free()

func test_lod_force_level() -> void:
    _lod.set_force_lod("minimal")
    assert_str(_lod.get_current_level()).is_equal("minimal")
    _lod.clear_force_lod()
    assert_str(_lod.get_current_level()).is_equal("high")
    assert_str(_lod._force_level).is_equal("")

func test_lod_performance_fallback() -> void:
    _lod.clear_force_lod()
    _lod._current_level = "high"
    _lod._max_level_index = 3
    _lod._low_fps_timer = 0.0
    _lod._high_fps_timer = 0.0
    # Simulate 5 seconds of low FPS (15 FPS) in small steps
    for i in range(100):
        _lod._check_performance_fallback(0.05, 15.0)
    # After 100 * 0.05 = 5 seconds of low FPS, should have degraded by one level
    assert_str(_lod.get_current_level()).is_equal("medium")
    # Continue for another 5 seconds
    _lod._low_fps_timer = 0.0
    for i in range(100):
        _lod._check_performance_fallback(0.05, 15.0)
    # Should degrade to low
    assert_str(_lod.get_current_level()).is_equal("low")

func test_lod_refresh_all() -> void:
    var parent := Node3D.new()
    parent.name = "TestLODParent"
    Engine.get_main_loop().root.add_child(parent)
    var atom1 := MeshInstance3D.new()
    var atom2 := MeshInstance3D.new()
    var sphere1 := SphereMesh.new()
    var sphere2 := SphereMesh.new()
    sphere1.radial_segments = 24
    sphere2.radial_segments = 24
    atom1.mesh = sphere1
    atom2.mesh = sphere2
    atom1.position = Vector3(0, 0, 0)
    atom2.position = Vector3(100, 0, 0)
    parent.add_child(atom1)
    parent.add_child(atom2)
    _lod.register_atom(atom1)
    _lod.register_atom(atom2)
    var cam := Camera3D.new()
    cam.position = Vector3(0, 0, 0)
    parent.add_child(cam)
    _lod._camera = cam
    _lod.clear_force_lod()
    _lod.refresh_all()
    assert_int(sphere1.radial_segments).is_equal(24)
    assert_int(sphere2.radial_segments).is_equal(4)
    parent.queue_free()
