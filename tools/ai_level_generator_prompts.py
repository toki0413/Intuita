# ai_level_generator_prompts.py
# AI 关卡生成器 - 系统提示词和 Few-shot 示例

SYSTEM_PROMPT = """You are an expert crystallography game level designer for Intuita, a game about building crystal structures, molecules, and devices using Wyckoff positions and conservation matrices.

You must generate level data as a JSON object that conforms to the following schema:

- v: 1 (schema version)
- chapter: integer (chapter number)
- level: integer (level number, 1-based)
- title: string (short, descriptive, Chinese or English)
- description: string (what the player should do)
- domain: string enum ["crystal", "molecular", "fluid", "device", "reaction", "topology"]
- construction_mode: string enum ["wyckoff_fill", "bond_build", "mesh_build", "path_build", "assembly", "free", "cellular_automaton"]
- space_group_number: integer (1-230, International Tables)
- space_group_symbol: string (e.g., "Fm-3m", "P6_3/mmc")
- lattice_parameters: object {x, y, z} in Angstroms
- lattice_angles: object {x, y, z} in degrees
- elements: array of objects {symbol: string, position: {x,y,z}, wyckoff_label: string, wyckoff_multiplicity: int}
- goals: array of objects {type: string, description: string, element?: string, wyckoff?: string, required_count?: int, max_deviation?: float, required_layer?: int}
- reward_cores: int (1-5)
- hint: string
- scale_label: string (e.g., "Å")
- scale_range: object {x, y}
- available_tools: array of strings

Goal types:
- wyckoff_fill: place element at Wyckoff position
- conservation_check: max_deviation is the threshold for conservation matrix health
- verification: complete verification at required_layer
- symmetry_check, bond_check, geometry_check, transport_check, etc.

Important rules:
1. The number of atoms must match the Wyckoff multiplicity.
2. Conservation_check max_deviation should be > 0.05 to allow solvable levels.
3. Use realistic lattice parameters for the material.
4. All fractional positions must be within [0, 1].
5. Include at least one conservation_check goal and one wyckoff_fill goal.
"""

FEW_SHOT_EXAMPLES = [
    {
        "v": 1,
        "chapter": 1,
        "level": 1,
        "title": "NaCl Wyckoff填充",
        "description": "在Fm-3m空间群中填充Na和Cl到正确的Wyckoff位置，构建岩盐结构",
        "domain": "crystal",
        "construction_mode": "wyckoff_fill",
        "space_group_number": 225,
        "space_group_symbol": "Fm-3m",
        "lattice_parameters": {"x": 5.64, "y": 5.64, "z": 5.64},
        "lattice_angles": {"x": 90.0, "y": 90.0, "z": 90.0},
        "elements": [
            {"symbol": "Na", "position": {"x": 0.0, "y": 0.0, "z": 0.0}, "wyckoff_label": "a", "wyckoff_multiplicity": 4},
            {"symbol": "Cl", "position": {"x": 0.5, "y": 0.5, "z": 0.5}, "wyckoff_label": "b", "wyckoff_multiplicity": 4},
        ],
        "goals": [
            {"type": "wyckoff_fill", "description": "将Na放置在4a位置", "element": "Na", "wyckoff": "a", "required_count": 4},
            {"type": "wyckoff_fill", "description": "将Cl放置在4b位置", "element": "Cl", "wyckoff": "b", "required_count": 4},
            {"type": "conservation_check", "description": "守恒矩阵保持健康状态", "max_deviation": 0.1},
        ],
        "reward_cores": 3,
        "hint": "岩盐结构中Na和Cl交替占据面心立方格位",
        "scale_label": "Å",
        "scale_range": {"x": 0.5, "y": 10.0},
        "available_tools": ["element_block", "wyckoff_snap"],
    },
    {
        "v": 1,
        "chapter": 1,
        "level": 2,
        "title": "LiFePO4骨架",
        "description": "在Pnma空间群中构建橄榄石结构，注意Fe和Li的有序占位",
        "domain": "crystal",
        "construction_mode": "wyckoff_fill",
        "space_group_number": 62,
        "space_group_symbol": "Pnma",
        "lattice_parameters": {"x": 10.33, "y": 6.01, "z": 4.69},
        "lattice_angles": {"x": 90.0, "y": 90.0, "z": 90.0},
        "elements": [
            {"symbol": "Li", "position": {"x": 0.0, "y": 0.0, "z": 0.0}, "wyckoff_label": "a", "wyckoff_multiplicity": 4},
            {"symbol": "Fe", "position": {"x": 0.5, "y": 0.0, "z": 0.5}, "wyckoff_label": "c", "wyckoff_multiplicity": 4},
            {"symbol": "P", "position": {"x": 0.25, "y": 0.25, "z": 0.25}, "wyckoff_label": "d", "wyckoff_multiplicity": 4},
            {"symbol": "O", "position": {"x": 0.1, "y": 0.0, "z": 0.2}, "wyckoff_label": "e", "wyckoff_multiplicity": 8},
        ],
        "goals": [
            {"type": "wyckoff_fill", "description": "将Li放置在4a位置", "element": "Li", "wyckoff": "a", "required_count": 4},
            {"type": "wyckoff_fill", "description": "将Fe放置在4c位置", "element": "Fe", "wyckoff": "c", "required_count": 4},
            {"type": "conservation_check", "description": "守恒矩阵保持健康状态", "max_deviation": 0.15},
        ],
        "reward_cores": 4,
        "hint": "橄榄石结构中Li占据4a，Fe占据4c，P占据4d",
        "scale_label": "Å",
        "scale_range": {"x": 0.5, "y": 12.0},
        "available_tools": ["element_block", "wyckoff_snap"],
    },
    {
        "v": 1,
        "chapter": 2,
        "level": 1,
        "title": "CaTiO3钙钛矿",
        "description": "构建立方钙钛矿结构，注意Ti的八面体配位",
        "domain": "crystal",
        "construction_mode": "wyckoff_fill",
        "space_group_number": 221,
        "space_group_symbol": "Pm-3m",
        "lattice_parameters": {"x": 3.84, "y": 3.84, "z": 3.84},
        "lattice_angles": {"x": 90.0, "y": 90.0, "z": 90.0},
        "elements": [
            {"symbol": "Ca", "position": {"x": 0.0, "y": 0.0, "z": 0.0}, "wyckoff_label": "a", "wyckoff_multiplicity": 1},
            {"symbol": "Ti", "position": {"x": 0.5, "y": 0.5, "z": 0.5}, "wyckoff_label": "b", "wyckoff_multiplicity": 1},
            {"symbol": "O", "position": {"x": 0.5, "y": 0.0, "z": 0.0}, "wyckoff_label": "d", "wyckoff_multiplicity": 3},
        ],
        "goals": [
            {"type": "wyckoff_fill", "description": "将Ca放置在1a位置", "element": "Ca", "wyckoff": "a", "required_count": 1},
            {"type": "wyckoff_fill", "description": "将Ti放置在1b位置", "element": "Ti", "wyckoff": "b", "required_count": 1},
            {"type": "conservation_check", "description": "守恒矩阵保持健康状态", "max_deviation": 0.12},
        ],
        "reward_cores": 3,
        "hint": "钙钛矿中Ca在角顶，Ti在体心，O在面心",
        "scale_label": "Å",
        "scale_range": {"x": 0.5, "y": 8.0},
        "available_tools": ["element_block", "wyckoff_snap"],
    },
]
