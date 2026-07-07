# ai_level_generator.py
# AI 关卡生成器 - 使用 LLM API 生成 Intuita 关卡 JSON
#
# 环境变量:
#   OPENAI_API_KEY - OpenAI API 密钥
#   GEMINI_API_KEY - Google Gemini API 密钥
#
# 用法:
#   from ai_level_generator import AILevelGenerator
#   gen = AILevelGenerator()
#   level = gen.generate("设计一个关于 ZnS 闪锌矿的关卡")
#   gen.validate_and_save(level, "data/levels/json/chapter_5_level_1.json")

import json
import os
import sys
from pathlib import Path
from typing import Optional

# 导入 prompt 定义
from ai_level_generator_prompts import SYSTEM_PROMPT, FEW_SHOT_EXAMPLES

# 导入 solver 验证
sys.path.insert(0, str(Path(__file__).parent))
from level_solver import analyze_level, parse_level_file


class AILevelGenerator:
    def __init__(self, provider: str = "openai"):
        self.provider = provider.lower()
        self.api_key = self._load_api_key()
        self.client = None
        self._init_client()

    def _load_api_key(self) -> str:
        if self.provider == "openai":
            return os.environ.get("OPENAI_API_KEY", "")
        elif self.provider == "gemini":
            return os.environ.get("GEMINI_API_KEY", "")
        return ""

    def _init_client(self) -> None:
        if not self.api_key:
            return
        if self.provider == "openai":
            try:
                import openai
                self.client = openai.OpenAI(api_key=self.api_key)
            except ImportError:
                pass
        elif self.provider == "gemini":
            try:
                import google.generativeai as genai
                genai.configure(api_key=self.api_key)
                self.client = genai.GenerativeModel("gemini-1.5-flash")
            except ImportError:
                pass

    def generate(self, prompt: str, chapter: int = 5, level: int = 1) -> dict:
        """生成单个关卡 JSON 字典。"""
        if not self.client:
            return self._fallback_generate(prompt, chapter, level)

        full_prompt = self._build_prompt(prompt, chapter, level)

        if self.provider == "openai":
            return self._generate_openai(full_prompt)
        elif self.provider == "gemini":
            return self._generate_gemini(full_prompt)
        else:
            return self._fallback_generate(prompt, chapter, level)

    def _build_prompt(self, user_prompt: str, chapter: int, level: int) -> str:
        examples_text = "\n\n".join(
            f"Example {i+1}:\n{json.dumps(ex, indent=2, ensure_ascii=False)}"
            for i, ex in enumerate(FEW_SHOT_EXAMPLES)
        )
        return (
            f"{SYSTEM_PROMPT}\n\n"
            f"{examples_text}\n\n"
            f"User Request: {user_prompt}\n"
            f"Chapter: {chapter}, Level: {level}\n\n"
            f"Generate a level JSON that follows the schema above. "
            f"Respond with ONLY the JSON object, no markdown fences."
        )

    def _generate_openai(self, prompt: str) -> dict:
        response = self.client.chat.completions.create(
            model="gpt-4o-mini",
            messages=[
                {"role": "system", "content": "You are a crystallography game level designer."},
                {"role": "user", "content": prompt},
            ],
            temperature=0.5,
            max_tokens=2048,
        )
        text = response.choices[0].message.content.strip()
        return self._parse_json(text)

    def _generate_gemini(self, prompt: str) -> dict:
        response = self.client.generate_content(prompt)
        text = response.text.strip()
        return self._parse_json(text)

    def _parse_json(self, text: str) -> dict:
        # 去除 markdown 代码块
        if text.startswith("```"):
            lines = text.splitlines()
            if lines[0].startswith("```"):
                lines = lines[1:]
            if lines[-1].startswith("```"):
                lines = lines[:-1]
            text = "\n".join(lines)
        try:
            return json.loads(text)
        except json.JSONDecodeError as e:
            return {"error": "JSON parse failed", "raw": text, "detail": str(e)}

    def _fallback_generate(self, prompt: str, chapter: int, level: int) -> dict:
        """离线 fallback: 使用模板生成一个简单关卡。"""
        return {
            "v": 1,
            "chapter": chapter,
            "level": level,
            "title": f"AI Generated Level {chapter}-{level}",
            "description": prompt,
            "domain": "crystal",
            "construction_mode": "wyckoff_fill",
            "space_group_number": 225,
            "space_group_symbol": "Fm-3m",
            "lattice_parameters": {"x": 5.0, "y": 5.0, "z": 5.0},
            "lattice_angles": {"x": 90.0, "y": 90.0, "z": 90.0},
            "elements": [
                {"symbol": "Na", "position": {"x": 0.0, "y": 0.0, "z": 0.0}, "wyckoff_label": "a", "wyckoff_multiplicity": 4},
            ],
            "goals": [
                {"type": "wyckoff_fill", "description": "Fill Na", "element": "Na", "wyckoff": "a", "required_count": 4},
                {"type": "conservation_check", "description": "守恒矩阵保持健康", "max_deviation": 0.1},
            ],
            "reward_cores": 3,
            "hint": "AI generated level.",
            "scale_label": "Å",
            "scale_range": {"x": 0.5, "y": 10.0},
            "available_tools": ["element_block", "wyckoff_snap"],
        }

    def validate(self, data: dict) -> dict:
        """验证关卡可解性。"""
        if "error" in data:
            return {"valid": False, "errors": [data["error"]], "adjusted": None}
        result = analyze_level(data)
        errors = []
        if result.get("solvable") == False:
            errors.append("Conservation check unsolvable")
        if result.get("max_deviation") != None and result.get("threshold") != None:
            if result["max_deviation"] > result["threshold"]:
                errors.append("Max deviation exceeds threshold")
        return {
            "valid": len(errors) == 0,
            "errors": errors,
            "result": result,
            "adjusted": None,
        }

    def auto_adjust(self, data: dict) -> dict:
        """自动调整不可解关卡的参数。"""
        result = self.validate(data)
        if result["valid"]:
            return data
        # 调整 max_deviation
        for g in data.get("goals", []):
            if g.get("type") == "conservation_check":
                max_dev = result["result"].get("max_deviation", 0.1)
                g["max_deviation"] = max(max_dev * 1.2, 0.15)
        return data

    def validate_and_save(self, data: dict, output_path: str) -> dict:
        """验证并保存到文件。"""
        adjusted = self.auto_adjust(data)
        result = self.validate(adjusted)
        if not result["valid"]:
            return result
        Path(output_path).parent.mkdir(parents=True, exist_ok=True)
        with open(output_path, "w", encoding="utf-8") as f:
            json.dump(adjusted, f, indent=4, ensure_ascii=False)
        result["saved_path"] = output_path
        return result


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser(description="AI Level Generator for Intuita")
    parser.add_argument("--prompt", required=True, help="Level description prompt")
    parser.add_argument("--chapter", type=int, default=5, help="Chapter number")
    parser.add_argument("--level", type=int, default=1, help="Level number")
    parser.add_argument("--output", required=True, help="Output JSON path")
    parser.add_argument("--provider", default="openai", choices=["openai", "gemini"])
    args = parser.parse_args()

    gen = AILevelGenerator(provider=args.provider)
    level_data = gen.generate(args.prompt, args.chapter, args.level)
    result = gen.validate_and_save(level_data, args.output)
    print(json.dumps(result, indent=2, ensure_ascii=False))
