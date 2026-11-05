#!/usr/bin/env python3
"""Documentation index, validation, scaffolding and git hook for doc/."""

from __future__ import annotations

import argparse
import difflib
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

GROUP_LABELS = {
    "build": "环境与构建",
    "feature": "功能与工作流",
    "convention": "约定",
}
REQUIRED_FIELDS = ("title", "summary", "group")
PLACEHOLDER_SUMMARY = "一句话说明什么时候该读这篇文档。"
PLACEHOLDER_BODIES = {"无", "暂无", "无。", "暂无。"}
NAME_RE = re.compile(r"^[a-z0-9][a-z0-9-]*$")
FENCE_RE = re.compile(r"^(`{3,}|~{3,})")
SETEXT_RE = re.compile(r"^(=+|-{3,})[ \t]*$")


class DocError(Exception):
    """A documentation problem that should stop the run."""


def repo_root() -> Path:
    return Path(__file__).resolve().parent.parent


def doc_dir() -> Path:
    return repo_root() / "doc"


def index_path() -> Path:
    return doc_dir() / "index.md"


def relative(path: Path) -> str:
    try:
        return str(path.relative_to(repo_root()))
    except ValueError:
        return str(path)


def parse_frontmatter(text: str, where: str) -> tuple[dict[str, str], str]:
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        raise DocError(f"{where}: missing YAML frontmatter on line 1")

    meta: dict[str, str] = {}
    for number, line in enumerate(lines[1:], start=2):
        stripped = line.strip()
        if stripped == "---":
            return meta, "\n".join(lines[number:])
        if not stripped or stripped.startswith("#"):
            continue
        if ":" not in line:
            raise DocError(f"{where}:{number}: expected `key: value`, got {line!r}")
        key, value = line.split(":", 1)
        key = key.strip()
        if not key:
            raise DocError(f"{where}:{number}: empty frontmatter key")
        if key in meta:
            raise DocError(f"{where}:{number}: duplicate frontmatter key {key!r}")
        meta[key] = value.strip()

    raise DocError(f"{where}: frontmatter is not closed")


def applies_to(meta: dict[str, str]) -> list[str]:
    return [item.strip() for item in meta.get("applies_to", "").split(",") if item.strip()]


def structure_problems(body: str, where: str) -> list[str]:
    problems: list[str] = []
    fence = ""
    fence_len = 0
    seen_heading = False
    preamble = False
    section = ""
    content = 0
    first = ""
    prev_text = False

    def close_section() -> None:
        nonlocal section, content, first
        if not section:
            return
        if content == 0:
            problems.append(f"{where}: empty section: {section}")
        elif content == 1 and first in PLACEHOLDER_BODIES:
            problems.append(f"{where}: placeholder section: {section}")
        section = ""
        content = 0
        first = ""

    for line in body.splitlines():
        marker = FENCE_RE.match(line)
        if fence:
            if (
                marker
                and marker.group(1)[0] == fence
                and len(marker.group(1)) >= fence_len
                and not line[marker.end() :].strip()
            ):
                fence = ""
            if line.strip():
                content += 1
            prev_text = False
            continue
        if marker:
            fence = marker.group(1)[0]
            fence_len = len(marker.group(1))
            content += 1
            prev_text = False
            continue
        if line.startswith("# "):
            problems.append(f"{where}: H1 is not allowed; start headings at H2")
            prev_text = False
            continue
        if line.startswith("## "):
            close_section()
            section = line
            seen_heading = True
            prev_text = False
            continue
        if line.startswith("### "):
            prev_text = False
            continue
        if not line.strip():
            prev_text = False
            continue

        if prev_text and SETEXT_RE.match(line):
            problems.append(
                f"{where}: setext heading is not allowed; write `## 标题` instead"
            )
            prev_text = False
            continue

        if not seen_heading:
            preamble = True
        content += 1
        if content == 1:
            first = line.strip()
        prev_text = True

    if fence:
        problems.append(f"{where}: unclosed code fence")
    if preamble:
        problems.append(f"{where}: body must start with an H2 heading")
    close_section()
    return problems


def quoted(value: str) -> bool:
    return len(value) > 1 and value[0] == value[-1] and value[0] in "'\""


