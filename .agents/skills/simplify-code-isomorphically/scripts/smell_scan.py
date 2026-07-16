#!/usr/bin/env python3
"""Heuristic smell scanner for behavior-preserving refactor triage.

This script flags possible smells. It does not prove a refactor is safe.
Use the output as a starting point for review, not as an auto-fix list.
"""

from __future__ import annotations

import argparse
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable

DEFAULT_EXTENSIONS = {".ts", ".tsx", ".js", ".jsx", ".py"}
IGNORE_DIRS = {
    ".git",
    "node_modules",
    "dist",
    "build",
    "coverage",
    ".next",
    ".turbo",
    "__pycache__",
}

FUNCTION_PATTERNS = [
    re.compile(r"^\s*(?:export\s+)?(?:async\s+)?function\s+([A-Za-z_$][\w$]*)\s*\("),
    re.compile(r"^\s*(?:export\s+)?const\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?\([^)]*\)\s*=>"),
    re.compile(r"^\s*(?:async\s+)?def\s+([A-Za-z_][\w]*)\s*\("),
]

DECISION_PATTERN = re.compile(
    r"\b(if|elif|else\s+if|for|while|case|catch|except|switch)\b|&&|\|\||\?"
)

RETURN_PATTERN = re.compile(r"^\s*return\s+(.+?);?\s*$")
TS_LOOKUP_CHAIN_PATTERN = re.compile(
    r"\b(?:if|else\s+if)\s*\(?\s*([A-Za-z_$][\w$.]*)\s*(?:===|==)\s*['\"`][^'\"`]+['\"`]"
)
PY_LOOKUP_CHAIN_PATTERN = re.compile(
    r"\b(?:if|elif)\s+([A-Za-z_][\w.]*)\s*==\s*['\"][^'\"]+['\"]"
)


@dataclass
class Finding:
    path: Path
    line: int
    severity: str
    kind: str
    message: str

    def format(self, root: Path) -> str:
        try:
            rel = self.path.relative_to(root)
        except ValueError:
            rel = self.path
        return f"{self.severity:6} {self.kind:26} {rel}:{self.line}  {self.message}"


def iter_files(root: Path, extensions: set[str]) -> Iterable[Path]:
    if root.is_file():
        if root.suffix in extensions:
            yield root
        return

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in IGNORE_DIRS for part in path.parts):
            continue
        if path.suffix in extensions:
            yield path


def leading_indent(line: str) -> int:
    expanded = line.replace("\t", "  ")
    return len(expanded) - len(expanded.lstrip(" "))


