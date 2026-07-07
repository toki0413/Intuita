# particle_system_test.gd
# GdUnit4 测试: ParticleSystem 状态颜色与初始化

extends GdUnitTestSuite

const __source = "res://scripts/effects/particle_system.gd"

var _ps = null

func before() -> void:
	_ps = load(__source).new()

func after() -> void:
	if _ps != null:
		_ps.free()
		_ps = null

func test_setup_creates_particles() -> void:
	_ps.setup("crystal")
	assert_object(_ps.get_child(0)).is_not_null()

func test_update_atmosphere_changes_color() -> void:
	_ps.setup("crystal")
	var clouds_before = _ps._clouds.process_material.color if _ps._clouds and _ps._clouds.process_material else Color.WHITE
	_ps.update_atmosphere(ConservationEngine.State.CRITICAL)
	var clouds_after = _ps._clouds.process_material.color if _ps._clouds and _ps._clouds.process_material else Color.WHITE
	assert_object(clouds_after).is_not_equal(clouds_before)

func test_domain_presets_exist() -> void:
	assert_bool(_ps._domain_presets.has("crystal")).is_true()
	assert_bool(_ps._domain_presets.has("molecular")).is_true()
	assert_bool(_ps._domain_presets.has("fluid")).is_true()
