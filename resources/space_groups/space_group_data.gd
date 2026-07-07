extends Resource
# 空间群数据 - 前10个空间群
# 包含编号、Hermann-Mauguin符号、点群、晶系、Wyckoff位置

class_name SpaceGroupData

enum CrystalSystem {
	TRICLINIC,
	MONOCLINIC,
	ORTHORHOMBIC,
	TETRAGONAL,
	TRIGONAL,
	HEXAGONAL,
	CUBIC,
}

const CRYSTAL_SYSTEM_NAMES: Array[String] = [
	"Triclinic", "Monoclinic", "Orthorhombic",
	"Tetragonal", "Trigonal", "Hexagonal", "Cubic"
]


class SpaceGroup:
	var number: int
	var symbol: String
	var point_group: String
	var crystal_system: CrystalSystem
	var wyckoff_positions: Array[Dictionary]

	func _init(p_num: int, p_sym: String, p_pg: String, p_cs: CrystalSystem, p_wp: Array[Dictionary]) -> void:
		number = p_num
		symbol = p_sym
		point_group = p_pg
		crystal_system = p_cs
		wyckoff_positions = p_wp


var groups: Array[SpaceGroup] = []


func _init() -> void:
	_build_data()


func _build_data() -> void:
	groups.clear()

	# 1. P1 - 三斜晶系
	groups.append(SpaceGroup.new(
		1, "P1", "1", CrystalSystem.TRICLINIC,
		[{"label": "a", "multiplicity": 1, "site_symmetry": "1", "positions": [[0.0, 0.0, 0.0]]}]
	))

	# 2. P-1 - 三斜晶系
	groups.append(SpaceGroup.new(
		2, "P-1", "-1", CrystalSystem.TRICLINIC,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "-1", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 1, "site_symmetry": "1", "positions": [[0.0, 0.5, 0.0]]},
		]
	))

	# 3. P2 - 单斜晶系
	groups.append(SpaceGroup.new(
		3, "P2", "2", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "2", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 1, "site_symmetry": "1", "positions": [[0.0, 0.0, 0.5]]},
		]
	))

	# 4. P2₁ - 单斜晶系
	groups.append(SpaceGroup.new(
		4, "P2₁", "2", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "2", "positions": [[0.0, 0.0, 0.0]]},
		]
	))

	# 5. C2 - 单斜晶系
	groups.append(SpaceGroup.new(
		5, "C2", "2", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "2", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 2, "site_symmetry": "1", "positions": [[0.0, 0.0, 0.25]]},
		]
	))

	# 6. Pm - 单斜晶系
	groups.append(SpaceGroup.new(
		6, "Pm", "m", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "m", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 1, "site_symmetry": "1", "positions": [[0.0, 0.5, 0.0]]},
		]
	))

	# 7. Pc - 单斜晶系
	groups.append(SpaceGroup.new(
		7, "Pc", "m", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "m", "positions": [[0.0, 0.0, 0.0]]},
		]
	))

	# 8. Cm - 单斜晶系
	groups.append(SpaceGroup.new(
		8, "Cm", "m", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "m", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 2, "site_symmetry": "1", "positions": [[0.0, 0.0, 0.5]]},
		]
	))

	# 9. Cc - 单斜晶系
	groups.append(SpaceGroup.new(
		9, "Cc", "m", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "m", "positions": [[0.0, 0.0, 0.0]]},
		]
	))

	# 10. P2/m - 单斜晶系
	groups.append(SpaceGroup.new(
		10, "P2/m", "2/m", CrystalSystem.MONOCLINIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "2/m", "positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 2, "site_symmetry": "2", "positions": [[0.0, 0.0, 0.5]]},
			{"label": "c", "multiplicity": 2, "site_symmetry": "m", "positions": [[0.0, 0.5, 0.0]]},
			{"label": "d", "multiplicity": 1, "site_symmetry": "1", "positions": [[0.25, 0.25, 0.25]]},
		]
	))

	# 11. Fm-3m (225) - 立方晶系，面心立方
	# NaCl结构：Na在4a (0,0,0)，Cl在4b (1/2,1/2,1/2)
	# 面心平移: (0,0,0), (1/2,1/2,0), (1/2,0,1/2), (0,1/2,1/2)
	groups.append(SpaceGroup.new(
		225, "Fm-3m", "m-3m", CrystalSystem.CUBIC,
		[
			# 4a: (0,0,0) + 面心 -> Na位点（岩盐结构）
			{
				"label": "4a",
				"multiplicity": 4,
				"site_symmetry": "m-3m",
				"positions": [
					[0.0, 0.0, 0.0],
					[0.5, 0.5, 0.0],
					[0.5, 0.0, 0.5],
					[0.0, 0.5, 0.5]
				]
			},
			# 4b: (1/2,1/2,1/2) + 面心 -> Cl位点（岩盐结构）
			{
				"label": "4b",
				"multiplicity": 4,
				"site_symmetry": "m-3m",
				"positions": [
					[0.5, 0.5, 0.5],
					[0.0, 0.0, 0.5],
					[0.0, 0.5, 0.0],
					[0.5, 0.0, 0.0]
				]
			},
			# 8c: (1/4,1/4,1/4) + 面心 -> 萤石结构阳离子位
			{
				"label": "8c",
				"multiplicity": 8,
				"site_symmetry": "-43m",
				"positions": [
					[0.25, 0.25, 0.25], [0.75, 0.75, 0.25],
					[0.75, 0.25, 0.75], [0.25, 0.75, 0.75],
					[0.25, 0.25, 0.75], [0.75, 0.75, 0.75],
					[0.75, 0.25, 0.25], [0.25, 0.75, 0.25]
				]
			},
			# 32f: (x,x,x) 一般位置，x≈0.0625等
			{
				"label": "32f",
				"multiplicity": 32,
				"site_symmetry": ".m",
				"positions": [
					[0.0625, 0.0625, 0.0625], [0.9375, 0.9375, 0.0625],
					[0.9375, 0.0625, 0.9375], [0.0625, 0.9375, 0.9375],
					[0.5625, 0.5625, 0.0625], [0.4375, 0.4375, 0.0625],
					[0.4375, 0.5625, 0.9375], [0.5625, 0.4375, 0.9375],
					[0.5625, 0.0625, 0.5625], [0.4375, 0.9375, 0.5625],
					[0.4375, 0.0625, 0.4375], [0.5625, 0.9375, 0.4375],
					[0.0625, 0.5625, 0.5625], [0.9375, 0.4375, 0.5625],
					[0.9375, 0.5625, 0.4375], [0.0625, 0.4375, 0.4375],
					[0.9375, 0.9375, 0.9375], [0.0625, 0.0625, 0.9375],
					[0.0625, 0.9375, 0.0625], [0.9375, 0.0625, 0.0625],
					[0.4375, 0.4375, 0.9375], [0.5625, 0.5625, 0.9375],
					[0.5625, 0.4375, 0.0625], [0.4375, 0.5625, 0.0625],
					[0.4375, 0.9375, 0.4375], [0.5625, 0.0625, 0.4375],
					[0.5625, 0.9375, 0.9375], [0.4375, 0.0625, 0.9375],
					[0.4375, 0.9375, 0.9375], [0.5625, 0.0625, 0.0625],
					[0.9375, 0.4375, 0.4375], [0.0625, 0.5625, 0.4375],
					[0.0625, 0.4375, 0.9375], [0.9375, 0.5625, 0.9375]
				]
			},
			# 48h: (x,1/2,0) 等价位置
			{
				"label": "48h",
				"multiplicity": 48,
				"site_symmetry": "mm2",
				"positions": [
					[0.125, 0.5, 0.0], [0.875, 0.5, 0.0],
					[0.125, 0.0, 0.5], [0.875, 0.0, 0.5],
					[0.5, 0.125, 0.0], [0.5, 0.875, 0.0],
					[0.0, 0.125, 0.5], [0.0, 0.875, 0.5],
					[0.625, 0.5, 0.5], [0.375, 0.5, 0.5],
					[0.625, 0.0, 0.0], [0.375, 0.0, 0.0],
					[0.5, 0.625, 0.5], [0.5, 0.375, 0.5],
					[0.0, 0.625, 0.0], [0.0, 0.375, 0.0],
					[0.125, 0.5, 0.5], [0.875, 0.5, 0.5],
					[0.125, 0.0, 0.0], [0.875, 0.0, 0.0],
					[0.5, 0.125, 0.5], [0.5, 0.875, 0.5],
					[0.0, 0.125, 0.0], [0.0, 0.875, 0.0],
					[0.625, 0.5, 0.0], [0.375, 0.5, 0.0],
					[0.625, 0.0, 0.5], [0.375, 0.0, 0.5],
					[0.5, 0.625, 0.0], [0.5, 0.375, 0.0],
					[0.0, 0.625, 0.5], [0.0, 0.375, 0.5],
					[0.875, 0.5, 0.0], [0.125, 0.5, 0.0],
					[0.875, 0.0, 0.5], [0.125, 0.0, 0.5],
					[0.5, 0.875, 0.0], [0.5, 0.125, 0.0],
					[0.0, 0.875, 0.5], [0.0, 0.125, 0.5],
					[0.375, 0.5, 0.5], [0.625, 0.5, 0.5],
					[0.375, 0.0, 0.0], [0.625, 0.0, 0.0],
					[0.5, 0.375, 0.5], [0.5, 0.625, 0.5],
					[0.0, 0.375, 0.0], [0.0, 0.625, 0.0],
					[0.875, 0.5, 0.5], [0.125, 0.5, 0.5],
					[0.875, 0.0, 0.0], [0.125, 0.0, 0.0],
					[0.5, 0.875, 0.5], [0.5, 0.125, 0.5],
					[0.0, 0.875, 0.0], [0.0, 0.125, 0.0]
				]
			},
			# 96k: (x,y,0) 一般位置
			{
				"label": "96k",
				"multiplicity": 96,
				"site_symmetry": "..m",
				"positions": []  # 太多了，运行时按需要生成
			}
		]
	))

	# 12. Pm-3m (221) - 立方晶系，简单立方
	# 钙钛矿结构：A位在1a(0,0,0)，B位在1b(1/2,1/2,1/2)，O位在3c面心和3d棱心
	groups.append(SpaceGroup.new(
		221, "Pm-3m", "m-3m", CrystalSystem.CUBIC,
		[
			# 1a: 原点 - 钙钛矿A位（如BaTiO3中的Ba）
			{
				"label": "1a",
				"multiplicity": 1,
				"site_symmetry": "m-3m",
				"positions": [[0.0, 0.0, 0.0]]
			},
			# 1b: 体心 - 钙钛矿B位（如Ti）
			{
				"label": "1b",
				"multiplicity": 1,
				"site_symmetry": "m-3m",
				"positions": [[0.5, 0.5, 0.5]]
			},
			# 3c: 面心 - 钙钛矿氧位点（如O）
			{
				"label": "3c",
				"multiplicity": 3,
				"site_symmetry": "4/mm.m",
				"positions": [
					[0.5, 0.5, 0.0],
					[0.5, 0.0, 0.5],
					[0.0, 0.5, 0.5]
				]
			},
			# 3d: 棱心
			{
				"label": "3d",
				"multiplicity": 3,
				"site_symmetry": "4mm.",
				"positions": [
					[0.5, 0.0, 0.0],
					[0.0, 0.5, 0.0],
					[0.0, 0.0, 0.5]
				]
			},
			# 1e: (1/2,1/2,0) - 特殊位置
			{
				"label": "1e",
				"multiplicity": 1,
				"site_symmetry": "4mm",
				"positions": [[0.5, 0.5, 0.0]]
			},
			# 3f: 棱心变体
			{
				"label": "3f",
				"multiplicity": 3,
				"site_symmetry": "mmm",
				"positions": [
					[0.5, 0.0, 0.0],
					[0.0, 0.5, 0.0],
					[0.0, 0.0, 0.5]
				]
			}
		]
	))

	# 13. Pna2₁ (33) - 正交晶系，极性空间群
	# 用于LiFePO4变体、铁电材料
	groups.append(SpaceGroup.new(
		33, "Pna2₁", "mm2", CrystalSystem.ORTHORHOMBIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "1",
			"positions": [
				[0.0, 0.0, 0.0], [0.5, 0.5, 0.0],
				[0.0, 0.5, 0.5], [0.5, 0.0, 0.5]
			]},
		]
	))

	# 14. Pnma (62) - 正交晶系
	# LiFePO4结构：Li@4a, Fe@4c, P@4c, O@4c+8d
	groups.append(SpaceGroup.new(
		62, "Pnma", "mmm", CrystalSystem.ORTHORHOMBIC,
		[
			{"label": "a", "multiplicity": 4, "site_symmetry": "-1",
			"positions": [
				[0.0, 0.0, 0.0], [0.5, 0.0, 0.5],
				[0.0, 0.5, 0.0], [0.5, 0.5, 0.5]
			]},
			{"label": "b", "multiplicity": 4, "site_symmetry": "-1",
			"positions": [
				[0.0, 0.0, 0.5], [0.5, 0.0, 0.0],
				[0.0, 0.5, 0.5], [0.5, 0.5, 0.0]
			]},
			{"label": "c", "multiplicity": 4, "site_symmetry": ".m.",
			"positions": [
				[0.25, 0.25, 0.0], [0.75, 0.25, 0.5],
				[0.25, 0.75, 0.0], [0.75, 0.75, 0.5]
			]},
			{"label": "d", "multiplicity": 8, "site_symmetry": "1",
			"positions": [
				[0.1, 0.2, 0.3], [0.9, 0.2, 0.7],
				[0.1, 0.8, 0.3], [0.9, 0.8, 0.7],
				[0.4, 0.2, 0.3], [0.6, 0.2, 0.7],
				[0.4, 0.8, 0.3], [0.6, 0.8, 0.7]
			]},
		]
	))

	# 15. P4mm (99) - 四方晶系，极性
	# 钙钛矿变体、铁电相变
	groups.append(SpaceGroup.new(
		99, "P4mm", "4mm", CrystalSystem.TETRAGONAL,
		[
			{"label": "a", "multiplicity": 1, "site_symmetry": "4mm",
			"positions": [[0.0, 0.0, 0.0]]},
			{"label": "b", "multiplicity": 1, "site_symmetry": "4mm",
			"positions": [[0.5, 0.5, 0.0]]},
			{"label": "c", "multiplicity": 2, "site_symmetry": "2mm",
			"positions": [[0.5, 0.0, 0.0], [0.0, 0.5, 0.0]]},
			{"label": "d", "multiplicity": 2, "site_symmetry": "2mm",
			"positions": [[0.5, 0.0, 0.5], [0.0, 0.5, 0.5]]},
			{"label": "e", "multiplicity": 2, "site_symmetry": ".m.",
			"positions": [[0.0, 0.3, 0.0], [0.3, 0.0, 0.0]]},
			{"label": "f", "multiplicity": 2, "site_symmetry": ".m.",
			"positions": [[0.5, 0.3, 0.0], [0.3, 0.5, 0.0]]},
			{"label": "g", "multiplicity": 4, "site_symmetry": "1",
			"positions": [[0.2, 0.3, 0.0], [0.3, 0.8, 0.0], [0.8, 0.7, 0.0], [0.7, 0.2, 0.0]]},
		]
	))

	# 16. P4₂/mnm (136) - 四方晶系
	# 金红石TiO2：Ti@2a, O@4f
	groups.append(SpaceGroup.new(
		136, "P4₂/mnm", "4/mmm", CrystalSystem.TETRAGONAL,
		[
			{"label": "a", "multiplicity": 2, "site_symmetry": "4/m..",
			"positions": [[0.0, 0.0, 0.0], [0.5, 0.5, 0.5]]},
			{"label": "b", "multiplicity": 4, "site_symmetry": "..2/m",
			"positions": [
				[0.3, 0.3, 0.0], [0.7, 0.7, 0.0],
				[0.7, 0.3, 0.5], [0.3, 0.7, 0.5]
			]},
			{"label": "c", "multiplicity": 2, "site_symmetry": "4/m..",
			"positions": [[0.0, 0.0, 0.5], [0.5, 0.5, 0.0]]},
			{"label": "d", "multiplicity": 4, "site_symmetry": "..2/m",
			"positions": [
				[0.2, 0.2, 0.0], [0.8, 0.8, 0.0],
				[0.8, 0.2, 0.5], [0.2, 0.8, 0.5]
			]},
		]
	))

	# 17. R-3m (166) - 三方晶系
	# 层状氧化物：LiCoO2等
	groups.append(SpaceGroup.new(
		166, "R-3m", "-3m", CrystalSystem.TRIGONAL,
		[
			{"label": "a", "multiplicity": 3, "site_symmetry": "-3m",
			"positions": [[0.0, 0.0, 0.0], [0.667, 0.333, 0.333], [0.333, 0.667, 0.667]]},
			{"label": "b", "multiplicity": 3, "site_symmetry": "-3m",
			"positions": [[0.0, 0.0, 0.5], [0.667, 0.333, 0.833], [0.333, 0.667, 0.167]]},
			{"label": "c", "multiplicity": 6, "site_symmetry": "3m",
			"positions": [
				[0.0, 0.0, 0.25], [0.0, 0.0, 0.75],
				[0.667, 0.333, 0.583], [0.667, 0.333, 0.083],
				[0.333, 0.667, 0.917], [0.333, 0.667, 0.417]
			]},
			{"label": "d", "multiplicity": 6, "site_symmetry": ".2/m",
			"positions": [
				[0.5, 0.0, 0.0], [0.0, 0.5, 0.0], [0.5, 0.5, 0.0],
				[0.167, 0.333, 0.333], [0.333, 0.167, 0.333], [0.833, 0.667, 0.667]
			]},
			{"label": "e", "multiplicity": 6, "site_symmetry": ".2/m",
			"positions": [
				[0.5, 0.0, 0.5], [0.0, 0.5, 0.5], [0.5, 0.5, 0.5],
				[0.167, 0.333, 0.833], [0.333, 0.167, 0.833], [0.833, 0.667, 0.167]
			]},
		]
	))

	# 18. Fd-3m (227) - 立方晶系，面心立方
	# 金刚石结构：C@8a + 8b；尖晶石：Mg@8a, Al@16d, O@32e
	groups.append(SpaceGroup.new(
		227, "Fd-3m", "m-3m", CrystalSystem.CUBIC,
		[
			# 8a: (0,0,0) + 面心平移
			{"label": "a", "multiplicity": 8, "site_symmetry": "-43m",
			"positions": [
				[0.0, 0.0, 0.0], [0.5, 0.5, 0.0], [0.5, 0.0, 0.5], [0.0, 0.5, 0.5],
				[0.25, 0.25, 0.25], [0.75, 0.75, 0.25], [0.75, 0.25, 0.75], [0.25, 0.75, 0.75]
			]},
			# 8b: (1/2,1/2,1/2) + 面心平移
			{"label": "b", "multiplicity": 8, "site_symmetry": "-43m",
			"positions": [
				[0.5, 0.5, 0.5], [0.0, 0.0, 0.5], [0.0, 0.5, 0.0], [0.5, 0.0, 0.0],
				[0.75, 0.75, 0.75], [0.25, 0.25, 0.75], [0.25, 0.75, 0.25], [0.75, 0.25, 0.25]
			]},
			# 16c: (1/8,1/8,1/8) + 面心
			{"label": "c", "multiplicity": 16, "site_symmetry": ".-3m",
			"positions": [
				[0.125, 0.125, 0.125], [0.625, 0.625, 0.125], [0.625, 0.125, 0.625], [0.125, 0.625, 0.625],
				[0.375, 0.375, 0.375], [0.875, 0.875, 0.375], [0.875, 0.375, 0.875], [0.375, 0.875, 0.875],
				[0.875, 0.875, 0.875], [0.375, 0.375, 0.875], [0.375, 0.875, 0.375], [0.875, 0.375, 0.375],
				[0.625, 0.625, 0.625], [0.125, 0.125, 0.625], [0.125, 0.625, 0.125], [0.625, 0.125, 0.125]
			]},
			# 16d: (1/2,1/2,1/2)偏移
			{"label": "d", "multiplicity": 16, "site_symmetry": ".-3m",
			"positions": [
				[0.5, 0.5, 0.5], [0.0, 0.0, 0.5], [0.0, 0.5, 0.0], [0.5, 0.0, 0.0],
				[0.25, 0.25, 0.25], [0.75, 0.75, 0.25], [0.75, 0.25, 0.75], [0.25, 0.75, 0.75],
				[0.0, 0.0, 0.0], [0.5, 0.5, 0.0], [0.5, 0.0, 0.5], [0.0, 0.5, 0.5],
				[0.75, 0.75, 0.75], [0.25, 0.25, 0.75], [0.25, 0.75, 0.25], [0.75, 0.25, 0.25]
			]},
		]
	))


func get_by_number(num: int) -> SpaceGroup:
	for g in groups:
		if g.number == num:
			return g
	return null


func get_by_symbol(sym: String) -> SpaceGroup:
	for g in groups:
		if g.symbol == sym:
			return g
	return null


func get_by_crystal_system(cs: CrystalSystem) -> Array[SpaceGroup]:
	var result: Array[SpaceGroup] = []
	for g in groups:
		if g.crystal_system == cs:
			result.append(g)
	return result
