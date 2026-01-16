#!/usr/bin/env python3
import os
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
DOCS_DIR = REPO_ROOT / "Docs"
REQUIRED_MODULES = [
    "CoreKit",
    "TelemetryKit",
    "QuotaKit",
    "AICore",
    "SyncKit",
    "StorageKit",
]
REQUIRED_COMMANDS = [
    "swift test",
    "xcodebuild test -project App/NobleNotesApp.xcodeproj -scheme NobleNotesApp",
]


def module_exists(name: str) -> bool:
    return (REPO_ROOT / "Sources" / name).exists()


def tests_exist(name: str) -> bool:
    tests_dir = REPO_ROOT / "Tests" / f"{name}Tests"
    if not tests_dir.exists():
        return False
    return any(path.suffix == ".swift" for path in tests_dir.iterdir())


def commands_documented() -> dict:
    doc_path = DOCS_DIR / "NextSteps.md"
    if not doc_path.exists():
        return {cmd: False for cmd in REQUIRED_COMMANDS}
    content = doc_path.read_text(encoding="utf-8")
    return {cmd: cmd in content for cmd in REQUIRED_COMMANDS}


def find_gate_todos() -> list[tuple[str, int, str]]:
    gate_tags = [f"[GATE{idx}]" for idx in range(7)]
    results: list[tuple[str, int, str]] = []
    for root, dirs, files in os.walk(REPO_ROOT):
        rel_root = Path(root).relative_to(REPO_ROOT)
        if rel_root.parts and rel_root.parts[0] in {".git", ".build", ".swiftpm"}:
            dirs[:] = []
            continue
        for filename in files:
            path = Path(root) / filename
            if path.suffix in {".swift", ".md", ".txt"}:
                try:
                    lines = path.read_text(encoding="utf-8").splitlines()
                except UnicodeDecodeError:
                    continue
                for idx, line in enumerate(lines, start=1):
                    if any(tag in line for tag in gate_tags):
                        results.append((str(path.relative_to(REPO_ROOT)), idx, line.strip()))
    return results


def format_check(item: str, ok: bool) -> str:
    mark = "✅" if ok else "❌"
    return f"- {mark} {item}"


def main() -> None:
    module_checks = [(name, module_exists(name)) for name in REQUIRED_MODULES]
    test_checks = [(name, tests_exist(name)) for name in REQUIRED_MODULES]
    command_checks = commands_documented()
    gate_todos = find_gate_todos()

    output_lines = [
        "# Release Checklist",
        "",
        "## Required Modules",
    ]
    output_lines.extend(format_check(name, ok) for name, ok in module_checks)

    output_lines.append("")
    output_lines.append("## Required Tests")
    output_lines.extend(format_check(f"{name}Tests", ok) for name, ok in test_checks)

    output_lines.append("")
    output_lines.append("## Required Commands Documented")
    for cmd, ok in command_checks.items():
        output_lines.append(format_check(f"`{cmd}`", ok))

    output_lines.append("")
    output_lines.append("## TODO Markers [GATE0]..[GATE6]")
    if gate_todos:
        for path, line_no, line in gate_todos:
            output_lines.append(f"- {path}:{line_no} {line}")
    else:
        output_lines.append("- None found")

    output_lines.append("")
    output_path = DOCS_DIR / "release_checklist.md"
    output_path.write_text("\n".join(output_lines), encoding="utf-8")


if __name__ == "__main__":
    main()
