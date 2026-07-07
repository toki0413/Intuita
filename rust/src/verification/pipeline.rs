use godot::prelude::*;
use std::collections::HashMap;

type Dict = Dictionary<Variant, Variant>;

// 验证层枚举 - 从简单到严格
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum VerificationLayer {
    Symbolic = 0,
    TypeSystem = 1,
    Logic = 2,
    LlmSemantic = 3,
    Formal = 4,
}

impl VerificationLayer {
    fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Symbolic),
            1 => Some(Self::TypeSystem),
            2 => Some(Self::Logic),
            3 => Some(Self::LlmSemantic),
            4 => Some(Self::Formal),
            _ => None,
        }
    }

    #[allow(dead_code)]
    fn confidence(&self) -> f64 {
        match self {
            Self::Symbolic => 0.3,
            Self::TypeSystem => 0.5,
            Self::Logic => 0.7,
            Self::LlmSemantic => 0.85,
            Self::Formal => 0.95,
        }
    }

    pub fn core_cost(&self) -> i32 {
        match self {
            Self::Symbolic => 0,
            Self::TypeSystem => 0,
            Self::Logic => 1,
            Self::LlmSemantic => 2,
            Self::Formal => 5,
        }
    }
}

pub struct LayerResult {
    pub layer: i32,
    pub passed: bool,
    pub message: String,
    pub confidence: f64,
}

impl LayerResult {
    fn to_dict(&self) -> Dict {
        let mut dict = Dict::new();
        dict.set("layer", self.layer);
        dict.set("passed", self.passed);
        dict.set("message", &GString::from(self.message.as_str()));
        dict.set("confidence", self.confidence);
        dict
    }
}

// 纯函数: L0 符号验证
pub fn verify_symbolic(stmt: &str, _ctx: &HashMap<String, String>) -> LayerResult {
    let mut passed = true;
    let mut msg = String::from("Symbolic check passed");

    if stmt.trim().is_empty() {
        passed = false;
        msg = "Empty statement".into();
    }

    if stmt.contains("x") {
        let parts: Vec<&str> = stmt.split('x').collect();
        if parts.len() == 2 {
            if let (Ok(a), Ok(b)) = (parts[0].trim().parse::<i32>(), parts[1].trim().parse::<i32>())
            {
                if a <= 0 || b <= 0 || a > 100 || b > 100 {
                    passed = false;
                    msg = format!("Invalid dimensions: {}x{}", a, b);
                }
            }
        }
    }

    if stmt.contains("inf") || stmt.contains("nan") {
        passed = false;
        msg = "Statement contains invalid numeric values".into();
    }

    LayerResult {
        layer: VerificationLayer::Symbolic as i32,
        passed,
        message: msg,
        confidence: if passed { 0.3 } else { 0.0 },
    }
}

// 纯函数: L1 类型系统检查
pub fn verify_type_system(stmt: &str, _ctx: &HashMap<String, String>) -> LayerResult {
    let mut passed = true;
    let mut msg = String::from("Type system check passed");

    if stmt.contains("TYPE_ERROR") || stmt.contains("type_mismatch") {
        passed = false;
        msg = "Type mismatch detected".into();
    }

    let open_count = stmt.chars().filter(|&c| c == '(').count();
    let close_count = stmt.chars().filter(|&c| c == ')').count();
    if open_count != close_count {
        passed = false;
        msg = "Unbalanced parentheses - possible type application error".into();
    }

    if (stmt.contains("Pi(") || stmt.contains("Sigma("))
        && !stmt.contains(':')
        && !stmt.contains("->")
    {
        passed = false;
        msg = "Dependent type annotation incomplete".into();
    }

    LayerResult {
        layer: VerificationLayer::TypeSystem as i32,
        passed,
        message: msg,
        confidence: if passed { 0.5 } else { 0.1 },
    }
}