def estimate_max_nesting(lines: list[str]) -> int:
    indents = []
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "#", "*")):
            continue
        indents.append(leading_indent(line))
    if not indents:
        return 0
    base = min(indents)
    return max(0, (max(indents) - base) // 2)


def estimate_decision_count(lines: list[str]) -> int:
    count = 0
    for line in lines:
        stripped = line.strip()
        if not stripped or stripped.startswith(("//", "#", "*")):
            continue
        count += len(DECISION_PATTERN.findall(line))
    return count


def scan_repeated_branch_outputs(path: Path, start_line: int, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    returns: Counter[str] = Counter()
    first_line: dict[str, int] = {}
    for offset, line in enumerate(lines):
        match = RETURN_PATTERN.match(line)
        if not match:
            continue
        expr = re.sub(r"\s+", " ", match.group(1).strip())
        if len(expr) < 3:
            continue
        returns[expr] += 1
        first_line.setdefault(expr, start_line + offset)

    for expr, count in returns.items():
        if count >= 3:
            findings.append(
                Finding(
                    path,
                    first_line[expr],
                    "low",
                    "repeated-branch-output",
                    f"Same return expression appears {count} times; check for safe de-repeat.",
                )
            )
    return findings


def scan_lookup_chain(path: Path, start_line: int, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    variables: defaultdict[str, list[int]] = defaultdict(list)
    pattern = PY_LOOKUP_CHAIN_PATTERN if path.suffix == ".py" else TS_LOOKUP_CHAIN_PATTERN
    for offset, line in enumerate(lines):
        match = pattern.search(line)
        if match:
            variables[match.group(1)].append(start_line + offset)

    for variable, line_numbers in variables.items():
        if len(line_numbers) >= 4:
            findings.append(
                Finding(
                    path,
                    line_numbers[0],
                    "medium",
                    "lookup-table-candidate",
                    f"{len(line_numbers)} branches compare {variable}; consider lookup table only if pure mapping.",
                )
            )
    return findings


def scan_react_prop_smells(path: Path, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    if path.suffix not in {".tsx", ".jsx"}:
        return findings

    bare_boolean_prefixes = r"(?:is|has|show|hide|allow|enable|disable|use|with)"

    for index, line in enumerate(lines, start=1):
        bare_flags = re.findall(rf"\b{bare_boolean_prefixes}[A-Z][A-Za-z0-9_]*(?=(?:\s|/|>))", line)
        bare_flags = [flag for flag in bare_flags if f"{flag}=" not in line]
        if len(set(bare_flags)) >= 2:
            findings.append(
                Finding(
                    path,
                    index,
                    "low",
                    "magic-boolean-props",
                    f"Multiple bare boolean props: {', '.join(sorted(set(bare_flags)))}.",
                )
            )

        if re.search(r"\b(isActive|isSelected|isChecked)\s*=\s*{", line):
            findings.append(
                Finding(
                    path,
                    index,
                    "low",
                    "manual-state-prop",
                    "Check whether this visual state can derive from a canonical value instead.",
                )
            )

        if "className={`" in line or "className={'" in line or "className={\"" in line:
            findings.append(
                Finding(
                    path,
                    index,
                    "low",
                    "class-merge",
                    "Dynamic className may need the project cn()/tailwind-merge helper.",
                )
            )

    component_patterns = [
        re.compile(r"function\s+[A-Z][A-Za-z0-9_]*\s*\(\s*{([^}]*)}"),
        re.compile(r"const\s+[A-Z][A-Za-z0-9_]*\s*=\s*\(\s*{([^}]*)}"),
    ]
    for index, line in enumerate(lines, start=1):
        for pattern in component_patterns:
            match = pattern.search(line)
            if not match:
                continue
            props = [
                part.strip()
                for part in match.group(1).split(",")
                if part.strip() and not part.strip().startswith("...")
            ]
            if len(props) > 8:
                findings.append(
                    Finding(
                        path,
                        index,
                        "medium",
                        "prop-explosion",
                        f"Component destructures {len(props)} props on one line; check ownership and API shape.",
                    )
                )
            break

    return findings


def scan_state_effect_smells(path: Path, text: str, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    if path.suffix not in {".ts", ".tsx", ".js", ".jsx"}:
        return findings

    for index, line in enumerate(lines, start=1):
        if re.search(r"\buseEffect\s*\(", line):
            findings.append(
                Finding(path, index, "medium", "effect-check", "Raw useEffect found; check de-effect/no-useEffect replacement patterns.")
            )
        if re.search(r"\buseState\s*\(\s*(props\.|[A-Za-z_$][\w$]*\.)", line):
            findings.append(
                Finding(path, index, "low", "mirrored-state", "useState initialized from props/object field; check for mirrored state.")
            )
        if re.search(r"\bconst\s+\[\s*(is[A-Z][\w$]*|has[A-Z][\w$]*|selected[A-Z][\w$]*|active[A-Z][\w$]*)\s*,", line):
            findings.append(
                Finding(path, index, "low", "possible-derived-state", "Boolean/selection state may be derivable from canonical value.")
            )

    effect_setter = re.compile(r"useEffect\s*\(\s*\(\)\s*=>\s*{[^}]*\bset[A-Z][\w$]*\s*\(", re.DOTALL)
    for match in effect_setter.finditer(text):
        line_no = text[: match.start()].count("\n") + 1
        findings.append(
            Finding(path, line_no, "medium", "effect-derived-state", "Effect sets state; verify this is external sync, not derived state/action relay.")
        )

    return findings


def scan_selector_smells(path: Path, text: str, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    if path.suffix not in {".ts", ".tsx", ".js", ".jsx"}:
        return findings

    for index, line in enumerate(lines, start=1):
        if re.search(r"\buse(App)?Selector\s*\([^)]*=>", line) and re.search(r"\.(map|filter|sort|reduce)\s*\(", line):
            findings.append(
                Finding(path, index, "medium", "inline-selector-derivation", "Inline useSelector derivation; check for owner selector.")
            )
        if re.search(r"\buse(App)?Selector\s*\([^)]*=>\s*\({", line):
            findings.append(
                Finding(path, index, "low", "fresh-selector-object", "Selector may return a fresh object; check reference stability.")
            )
        if re.search(r"createSelector\s*\(\s*\[\s*\([^)]*\)\s*=>[^\]]*\.(map|filter|sort|reduce)\s*\(", line):
            findings.append(
                Finding(path, index, "medium", "selector-input-work", "Reselect input selector appears to calculate; move work to result function if true.")
            )

    for match in re.finditer(r"use(App)?Selector\s*\([^)]*=>[^)]*\.(map|filter|sort|reduce)\s*\(", text, re.DOTALL):
        line_no = text[: match.start()].count("\n") + 1
        findings.append(
            Finding(path, line_no, "medium", "inline-selector-derivation", "Multi-line selector derivation; check memoization and owner layer.")
        )
    return findings


def scan_layer_smells(path: Path, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    is_component = path.suffix in {".tsx", ".jsx"}
    infra_pattern = re.compile(r"\b(db\.execute|db\.write|fetch\(|axios\.|supabase\.|PowerSync|SQLite|localStorage\.|sessionStorage\.)")
    for index, line in enumerate(lines, start=1):
        if is_component and infra_pattern.search(line):
            findings.append(
                Finding(path, index, "high", "ui-infrastructure-leak", "UI component appears to access persistence/API/infrastructure directly.")
            )
        if re.search(r"from ['\"].*(components|\.tsx)['\"]", line) and re.search(r"(domain|selector|service|policy|gateway|command)", str(path)):
            findings.append(
                Finding(path, index, "medium", "domain-imports-ui", "Lower layer may import UI; check dependency direction.")
            )
        if "expandRRule" in line or "rrulestr" in line:
            findings.append(
                Finding(path, index, "high", "calendar-engine-boundary", "Recurrence expansion found; verify this belongs in calendar engine/worker.")
            )
    return findings


def scan_type_smells(path: Path, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    if path.suffix not in {".ts", ".tsx"}:
        return findings
    for index, line in enumerate(lines, start=1):
        if " as any" in line or re.search(r"[:<,]\s*any\b", line):
            findings.append(Finding(path, index, "low", "loose-type", "Review whether any hides a real contract."))
        if re.search(r"Record\s*<\s*string\s*,\s*(any|unknown|string)\s*>", line):
            findings.append(Finding(path, index, "low", "string-record", "Broad Record type may hide a clearer domain contract."))
        if re.search(r"\b(variant|status|type|kind|intent|size)\??\s*:\s*string\b", line):
            findings.append(Finding(path, index, "medium", "stringly-contract", "Finite domain value typed as string; consider union/shared type if stable."))
        if re.search(r"\bas\s+[A-Z][A-Za-z0-9_]*(Payload|Dto|DTO|Response|Entity)", line):
            findings.append(Finding(path, index, "low", "boundary-cast", "Boundary cast may need runtime validation or existing schema parser."))
    return findings


def scan_render_smells(path: Path, lines: list[str]) -> list[Finding]:
    findings: list[Finding] = []
    if path.suffix not in {".tsx", ".jsx"}:
        return findings
    for index, line in enumerate(lines, start=1):
        if ".Provider" in line and "value={{" in line:
            findings.append(Finding(path, index, "medium", "unstable-context-value", "Provider value object created inline; check de-render."))
        if re.search(r"\w+=\{\{[^}]+\}\}", line):
            findings.append(Finding(path, index, "low", "inline-object-prop", "Inline object prop may destabilize memoized child if crossing boundary."))
        if re.search(r"\w+=\{\[[^\]]+\]\}", line):
            findings.append(Finding(path, index, "low", "inline-array-prop", "Inline array prop may destabilize memoized child if crossing boundary."))
        if re.search(r"\w+=\{\s*\(.*\)\s*=>", line):
            findings.append(Finding(path, index, "low", "inline-callback-prop", "Inline callback prop may be fine; check only for heavy/memoized/list boundaries."))
        if re.search(r"useMemo\s*\(\s*\(\)\s*=>\s*[A-Za-z_$][\w$.]*(?:\??\.|\.)(trim|toString|toLowerCase|toUpperCase)\s*\(", line):
            findings.append(Finding(path, index, "low", "memo-overuse", "Tiny derivation memoized; check if reference boundary really needs it."))
    return findings


def scan_file(path: Path) -> list[Finding]:
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        text = path.read_text(encoding="utf-8", errors="ignore")
    lines = text.splitlines()
    findings: list[Finding] = []

    if len(lines) > 300:
        findings.append(Finding(path, 1, "medium", "large-file", f"{len(lines)} lines; check for mixed responsibilities."))

    current_name = None
    current_start = 0
    current_lines: list[str] = []

    def flush_function() -> None:
        nonlocal current_name, current_start, current_lines
        if not current_name:
            return
        length = len(current_lines)
        nesting = estimate_max_nesting(current_lines)
        decision_count = estimate_decision_count(current_lines)
        if length > 30:
            findings.append(Finding(path, current_start, "medium", "long-function", f"{current_name} is about {length} lines."))
        if nesting > 2:
            findings.append(Finding(path, current_start, "medium", "deep-nesting", f"{current_name} has estimated nesting depth {nesting}."))
        if decision_count > 10:
            findings.append(
                Finding(
                    path,
                    current_start,
                    "medium",
                    "cyclomatic-complexity",
                    f"{current_name} has about {decision_count} decision points; check guard clauses, lookup tables, or strategy maps.",
                )
            )
        findings.extend(scan_repeated_branch_outputs(path, current_start, current_lines))
        findings.extend(scan_lookup_chain(path, current_start, current_lines))
        current_name = None
        current_start = 0
        current_lines = []

    for index, line in enumerate(lines, start=1):
        matched_name = None
        for pattern in FUNCTION_PATTERNS:
            match = pattern.match(line)
            if match:
                matched_name = match.group(1)
                break
        if matched_name:
            flush_function()
            current_name = matched_name
            current_start = index
            current_lines = [line]
            continue
        if current_name:
            current_lines.append(line)

    flush_function()

    broad_catches = [i for i, line in enumerate(lines, start=1) if re.search(r"catch\s*\([^)]*\)\s*{\s*$|except\s+Exception\s*:", line)]
    for line_no in broad_catches:
        findings.append(Finding(path, line_no, "low", "broad-catch", "Check this catch preserves useful failure behavior."))

    todo_lines = [i for i, line in enumerate(lines, start=1) if "TODO" in line or "FIXME" in line]
    for line_no in todo_lines[:10]:
        findings.append(Finding(path, line_no, "low", "stale-note", "TODO/FIXME should be concrete or removed."))

    findings.extend(scan_react_prop_smells(path, lines))
    findings.extend(scan_state_effect_smells(path, text, lines))
    findings.extend(scan_selector_smells(path, text, lines))
    findings.extend(scan_layer_smells(path, lines))
    findings.extend(scan_type_smells(path, lines))
    findings.extend(scan_render_smells(path, lines))

    return findings


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan files for refactor smell heuristics.")
    parser.add_argument("paths", nargs="+", help="Files or folders to scan")
    parser.add_argument("--extensions", default=",".join(sorted(DEFAULT_EXTENSIONS)), help="Comma-separated extensions")
    args = parser.parse_args()

    extensions = {
        ext.strip() if ext.strip().startswith(".") else f".{ext.strip()}"
        for ext in args.extensions.split(",")
        if ext.strip()
    }
    roots = [Path(path).resolve() for path in args.paths]
    common_root = roots[0] if len(roots) == 1 and roots[0].is_dir() else Path.cwd().resolve()

    findings: list[Finding] = []
    for root in roots:
        if not root.exists():
            print(f"WARN   missing-path                {root}")
            continue
        for file_path in iter_files(root, extensions):
            findings.extend(scan_file(file_path))

    if not findings:
        print("No heuristic smells found. This does not prove the code is clean.")
        return 0

    for finding in findings:
        print(finding.format(common_root))

    print(f"\n{len(findings)} finding(s). Treat as triage; verify behavior before refactoring.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