def validate_doc(path: Path) -> dict[str, str]:
    where = relative(path)
    meta, body = parse_frontmatter(path.read_text(encoding="utf-8"), where)

    for field in REQUIRED_FIELDS:
        if not meta.get(field):
            raise DocError(f"{where}: missing {field}")

    title = meta["title"]
    summary = meta["summary"]
    group = meta["group"]

    for name, value in (("title", title), ("summary", summary)):
        if any(char in value for char in "|[]"):
            raise DocError(f"{where}: {name} must not contain | [ or ]")
        if quoted(value):
            raise DocError(f"{where}: {name} must not be quoted; write the value bare")

    if any(quoted(prefix) for prefix in applies_to(meta)):
        raise DocError(f"{where}: applies_to entries must not be quoted")

    if summary.endswith((":", "：")):
        raise DocError(f"{where}: summary must not end with a colon")
    if summary.startswith("一句话说明"):
        raise DocError(f"{where}: summary is still the template placeholder")
    if group not in GROUP_LABELS:
        raise DocError(f"{where}: unknown group {group!r}")

    unknown = set(meta) - set(REQUIRED_FIELDS) - {"applies_to"}
    if unknown:
        raise DocError(f"{where}: unknown frontmatter field(s): {', '.join(sorted(unknown))}")

    problems = structure_problems(body, where)
    if problems:
        raise DocError("\n".join(problems))

    return meta


def validate_all() -> dict[Path, dict[str, str]]:
    paths = sorted(path for path in doc_dir().glob("*.md") if path.name != "index.md")
    docs: dict[Path, dict[str, str]] = {}
    owners: dict[str, str] = {}

    for path in paths:
        meta = validate_doc(path)
        for prefix in applies_to(meta):
            if prefix in owners:
                raise DocError(
                    "applies_to declared by more than one document:\n"
                    f"  {prefix}  ({owners[prefix]}, {relative(path)})"
                )
            owners[prefix] = relative(path)
        docs[path] = meta

    return docs


def render(docs: dict[Path, dict[str, str]]) -> str:
    lines = [
        "# Project Documentation Index",
        "> Generated by `tool/build_doc_index.sh`; do not edit this file manually.",
        "",
        "Read the matching doc before changing architecture, build tooling, or feature "
        "workflows; the code alone does not record why.",
        "",
    ]

    for group, label in GROUP_LABELS.items():
        rows = [(path, meta) for path, meta in docs.items() if meta["group"] == group]
        if not rows:
            continue
        lines.extend(
            [
                f"## {label}",
                "",
                "| 文档 | 何时读 | 适用路径 |",
                "| --- | --- | --- |",
            ]
        )
        for path, meta in rows:
            paths = ", ".join(f"`{prefix}`" for prefix in applies_to(meta)) or "—"
            lines.append(f"| [{meta['title']}]({path.name}) | {meta['summary']} | {paths} |")
        lines.append("")

    return "\n".join(lines).rstrip("\n") + "\n"


def write_index(docs: dict[Path, dict[str, str]]) -> None:
    target = index_path()
    with tempfile.NamedTemporaryFile(
        "w", dir=target.parent, delete=False, encoding="utf-8"
    ) as handle:
        handle.write(render(docs))
        temporary = Path(handle.name)
    os.chmod(temporary, 0o644)
    temporary.replace(target)


def check_index(docs: dict[Path, dict[str, str]]) -> None:
    expected = render(docs)
    current = index_path().read_text(encoding="utf-8") if index_path().exists() else ""
    if current == expected:
        return

    sys.stderr.write(
        "".join(
            difflib.unified_diff(
                current.splitlines(keepends=True),
                expected.splitlines(keepends=True),
                fromfile="doc/index.md",
                tofile="doc/index.md (expected)",
            )
        )
    )
    raise DocError("doc/index.md is stale; run tool/build_doc_index.sh")


def git(*args: str, optional: bool = False) -> str | None:
    result = subprocess.run(
        ["git", *args], cwd=repo_root(), text=True, capture_output=True
    )
    if result.returncode != 0:
        if optional:
            return None
        raise DocError(result.stderr.strip() or f"git {' '.join(args)} failed")
    return result.stdout


def path_matches(changed: str, prefix: str) -> bool:
    prefix = prefix.rstrip("/")
    return changed == prefix or changed.startswith(prefix + "/")


