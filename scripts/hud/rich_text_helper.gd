class_name RichTextHelper
extends RefCounted
# 化学公式渲染辅助 - 在RichTextLabel中正确显示下标、上标、电荷和空间群

const SUBSCRIPT_DIGITS := {
	"0": "₀", "1": "₁", "2": "₂", "3": "₃", "4": "₄",
	"5": "₅", "6": "₆", "7": "₇", "8": "₈", "9": "₉",
}

const SUPERSCRIPT_DIGITS := {
	"0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴",
	"5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹",
}

const SUPERSCRIPT_SIGNS := {
	"+": "⁺", "-": "⁻",
}

# 化学元素符号表 (常见元素)
const ELEMENT_SYMBOLS := [
	"H", "He", "Li", "Be", "B", "C", "N", "O", "F", "Ne",
	"Na", "Mg", "Al", "Si", "P", "S", "Cl", "Ar", "K", "Ca",
	"Sc", "Ti", "V", "Cr", "Mn", "Fe", "Co", "Ni", "Cu", "Zn",
	"Ga", "Ge", "As", "Se", "Br", "Kr", "Rb", "Sr", "Y", "Zr",
	"Nb", "Mo", "Tc", "Ru", "Rh", "Pd", "Ag", "Cd", "In", "Sn",
	"Sb", "Te", "I", "Xe", "Cs", "Ba", "La", "Ce", "Pr", "Nd",
	"Pm", "Sm", "Eu", "Gd", "Tb", "Dy", "Ho", "Er", "Tm", "Yb",
	"Lu", "Hf", "Ta", "W", "Re", "Os", "Ir", "Pt", "Au", "Hg",
	"Tl", "Pb", "Bi", "Po", "At", "Rn", "Fr", "Ra", "Ac", "Th",
	"Pa", "U", "Np", "Pu", "Am", "Cm", "Bk", "Cf", "Es", "Fm",
]


# 将化学公式转为BBCode格式
# 例: "LiFePO4" → "LiFePO[sub]4[/sub]"
# 例: "H2SO4" → "H[sub]2[/sub]SO[sub]4[/sub]"
static func format_chemical_formula(formula: String) -> String:
	var result := ""
	var i := 0
	var chars := formula.to_utf8_buffer()

	while i < formula.length():
		var ch := formula[i]

		# 大写字母 = 新元素开始
		if ch >= "A" and ch <= "Z":
			result += ch
			i += 1
			# 小写字母 = 元素符号续
			if i < formula.length() and formula[i] >= "a" and formula[i] <= "z":
				result += formula[i]
				i += 1
			# 后面的数字 = 下标
			if i < formula.length() and formula[i] >= "0" and formula[i] <= "9":
				var sub_num := ""
				while i < formula.length() and formula[i] >= "0" and formula[i] <= "9":
					sub_num += formula[i]
					i += 1
				result += "[sub]" + sub_num + "[/sub]"
		# 小写字母 (不在大写后面, 不太常见但保留)
		elif ch >= "a" and ch <= "z":
			result += ch
			i += 1
		# 括号
		elif ch == "(" or ch == ")" or ch == "[" or ch == "]":
			result += ch
			i += 1
			# 括号后的数字也是下标
			if i < formula.length() and formula[i] >= "0" and formula[i] <= "9":
				var sub_num := ""
				while i < formula.length() and formula[i] >= "0" and formula[i] <= "9":
					sub_num += formula[i]
					i += 1
				result += "[sub]" + sub_num + "[/sub]"
		# 数字 (不在元素后, 可能是系数)
		elif ch >= "0" and ch <= "9":
			result += ch
			i += 1
		else:
			result += ch
			i += 1

	return result


# 将同位素标记转为BBCode
# 例: "6Li" → "[sup]6[/sup]Li"
# 例: "235U" → "[sup]235[/sup]U"
static func format_isotope(isotope: String) -> String:
	var result := ""
	var i := 0

	# 开头的数字 = 质量数 (上标)
	if i < isotope.length() and isotope[i] >= "0" and isotope[i] <= "9":
		var mass_num := ""
		while i < isotope.length() and isotope[i] >= "0" and isotope[i] <= "9":
			mass_num += isotope[i]
			i += 1
		result += "[sup]" + mass_num + "[/sup]"

	# 剩余部分作为化学公式处理
	result += format_chemical_formula(isotope.substr(i))
	return result


