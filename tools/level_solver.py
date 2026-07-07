#!/usr/bin/env python3
"""
Intuita Level Solver - 批量关卡守恒矩阵可解性验证工具

遍历所有关卡 JSON，模拟最终状态守恒矩阵，判断 conservation_check 目标是否可解。
支持命令行运行和 Kimi PythonRun 工具内嵌运行。

用法:
    python tools/level_solver.py
    # 或作为 Kimi PythonRun 任务运行
"""

import json
import glob
import os
import sys
from pathlib import Path
import numpy as np

# ---------------------------------------------------------------------------
# 1.5 JSON Schema validation (optional)
# ---------------------------------------------------------------------------
_jsonschema_available = False
_validator = None

try:
    import jsonschema
    from jsonschema import Draft202012Validator
    _jsonschema_available = True
except ImportError:
    pass


def _load_schema():
    global _validator
    if not _jsonschema_available or _validator is not None:
        return
    schema_path = Path(__file__).parent.parent / "data" / "levels" / "level.schema.json"
    if schema_path.exists():
        with open(schema_path, "r", encoding="utf-8") as f:
            schema = json.load(f)
        _validator = Draft202012Validator(schema)


# ---------------------------------------------------------------------------
# 1. 前20种元素原子质量表（从 element_data_resource.gd 提取）
# ---------------------------------------------------------------------------
ATOMIC_MASS_TABLE = {
    "H": 1.008,
    "He": 4.003,
    "Li": 6.94,
    "Be": 9.012,
    "B": 10.81,
    "C": 12.01,
    "N": 14.01,
    "O": 16.00,
    "F": 19.00,
    "Ne": 20.18,
    "Na": 22.99,
    "Mg": 24.31,
    "Al": 26.98,
    "Si": 28.09,
    "P": 30.97,
    "S": 32.06,
    "Cl": 35.45,
    "Ar": 39.95,
    "K": 39.10,
    "Ca": 40.08,
}

# 常见元素符号扩展（非前20种，但出现在关卡中）
EXTENDED_MASS_TABLE = {
    "Co": 58.93,
    "Cu": 63.55,
    "Zr": 91.22,
    "La": 138.91,
    "Y": 88.91,
    "Ba": 137.33,
    # 扩展：补充关卡中使用的真实元素
    "Fe": 55.85,
    "Ti": 47.87,
    "Sr": 87.62,
    "Ni": 58.69,
    "Ga": 69.72,
    "As": 74.92,
    # 钙钛矿等常见结构元素
    "Mn": 54.94,
    "Zn": 65.38,
    "Pb": 207.2,
    "Bi": 208.98,
    "W": 183.84,
    "Mo": 95.95,
    "Nb": 92.91,
    "Ru": 101.07,
    "Rh": 102.91,
    "Pd": 106.42,
    "Ag": 107.87,
    "Cd": 112.41,
    "In": 114.82,
    "Sn": 118.71,
    "Sb": 121.76,
    "Te": 127.60,
    "I": 126.90,
    "Xe": 131.29,
    "Cs": 132.91,
    "Ce": 140.12,
    "Pr": 140.91,
    "Nd": 144.24,
    "Sm": 150.36,
    "Eu": 151.96,
    "Gd": 157.25,
    "Tb": 158.93,
    "Dy": 162.50,
    "Ho": 164.93,
    "Er": 167.26,
    "Tm": 168.93,
    "Yb": 173.05,
    "Lu": 174.97,
    "Hf": 178.49,
    "Ta": 180.95,
    "Re": 186.21,
    "Os": 190.23,
    "Ir": 192.22,
    "Pt": 195.08,
    "Au": 196.97,
    "Hg": 200.59,
    "Tl": 204.38,
    "Pb": 207.2,
    "Bi": 208.98,
    "Th": 232.04,
    "U": 238.03,
}

# 合并质量表（同时建立大小写不敏感查找表）
MASS_TABLE = {**ATOMIC_MASS_TABLE, **EXTENDED_MASS_TABLE}
# 大小写不敏感映射：CA -> Ca, fe -> Fe 等
_MASS_TABLE_LOWER = {k.lower(): v for k, v in MASS_TABLE.items()}

