use godot::prelude::*;

// 可判定性分类 - 对应元数学中的经典分层
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
#[repr(i32)]
pub enum DecidabilityClass {
    Decidable = 0,
    SemiDecidable = 1,
    Undecidable = 2,
    Independent = 3,
}

impl DecidabilityClass {
    #[allow(dead_code)]
    fn from_i32(v: i32) -> Option<Self> {
        match v {
            0 => Some(Self::Decidable),
            1 => Some(Self::SemiDecidable),
            2 => Some(Self::Undecidable),
            3 => Some(Self::Independent),
            _ => None,
        }
    }
}

// 纯函数: 可判定性分析核心逻辑
pub fn classify_invariant(name: &str, expression: &str) -> DecidabilityClass {
    let n = name.to_lowercase();
    let e = expression.to_lowercase();
    let combined = format!("{} {}", n, e);

    if combined.contains("independent") || combined.contains("godel") || combined.contains("gödel")
    {
        return DecidabilityClass::Independent;
    }

    if combined.contains("halting")
        || combined.contains("termination")
        || combined.contains("topological")
        || combined.contains("homotopy")
        || combined.contains("rice")
        || combined.contains("post_correspondence")
    {
        return DecidabilityClass::Undecidable;
    }

    if combined.contains("convergence")
        || combined.contains("scf")
        || combined.contains("eigenvalue")
        || combined.contains("spectrum")
        || combined.contains("spectral")
        || combined.contains("iteration")
        || combined.contains("fixed_point")
        || combined.contains("attractor")
    {
        return DecidabilityClass::SemiDecidable;
    }

    if combined.contains("conservation")
        || combined.contains("symmetry")
        || combined.contains("group")
        || combined.contains("finite")
        || combined.contains("linear")
        || combined.contains("polynomial")
        || combined.contains("dimension")
        || combined.contains("rank")
    {
        return DecidabilityClass::Decidable;
    }

    DecidabilityClass::SemiDecidable
}

#[derive(GodotClass)]
#[class(base=RefCounted)]
pub struct DecidabilityAnalyzer {
    base: Base<RefCounted>,
}

#[godot_api]
impl IRefCounted for DecidabilityAnalyzer {
    fn init(base: Base<RefCounted>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl DecidabilityAnalyzer {
    /// 分析不变量的可判定性
    /// 基于关键词匹配 + 启发式规则，和 Python metamath.py 逻辑对齐
    #[func]
    fn analyze_invariant(&self, name: GString, expression: GString) -> i32 {
        classify_invariant(&name.to_string(), &expression.to_string()) as i32
    }

    /// 给定系统强度等级，返回对应的 Godel 不完备性命题
    /// 系统越强，Godel 句越复杂
    #[func]
    fn godel_limitation(&self, system_strength: i32) -> GString {
        match system_strength {
            0 => GString::new(), // 太弱，没有 Godel 句
            1 => GString::from("This system cannot prove its own consistency"),
            2 => GString::from("There exist true statements unprovable within this system"),
            3 => GString::from(
                "The consistency of this system implies the existence of undecidable propositions",
            ),
            4 => GString::from(
                "For any consistent formal system F capable of arithmetic, \
                 there exists a statement G(F) that is true but unprovable in F",
            ),
            _ => GString::from(
                "No consistent formal system can demonstrate its own completeness; \
                 stronger systems only produce stronger independence phenomena",
            ),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn conservation_is_decidable() {
        assert_eq!(classify_invariant("conservation", ""), DecidabilityClass::Decidable);
    }

    #[test]
    fn scf_convergence_is_semi_decidable() {
        assert_eq!(classify_invariant("scf convergence", ""), DecidabilityClass::SemiDecidable);
    }

    #[test]
    fn halting_problem_is_undecidable() {
        assert_eq!(classify_invariant("halting problem", ""), DecidabilityClass::Undecidable);
    }

    #[test]
    fn godel_independent() {
        assert_eq!(classify_invariant("godel independent", ""), DecidabilityClass::Independent);
    }

    #[test]
    fn default_is_semi_decidable() {
        assert_eq!(
            classify_invariant("something_random", "no keywords here"),
            DecidabilityClass::SemiDecidable
        );
    }
}