// 纯函数: L2 逻辑推理
pub fn verify_logic(stmt: &str, ctx: &HashMap<String, String>) -> LayerResult {
    let mut passed = true;
    let mut msg = String::from("Logic check passed");

    if let Some(premises_str) = ctx.get("premises") {
        let premises: Vec<&str> = premises_str.split(';').collect();
        for i in 0..premises.len() {
            for j in (i + 1)..premises.len() {
                let pi = premises[i].trim();
                let pj = premises[j].trim();
                if format!("NOT {}", pi) == pj || format!("NOT {}", pj) == pi {
                    passed = false;
                    msg = format!("Contradiction found: {} vs {}", pi, pj);
                }
                if format!("¬{}", pi) == pj || format!("¬{}", pj) == pi {
                    passed = false;
                    msg = format!("Contradiction found: {} vs {}", pi, pj);
                }
            }
        }
    }

    let has_implies = stmt.contains("=>") || stmt.contains("→") || stmt.contains("implies");
    let has_conclusion =
        stmt.contains("therefore") || stmt.contains("所以") || stmt.contains("thus");
    if has_implies && !has_conclusion && stmt.len() < 10 {
        passed = false;
        msg = "Implication without conclusion".into();
    }

    LayerResult {
        layer: VerificationLayer::Logic as i32,
        passed,
        message: msg,
        confidence: if passed { 0.7 } else { 0.2 },
    }
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct VerificationPipeline {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for VerificationPipeline {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl VerificationPipeline {
    /// 获取指定层的核心消耗
    #[func]
    fn get_core_cost(&self, layer: i32) -> i32 {
        VerificationLayer::from_i32(layer).map(|l| l.core_cost()).unwrap_or(0)
    }

    /// 执行验证 - 逐层检查语句
    #[func]
    fn verify(&self, layer: i32, statement: GString, context: Dict) -> Dict {
        let vl = match VerificationLayer::from_i32(layer) {
            Some(l) => l,
            None => {
                let result = LayerResult {
                    layer,
                    passed: false,
                    message: "Unknown verification layer".into(),
                    confidence: 0.0,
                };
                return result.to_dict();
            }
        };

        let stmt = statement.to_string();
        let ctx = Self::dict_to_hashmap(&context);

        let result = match vl {
            VerificationLayer::Symbolic => verify_symbolic(&stmt, &ctx),
            VerificationLayer::TypeSystem => verify_type_system(&stmt, &ctx),
            VerificationLayer::Logic => verify_logic(&stmt, &ctx),
            VerificationLayer::LlmSemantic => Self::verify_llm(&stmt, &ctx),
            VerificationLayer::Formal => Self::verify_formal(&stmt, &ctx),
        };

        result.to_dict()
    }

    /// Z3 形式化约束验证（占位 - 需要 z3 crate 编译环境）
    /// 当前通过 GDScript 命令行调用 z3 实现
    #[func]
    fn verify_conservation_z3(&self, matrix: PackedFloat64Array) -> Dict {
        // 占位：当 z3 crate 可用时，这里会直接调用 Z3 Rust API
        // 当前 GDScript 端通过命令行 z3 -smt2 实现
        let mut dict = Dict::new();
        dict.set("success", false);
        dict.set("confidence", 0.0);
        dict.set("reason", &GString::from("z3_rust_not_available_use_gdscript_fallback"));
        dict.set("matrix_size", matrix.len() as i32);
        dict
    }
}

impl VerificationPipeline {
    fn dict_to_hashmap(dict: &Dict) -> HashMap<String, String> {
        let mut map = HashMap::new();
        for (key_var, val_var) in dict.iter_shared() {
            let key_str = key_var.to_string();
            let val_str = val_var.to_string();
            map.insert(key_str, val_str);
        }
        map
    }

    /// L3: LLM 语义验证 - 占位，后续接入 LLM
    fn verify_llm(stmt: &str, _ctx: &HashMap<String, String>) -> LayerResult {
        let mut score = 0.7f64;

        if stmt.len() > 20 {
            score += 0.05;
        }
        if stmt.len() > 50 {
            score += 0.05;
        }
        if stmt.contains("therefore") || stmt.contains("所以") || stmt.contains("thus") {
            score += 0.1;
        }
        if stmt.contains("proof") || stmt.contains("证明") {
            score += 0.05;
        }
        score = score.min(1.0);

        let passed = score > 0.6;

        LayerResult {
            layer: VerificationLayer::LlmSemantic as i32,
            passed,
            message: if passed {
                "LLM semantic verification passed (placeholder)".into()
            } else {
                "LLM semantic verification failed (placeholder)".into()
            },
            confidence: score,
        }
    }

    /// L5: 形式化约束验证 - GDScript 端通过 Z3 命令行实现
    fn verify_formal(stmt: &str, _ctx: &HashMap<String, String>) -> LayerResult {
        LayerResult {
            layer: VerificationLayer::Formal as i32,
            passed: !stmt.trim().is_empty(),
            message: "Formal verification deferred to GDScript Z3 implementation".into(),
            confidence: 0.5,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn symbolic_empty_statement_fails() {
        let ctx = HashMap::new();
        let result = verify_symbolic("", &ctx);
        assert!(!result.passed);
        assert_eq!(result.confidence, 0.0);
    }

    #[test]
    fn symbolic_valid_statement_passes() {
        let ctx = HashMap::new();
        let result = verify_symbolic("structure_integrity", &ctx);
        assert!(result.passed);
        assert_eq!(result.confidence, 0.3);
    }

    #[test]
    fn type_system_unbalanced_parens_fails() {
        let ctx = HashMap::new();
        let result = verify_type_system("f(x", &ctx);
        assert!(!result.passed);
    }

    #[test]
    fn type_system_valid_expression_passes() {
        let ctx = HashMap::new();
        let result = verify_type_system("f(x)", &ctx);
        assert!(result.passed);
    }

    #[test]
    fn logic_contradiction_detected() {
        let mut ctx = HashMap::new();
        ctx.insert("premises".to_string(), "P;NOT P".to_string());
        let result = verify_logic("P implies Q", &ctx);
        assert!(!result.passed);
        assert!(result.message.contains("Contradiction"));
    }

    #[test]
    fn core_costs() {
        assert_eq!(VerificationLayer::Symbolic.core_cost(), 0);
        assert_eq!(VerificationLayer::TypeSystem.core_cost(), 0);
        assert_eq!(VerificationLayer::Logic.core_cost(), 1);
        assert_eq!(VerificationLayer::LlmSemantic.core_cost(), 2);
        assert_eq!(VerificationLayer::Formal.core_cost(), 5);
    }
}