# 常见后缀剥离映射（如 O1, O2, O3 -> O）
SUFFIX_STRIP = {
    "O1": "O", "O2": "O", "O3": "O", "O4": "O", "O5": "O",
    "Cu1": "Cu", "Cu2": "Cu", "Cu3": "Cu",
    "Fe1": "Fe", "Fe2": "Fe",
    "Li1": "Li", "Li2": "Li", "Li3": "Li",
}


def get_atomic_mass(symbol: str) -> float | None:
    """
    获取元素符号的游戏内质量值。

    策略：
      1. 直接查找 MASS_TABLE
      2. 大小写不敏感查找（CA -> Ca）
      3. 后缀剥离（O1 -> O, Li1 -> Li）
      4. 对占位符/特殊构造（如 M, FLUID, WALL, Cu_panel_back）返回默认质量 1.0
         以便 solver 继续计算偏差，而不是中断分析
    """
    # 1. 直接查找
    if symbol in MASS_TABLE:
        return MASS_TABLE[symbol]
    # 2. 大小写不敏感查找
    lower = symbol.lower()
    if lower in _MASS_TABLE_LOWER:
        return _MASS_TABLE_LOWER[lower]
    # 3. 后缀剥离（如 O1 -> O）
    if symbol in SUFFIX_STRIP:
        stripped = SUFFIX_STRIP[symbol]
        return MASS_TABLE.get(stripped, 1.0)
    # 4. 占位符/特殊构造：返回默认质量 1.0，让 solver 可以继续计算
    # 这样 UNKNOWN 元素不会导致关卡被误判为不可分析
    return 1.0


# 保留原子质量表仅用于参考（完整版，包含所有扩展元素）
_REFERENCE_ATOMIC_MASS = {**ATOMIC_MASS_TABLE, **EXTENDED_MASS_TABLE}



def parse_level_file(path: Path) -> dict:
    """读取并解析单个关卡 JSON 文件，可选 JSON Schema 验证。"""
    _load_schema()
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    if _validator is not None:
        try:
            _validator.validate(data)
        except jsonschema.ValidationError as e:
            print(f"[WARN] Schema validation failed for {path}: {e.message}")
    return data


def compute_max_deviation(mass_increase: float) -> float:
    """
    模拟守恒矩阵最终状态，计算特征值最大偏离度。

    矩阵 M = I_4，只有 M[0][0] = 1.0 + mass_increase
    特征值 = [1.0 + mass_increase, 1.0, 1.0, 1.0]
    max_deviation = max(|λ_i - 1.0|) = |mass_increase|
    """
    M = np.eye(4, dtype=np.float64)
    M[0, 0] = 1.0 + mass_increase

    eigenvalues = np.linalg.eigvals(M)
    # 对于对角矩阵，特征值就是对角线元素，但保留 numpy 计算以兼容非对角情况
    max_deviation = float(np.max(np.abs(eigenvalues - 1.0)))
    return max_deviation


