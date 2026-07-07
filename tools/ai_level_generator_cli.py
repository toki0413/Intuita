#!/usr/bin/env python3
"""
AI Level Generator CLI - 命令行入口

用法:
    python tools/ai_level_generator_cli.py --prompt "ZnS 闪锌矿" --output data/levels/json/chapter_5_level_1.json
    python tools/ai_level_generator_cli.py --prompt "设计一个石墨烯的分子结构关卡" --provider gemini --chapter 3 --level 5 --output data/levels/json/chapter_3_level_5.json
"""

import sys
from pathlib import Path

# Add tools directory to path
sys.path.insert(0, str(Path(__file__).parent))

from ai_level_generator import AILevelGenerator
from ai_level_generator_prompts import SYSTEM_PROMPT, FEW_SHOT_EXAMPLES


def main():
    import argparse
    parser = argparse.ArgumentParser(
        description="AI Level Generator for Intuita",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  %(prog)s --prompt "ZnS 闪锌矿" --output data/levels/json/chapter_5_level_1.json
  %(prog)s --prompt "石墨烯分子结构" --provider gemini --chapter 3 --level 5 --output data/levels/json/chapter_3_level_5.json
  %(prog)s --prompt "全固态电池 Li+ 扩散" --chapter 4 --level 1 --output data/levels/json/chapter_4_level_1.json
        """
    )
    parser.add_argument("--prompt", required=True, help="Level description prompt (Chinese or English)")
    parser.add_argument("--chapter", type=int, default=5, help="Chapter number (default: 5)")
    parser.add_argument("--level", type=int, default=1, help="Level number (default: 1)")
    parser.add_argument("--output", required=True, help="Output JSON file path")
    parser.add_argument("--provider", default="openai", choices=["openai", "gemini"],
                        help="LLM provider (default: openai)")
    parser.add_argument("--validate-only", action="store_true",
                        help="Skip generation, only validate an existing JSON file")
    parser.add_argument("--show-prompt", action="store_true",
                        help="Print the system prompt and exit")

    args = parser.parse_args()

    if args.show_prompt:
        print("=== SYSTEM PROMPT ===")
        print(SYSTEM_PROMPT)
        print("\n=== FEW-SHOT EXAMPLES ===")
        import json
        for i, ex in enumerate(FEW_SHOT_EXAMPLES):
            print(f"\nExample {i+1}:")
            print(json.dumps(ex, indent=2, ensure_ascii=False))
        return

    gen = AILevelGenerator(provider=args.provider)

    if args.validate_only:
        import json
        with open(args.output, "r", encoding="utf-8") as f:
            data = json.load(f)
        result = gen.validate(data)
        print(result)
        return

    print(f"Generating level for chapter {args.chapter}, level {args.level}...")
    print(f"Prompt: {args.prompt}")
    print(f"Provider: {args.provider}")

    level_data = gen.generate(args.prompt, args.chapter, args.level)

    if "error" in level_data:
        print(f"Generation failed: {level_data['error']}")
        print(f"Raw output: {level_data.get('raw', '')}")
        sys.exit(1)

    result = gen.validate_and_save(level_data, args.output)

    import json
    print(json.dumps(result, indent=2, ensure_ascii=False))

    if result.get("valid"):
        print(f"\n✅ Level saved to {args.output}")
    else:
        print(f"\n❌ Validation failed: {result.get('errors', [])}")
        sys.exit(1)


if __name__ == "__main__":
    main()