# 将电荷标记转为BBCode
# 例: "Fe3+" → "Fe[sup]3+[/sup]"
# 例: "SO4 2-" → "SO[sub]4[/sub][sup]2-[/sup]"
# 例: "O2-" → "O[sup]2-[/sup]"
static func format_charge(formula: String) -> String:
	# 先处理化学公式部分
	var charge_part := ""
	var chem_part := formula
	var plus_idx := formula.find_last("+")
	var minus_idx := formula.find_last("-")

	# 找到电荷符号位置
	var charge_pos := -1
	if plus_idx >= 0 and minus_idx >= 0:
		charge_pos = maxi(plus_idx, minus_idx)
	elif plus_idx >= 0:
		charge_pos = plus_idx
	elif minus_idx >= 0:
		charge_pos = minus_idx

	if charge_pos >= 0:
		# 提取电荷: 符号前的数字 + 符号
		var j := charge_pos
		var charge_num := ""
		# 往前找数字
		var k := j - 1
		while k >= 0 and formula[k] >= "0" and formula[k] <= "9":
			charge_num = formula[k] + charge_num
			k -= 1

		if charge_num == "":
			charge_num = "1"  # 单电荷

		var sign := formula[j]
		charge_part = "[sup]" + charge_num + sign + "[/sup]"
		chem_part = formula.substr(0, k + 1)

	return format_chemical_formula(chem_part) + charge_part


# 空间群标记格式化
# 例: "Fm-3m" → "Fm3̄m" (3上面加横线)
# 例: "P-1" → "P1̄"
static func format_space_group(sg: String) -> String:
	var result := ""
	var i := 0

	while i < sg.length():
		var ch := sg[i]
		# 负号后面跟数字 = 上面加横线 (macron)
		if ch == "-" and i + 1 < sg.length():
			var next_ch := sg[i + 1]
			if next_ch >= "0" and next_ch <= "9":
				# 用组合macron字符
				result += _add_macron(next_ch)
				i += 2
				continue
		result += ch
		i += 1

	return result


# 给数字加macron (上横线)
static func _add_macron(ch: String) -> String:
	# Unicode组合macron: U+0304
	return ch + "\u0304"


# 生成完整的BBCode文本, 带字体设置
# base_font_size: 基础字号 (sub/sup为60%)
static func make_bbcode(text: String, base_font_size: int = 20) -> String:
	var sub_size := int(base_font_size * 0.6)
	return (
		"[font_size=%d]" % base_font_size +
		text +
		"[/font_size]"
	)


# 便捷方法: 格式化化学公式并生成完整BBCode
static func render_formula(formula: String, base_font_size: int = 20) -> String:
	var formatted := format_chemical_formula(formula)
	return make_bbcode(formatted, base_font_size)


# 便捷方法: 格式化同位素并生成完整BBCode
static func render_isotope(isotope: String, base_font_size: int = 20) -> String:
	var formatted := format_isotope(isotope)
	return make_bbcode(formatted, base_font_size)


# 便捷方法: 格式化带电荷的化学式
static func render_charged(formula: String, base_font_size: int = 20) -> String:
	var formatted := format_charge(formula)
	return make_bbcode(formatted, base_font_size)


# 便捷方法: 格式化空间群
static func render_space_group(sg: String, base_font_size: int = 20) -> String:
	var formatted := format_space_group(sg)
	return make_bbcode(formatted, base_font_size)


# 将Unicode下标数字转回普通数字
static func subscript_to_normal(text: String) -> String:
	var result := text
	for sub in SUBSCRIPT_DIGITS:
		result = result.replace(SUBSCRIPT_DIGITS[sub], sub)
	return result


# 将Unicode上标数字转回普通数字
static func superscript_to_normal(text: String) -> String:
	var result := text
	for sup in SUPERSCRIPT_DIGITS:
		result = result.replace(SUPERSCRIPT_DIGITS[sup], sup)
	for sign in SUPERSCRIPT_SIGNS:
		result = result.replace(SUPERSCRIPT_SIGNS[sign], sign)
	return result