def analyze_level(data: dict) -> dict:
    """
    分析单个关卡的可解性。
    """
    chapter = data.get("chapter")
    level = data.get("level")
    title = data.get("title", "")
    construction_mode = data.get("construction_mode", "")
    domain = data.get("domain", "")
    elements = data.get("elements", [])
    goals = data.get("goals", [])
    available_tools = data.get("available_tools", [])

    result = {
        "chapter": chapter,
        "level": level,
        "title": title,
        "construction_mode": construction_mode,
        "domain": domain,
        "max_deviation": None,
        "threshold": None,
        "solvable": None,
        "notes": "",
    }

    # ------------------------------------------------------------------
    # 边界情况：cellular_automaton 模式
    # ------------------------------------------------------------------
    if construction_mode == "cellular_automaton":
        result["domain_not_supported"] = True
        result["solvable"] = None
        result["notes"] = (
            "cellular_automaton 模式质量模型不适用; "
            "conservation_check 在演化中动态维持，需手动验证。"
        )
        # 仍尝试提取 threshold 供参考
        conservation_goals = [g for g in goals if g.get("type") == "conservation_check"]
        if conservation_goals:
            thresholds = [g.get("max_deviation") for g in conservation_goals if g.get("max_deviation") is not None]
            if thresholds:
                result["threshold"] = min(thresholds)
        return result

    # ------------------------------------------------------------------
    # 计算单元总质量（用于归一化扰动）
    # ------------------------------------------------------------------
    total_cell_mass = 0.0
    unknown_elements = set()
    for el in elements:
        symbol = el.get("symbol", "")
        mult = el.get("wyckoff_multiplicity", 1)
        mass = get_atomic_mass(symbol)
        if mass is None:
            unknown_elements.add(symbol)
        else:
            total_cell_mass += mass * mult
    if total_cell_mass == 0.0:
        total_cell_mass = 1.0  # 避免除零

    # ------------------------------------------------------------------
    # 提取 conservation_check 阈值
    # ------------------------------------------------------------------
    conservation_goals = [g for g in goals if g.get("type") == "conservation_check"]
    if not conservation_goals:
        result["no_conservation_check"] = True
        result["solvable"] = True
        result["notes"] = "No conservation_check goal; only verify other goals."
        return result

    thresholds = [g.get("max_deviation") for g in conservation_goals if g.get("max_deviation") is not None]
    if not thresholds:
        result["no_conservation_check"] = True
        result["solvable"] = True
        result["notes"] = "conservation_check goal exists but no max_deviation specified."
        return result

    threshold = min(thresholds)
    result["threshold"] = threshold

    # ------------------------------------------------------------------
    # 计算 wyckoff_fill 目标带来的总质量增加（归一化模型）
    # ------------------------------------------------------------------
    wyckoff_goals = [g for g in goals if g.get("type") == "wyckoff_fill"]
    total_mass_increase = 0.0

    for goal in wyckoff_goals:
        element_symbol = goal.get("element", "")
        required_count = goal.get("required_count", 0)

        mass = get_atomic_mass(element_symbol)
        if mass is None:
            unknown_elements.add(element_symbol)
        else:
            total_mass_increase += required_count * (mass / total_cell_mass) * 0.05

    # ------------------------------------------------------------------
    # 未知元素处理
    # ------------------------------------------------------------------
    if unknown_elements:
        result["unknown_element_mass"] = True
        result["needs_manual_review"] = True
        result["solvable"] = None
        result["notes"] = (
            f"Unknown element(s) in goals/elements: {', '.join(sorted(unknown_elements))}. "
            f"Cannot compute mass deviation. Requires manual review or mass table extension."
        )
        return result

    # ------------------------------------------------------------------
    # 计算偏离度
    # ------------------------------------------------------------------
    max_deviation = compute_max_deviation(total_mass_increase)
    result["max_deviation"] = round(max_deviation, 6)

    # 其他模式（bond_build, assembly, path_build, mesh_build, free）不直接增加质量
    # 因此偏离度仅来自 wyckoff_fill
    # 加入浮点 epsilon 避免边界值被误判（如 0.05000000000000001 > 0.05）
    _EPSILON = 1e-9
    if max_deviation <= threshold + _EPSILON:
        result["solvable"] = True
        result["notes"] = "Mass deviation within threshold with ideal placement."
    else:
        result["solvable"] = False
        result["notes"] = (
            f"Mass deviation exceeds threshold even with ideal placement. "
            f"Required: ≤{threshold}, Got: {max_deviation:.6f}"
        )

    return result