def hook() -> int:
    docs = validate_all()

    staged_output = git(
        "diff", "--cached", "--name-only", "--diff-filter=ACMR", "--", "doc/*.md"
    ) or ""
    staged_docs = [
        line for line in staged_output.splitlines() if line and line != "doc/index.md"
    ]
    staged_set = set(staged_docs)

    all_output = git("diff", "--cached", "--name-only", "--diff-filter=ACMRD") or ""

    drift: list[tuple[str, str, str]] = []
    for rel in staged_docs:
        path = repo_root() / rel
        if not path.is_file():
            continue
        old_text = git("show", f"HEAD:{rel}", optional=True)
        if not old_text:
            continue
        try:
            old_meta, old_body = parse_frontmatter(old_text, f"HEAD:{rel}")
            new_meta, new_body = parse_frontmatter(
                path.read_text(encoding="utf-8"), rel
            )
        except DocError:
            continue
        unchanged_meta = (
            old_meta.get("title") == new_meta.get("title")
            and old_meta.get("summary") == new_meta.get("summary")
        )
        if unchanged_meta and old_body.strip() != new_body.strip():
            drift.append((rel, new_meta.get("title", ""), new_meta.get("summary", "")))

    impact: set[tuple[str, str]] = set()
    for changed in all_output.splitlines():
        if not changed or changed.startswith("doc/"):
            continue
        for path, meta in docs.items():
            owner = relative(path)
            if owner in staged_set:
                continue
            if any(path_matches(changed, prefix) for prefix in applies_to(meta)):
                impact.add((owner, changed))

    if (drift or impact) and os.environ.get("DOC_REVIEWED") != "1":
        print("\n提交前需要确认以下文档仍然准确：", file=sys.stderr)
        if drift:
            print("\n  正文有改动，但 title/summary 未变：", file=sys.stderr)
            for rel, title, summary in drift:
                print(f"    {rel}\n      title:   {title}\n      summary: {summary}", file=sys.stderr)
        if impact:
            print("\n  声明的路径被改动，但文档没有一起修改：", file=sys.stderr)
            for rel, changed in sorted(impact):
                print(f"    {rel}  ← {changed}", file=sys.stderr)

        if sys.stdin.isatty():
            try:
                answer = input("\n确认以上文档仍然准确？[y/N] ")
            except EOFError:
                answer = ""
            if answer.strip().lower() not in {"y", "yes"}:
                print(
                    "已中止。更新相关文档，或用 DOC_REVIEWED=1 git commit ... 显式确认。",
                    file=sys.stderr,
                )
                return 1
        else:
            print(
                "\n没有可交互终端。确认后用 DOC_REVIEWED=1 git commit ...。",
                file=sys.stderr,
            )
            return 1

    write_index(docs)
    git("add", "doc/index.md")
    return 0


def new_doc(name: str, title: str | None, group: str) -> int:
    if not NAME_RE.match(name):
        raise DocError(f"file name must be lowercase kebab-case, got {name}")
    if group not in GROUP_LABELS:
        raise DocError(
            f"group must be one of {', '.join(GROUP_LABELS)}, got {group}"
        )

    target = doc_dir() / f"{name}.md"
    if target.exists():
        raise DocError(f"doc/{name}.md already exists")

    template = doc_dir() / "documentation-standard.md"
    _, body = parse_frontmatter(template.read_text(encoding="utf-8"), relative(template))
    meta = {
        "title": title or name,
        "summary": PLACEHOLDER_SUMMARY,
        "group": group,
        "applies_to": "",
    }
    frontmatter = "".join(
        f"{key}: {value}\n" if value else f"{key}:\n" for key, value in meta.items()
    )
    target.write_text(f"---\n{frontmatter}---\n{body}", encoding="utf-8")
    print(f"Created doc/{name}.md from doc/documentation-standard.md; replace the body.")
    return 0


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)

    index_parser = subparsers.add_parser("index", help="build or check doc/index.md")
    index_parser.add_argument("--check", action="store_true", help="fail on drift")
    index_parser.add_argument("--validate", action="store_true", help="validate only")

    new_parser = subparsers.add_parser("new", help="create a doc from the standard")
    new_parser.add_argument("name")
    new_parser.add_argument("title", nargs="?")
    new_parser.add_argument("group", nargs="?", default="feature")

    subparsers.add_parser("hook", help="run the pre-commit checks")

    args = parser.parse_args(argv)

    try:
        if args.command == "index":
            docs = validate_all()
            if args.validate:
                return 0
            if args.check:
                check_index(docs)
                return 0
            write_index(docs)
            return 0
        if args.command == "new":
            return new_doc(args.name, args.title, args.group)
        if args.command == "hook":
            return hook()
    except DocError as error:
        for line in str(error).splitlines():
            print(f"doc: {line}", file=sys.stderr)
        return 1

    parser.error(f"unknown command {args.command}")
    return 2


if __name__ == "__main__":
    sys.exit(main())