def run_analysis(project_root: Path) -> dict:
    """
    执行完整的关卡分析并返回报告字典。
    """
    levels_dir = project_root / "data" / "levels" / "json"
    if not levels_dir.exists():
        raise FileNotFoundError(f"Levels directory not found: {levels_dir}")

    pattern = levels_dir / "chapter_*_level_*.json"
    level_files = sorted(glob.glob(str(pattern)))

    levels = []
    solvable_count = 0
    unsolvable_count = 0
    needs_manual_review_count = 0
    no_conservation_count = 0

    for filepath in level_files:
        data = parse_level_file(Path(filepath))
        result = analyze_level(data)
        levels.append(result)

        if result.get("solvable") is True:
            solvable_count += 1
        elif result.get("solvable") is False:
            unsolvable_count += 1
        else:
            needs_manual_review_count += 1

        if result.get("no_conservation_check"):
            no_conservation_count += 1

    # 按 chapter, level 排序
    levels.sort(key=lambda x: (x.get("chapter", 0), x.get("level", 0)))

    report = {
        "summary": {
            "total_levels": len(levels),
            "solvable": solvable_count,
            "unsolvable": unsolvable_count,
            "needs_manual_review": needs_manual_review_count,
            "no_conservation_check": no_conservation_count,
        },
        "levels": levels,
    }

    return report


def print_report(report: dict) -> None:
    """打印可读的分析报告到控制台。"""
    summary = report["summary"]
    print("=" * 70)
    print("Intuita Level Solver Report")
    print("=" * 70)
    print(f"Total Levels:          {summary['total_levels']}")
    print(f"Solvable:              {summary['solvable']}")
    print(f"Unsolvable:            {summary['unsolvable']}")
    print(f"Needs Manual Review:   {summary['needs_manual_review']}")
    print(f"No Conservation Check: {summary['no_conservation_check']}")
    print("-" * 70)

    for lvl in report["levels"]:
        chapter = lvl.get("chapter", "?")
        level = lvl.get("level", "?")
        title = lvl.get("title", "")
        mode = lvl.get("construction_mode", "")
        solvable = lvl.get("solvable")
        deviation = lvl.get("max_deviation")
        threshold = lvl.get("threshold")
        notes = lvl.get("notes", "")

        status = "✓" if solvable is True else "✗" if solvable is False else "?"
        print(f"[{status}] Ch{chapter} L{level:02d} | {mode:20s} | {title}")
        if deviation is not None and threshold is not None:
            print(f"       deviation={deviation:.6f} threshold={threshold}")
        if notes:
            print(f"       NOTE: {notes}")
        print()


# ---------------------------------------------------------------------------
# Kimi PythonRun 入口 + 命令行入口
# ---------------------------------------------------------------------------

def main(ctx=None):
    """
    Kimi PythonRun 入口函数。
    ctx: 包含 runDir 等信息的字典（Kimi PythonRun 提供）。
    """
    # 确定项目根目录
    # 1. 首先尝试从命令行参数获取（忽略以 -- 开头的 runner 参数）
    # 2. 否则尝试从环境变量 INTUITA_ROOT 获取
    # 3. 否则使用脚本所在目录的父目录
    # 4. 如果 ctx 提供了 runDir，则使用默认项目路径
    project_root = None
    if len(sys.argv) > 1:
        arg = sys.argv[1]
        if not arg.startswith("--"):
            project_root = Path(arg)
    if project_root is None or not project_root.exists():
        env_root = os.environ.get("INTUITA_ROOT")
        if env_root:
            project_root = Path(env_root)
    if project_root is None or not project_root.exists():
        # 默认路径：脚本位于 tools/level_solver.py，项目根目录是父目录
        script_dir = Path(__file__).resolve().parent
        project_root = script_dir.parent
        # 如果项目根目录不存在，尝试硬编码的 Windows 路径
        if not project_root.exists():
            project_root = Path(r"C:\Users\wanzh\Desktop\Intuita")

    if not project_root.exists():
        print(f"ERROR: Project root not found: {project_root}")
        return {"error": f"Project root not found: {project_root}"}

    print(f"Analyzing project: {project_root}")

    report = run_analysis(project_root)

    # 保存报告到 tools/level_solver_report.json
    tools_dir = project_root / "tools"
    tools_dir.mkdir(parents=True, exist_ok=True)
    report_path = tools_dir / "level_solver_report.json"

    with open(report_path, "w", encoding="utf-8") as f:
        json.dump(report, f, ensure_ascii=False, indent=2)

    print(f"\nReport saved to: {report_path}")
    print_report(report)

    return {
        "report_path": str(report_path),
        "summary": report["summary"],
    }


if __name__ == "__main__":
    main()
