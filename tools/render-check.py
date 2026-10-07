#!/usr/bin/env python3
"""Render the template with Liquid and check the result, without cargo-generate.

This is a fast local gate for template authors. It answers the questions
that only surface *after* generation otherwise:

  * does every templated file still parse (TOML / YAML / JSON) once the
    placeholders are substituted, for every combination of prompts?
  * did any placeholder survive into the output unexpanded?
  * did a file that must NOT be templated (a GitHub Actions workflow,
    cliff.toml, the justfile) accidentally get processed -- or, worse,
    did a templated file end up on the exclude list?
  * do the placeholder regexes accept their own defaults?

It is an approximation: cargo-generate uses the Rust `liquid` crate and
this uses python-liquid. They agree on the subset used here (assign,
if/elsif/else, unless, for, split, strip, replace, date), which is why
the template deliberately stays inside that subset.

One known divergence: after a `-%}` trim tag, python-liquid also drops
the template's final newline where liquid-rust keeps it. Output from
real cargo-generate is byte-identical to this harness's apart from that
one trailing byte, so do not use this to check trailing whitespace.
Anything about whitespace, run the smoke-test workflow instead.

When `nix-instantiate` is on PATH, every rendered `.nix` file is parsed
too (no evaluation: that needs the flake's inputs; the smoke test runs
`nix flake check`).

Usage:  python3 tools/render-check.py
Exit:   0 = all good, 1 = at least one check failed.
"""

from __future__ import annotations

import fnmatch
import json
import pathlib
import re
import shutil
import subprocess
import sys
import tomllib

try:
    from liquid import Environment
except ImportError:  # pragma: no cover - dependency hint
    sys.exit("python-liquid is required:  pip install python-liquid")

try:
    import yaml
except ImportError:  # pragma: no cover - dependency hint
    sys.exit("PyYAML is required:  pip install pyyaml")

ROOT = pathlib.Path(__file__).resolve().parent.parent
TEMPLATE = ROOT / "template"
CONFIG = TEMPLATE / "cargo-generate.toml"

# cargo-generate's built-ins, plus one sample answer per prompt. The
# combinations that change the file set are varied in `CASES` below.
BASE_VARS = {
    "project-name": "sample-crate",
    "crate_name": "sample_crate",
    "authors": "Jane Doe <jane@example.com>",
    "username": "jane",
    "os-arch": "linux-x86_64",
    "within_cargo_project": False,
    "is_init": False,
    "description": "A sample crate.",
    "author_name": "Jane Doe",
    "author_email": "jane@example.com",
    "github_username": "jane",
    "msrv": "1.92",
    "keywords": "rust, sample",
    "categories": "development-tools, command-line-utilities",
}

CASES = [
    {"project_kind": k, "license": lic, **extra}
    for k in ("bin", "lib", "both", "workspace")
    for lic in ("MIT OR Apache-2.0", "MIT", "Apache-2.0")
    for extra in ({}, {"author_email": ""})
]

# `{{project-name}}` is valid for the Rust liquid crate but the dash
# parses as subtraction in python-liquid, so rewrite the identifier
# inside tags only -- never in prose that happens to mention it.
TAG = re.compile(r"\{\{.*?\}\}|\{%.*?%\}", re.DOTALL)


def normalise(text: str) -> str:
    return TAG.sub(lambda m: m.group(0).replace("project-name", "project_name"), text)


def matches_any(rel: str, globs: list[str]) -> bool:
    return any(
        fnmatch.fnmatch(rel, g) or rel == g or rel.startswith(g.rstrip("/") + "/")
        for g in globs
    )


def main() -> int:
    cfg = tomllib.loads(CONFIG.read_text())
    excluded = cfg["template"].get("exclude", [])
    placeholders = cfg["placeholders"]
    conditionals = cfg.get("conditional", {})
    env = Environment()
    failures: list[str] = []

    def fail(msg: str) -> None:
        failures.append(msg)
        print(f"  FAIL {msg}")

    # 1. Every placeholder default must satisfy its own regex.
    print("== placeholder defaults vs regexes")
    for name, spec in placeholders.items():
        if "regex" not in spec or "default" not in spec:
            continue
        if not re.search(spec["regex"], str(spec["default"])):
            fail(f"{name}: default {spec['default']!r} rejected by its own regex")
    print(f"  checked {len(placeholders)} placeholders")

    # 1b. `ignore` entries are literal paths, not globs: cargo-generate
    #     joins each onto the output dir and removes it. A glob would
    #     resolve to a non-existent path and be skipped silently,
    #     shipping a file that was meant to be dropped.
    print("== conditional ignore paths")
    for expr, section in conditionals.items():
        for entry in section.get("ignore", []):
            if any(ch in entry for ch in "*?["):
                fail(f"{expr}: ignore entry {entry!r} looks like a glob; ignore takes literal paths")
            elif not (TEMPLATE / entry).exists():
                fail(f"{expr}: ignore entry {entry!r} does not exist in the template")
    print(f"  checked {sum(len(s.get('ignore', [])) for s in conditionals.values())} paths")

    # 1d. The starter function exists in two copies -- src/lib.rs for the
    #     single-package layouts and crates/<name>-core/src/lib.rs for the
    #     workspace. Their prose differs on purpose; the code must not.
    print("== duplicated starter code")
    def fn_body(path: pathlib.Path) -> str:
        text = path.read_text()
        start = text.index("#[must_use]")
        return re.sub(r"\s+", " ", text[start:]).strip()

    core = TEMPLATE / "crates" / "{{project-name}}-core" / "src" / "lib.rs"
    single = TEMPLATE / "src" / "lib.rs"
    if core.exists() and single.exists():
        a = fn_body(single).replace("{{crate_name}}::", "CRATE::")
        b = fn_body(core).replace("{{crate_name}}_core::", "CRATE::")
        if a != b:
            fail("src/lib.rs and the workspace core lib.rs have drifted apart")
        else:
            print("  single-package and workspace copies agree")
    else:
        fail("expected both a single-package and a workspace copy of lib.rs")

    # 1e. Each workspace member carries copies of the root's licence texts
    #     (a member's .crate holds its own directory only): byte-identical,
    #     so the copies cannot drift from the root's.
    print("== member licence copies")
    for member in sorted((TEMPLATE / "crates").iterdir()):
        for name in ("LICENSE-MIT", "LICENSE-APACHE"):
            copy = member / name
            if not copy.exists():
                fail(f"crates/{member.name}/{name} is missing")
            elif copy.read_bytes() != (TEMPLATE / name).read_bytes():
                fail(f"crates/{member.name}/{name} differs from the root's {name}")
    print("  checked the members' licence files")

    nix = shutil.which("nix-instantiate")

    files = sorted(
        p for p in TEMPLATE.rglob("*") if p.is_file() and p.name != "cargo-generate.toml"
    )

    # 1c. Every variable referenced in a templated file must be declared
    #     or built in. This one matters more than it looks: when Liquid
    #     hits an unknown variable, cargo-generate catches the error,
    #     inserts an empty string and re-renders (see
    #     `render_string_gracefully` in template.rs). So a misspelled
    #     placeholder does not fail -- it silently renders as nothing,
    #     and the "no leftover {{" check below cannot see it.
    print("== variable references")
    builtins = {
        "project-name", "crate_name", "crate_type", "authors",
        "username", "os-arch", "within_cargo_project", "is_init",
    }
    known = builtins | set(placeholders)
    for section in conditionals.values():
        known |= set(section.get("placeholders", {}))
    ident = re.compile(r"[A-Za-z_][A-Za-z0-9_-]*")
    literal = re.compile(r"\"[^\"]*\"|'[^']*'")
    # Liquid keywords, filters, and forloop members are not variables.
    reserved = {
        "if", "elsif", "else", "endif", "unless", "endunless", "for",
        "endfor", "in", "assign", "capture", "endcapture", "case", "when",
        "endcase", "break", "continue", "raw", "endraw", "comment",
        "endcomment", "and", "or", "contains", "true", "false", "nil",
        "empty", "forloop", "last", "first", "index", "index0", "rindex",
        "length", "now", "today", "strip", "split", "replace", "date",
        "upcase", "downcase", "join", "size", "default", "append",
        "prepend", "rhai", "kebab_case", "snake_case", "pascal_case",
        "title_case", "upper_camel_case", "lower_camel_case",
        "shouty_snake_case", "shouty_kebab_case",
    }
    refs = 0
    for path in files:
        rel = str(path.relative_to(TEMPLATE))
        if matches_any(rel, excluded):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        # names bound by the template itself
        local = set(re.findall(r"assign\s+([A-Za-z_][A-Za-z0-9_]*)\s*=", text))
        local |= set(re.findall(r"for\s+([A-Za-z_][A-Za-z0-9_]*)\s+in", text))
        for match in TAG.finditer(text):
            expr = literal.sub("", match.group(0).strip("{}%- "))
            for token in ident.findall(expr):
                base = token.split(".")[0]
                refs += 1
                if base not in reserved and base not in known and base not in local:
                    fail(f"{rel}: unknown variable {base!r} -- it would render as an empty string")
    print(f"  checked {refs} identifier references")

    # 2. Excluded files must be free of *our* placeholders: they are
    #    copied verbatim, so a placeholder there would ship unexpanded.
    print("== exclude list integrity")
    ours = set(placeholders) | {"project-name", "crate_name", "authors", "msrv"}
    for path in files:
        rel = str(path.relative_to(TEMPLATE))
        if not matches_any(rel, excluded):
            continue
        text = path.read_text(encoding="utf-8", errors="replace")
        for var in ours:
            if re.search(r"\{\{\s*" + re.escape(var) + r"\s*\}\}", text):
                fail(f"{rel} is on the exclude list but contains {{{{{var}}}}}")
    print(f"  checked {sum(1 for p in files if matches_any(str(p.relative_to(TEMPLATE)), excluded))} excluded files")

    # 3. Render every case and validate the output.
    for case in CASES:
        vars_ = {**BASE_VARS, **case}
        vars_["project_name"] = vars_["project-name"]
        label = f"{case['project_kind']}/{case['license']}" + (
            "/no-email" if case.get("author_email") == "" else ""
        )
        print(f"== render {label}")

        ignored: list[str] = []
        for expr, section in conditionals.items():
            # The conditions used here are all `key == "value"`.
            m = re.fullmatch(r"(\w+)\s*==\s*\"([^\"]+)\"", expr)
            if not m:
                fail(f"harness cannot evaluate conditional {expr!r}")
                continue
            if str(vars_.get(m.group(1))) == m.group(2):
                ignored.extend(section.get("ignore", []))

        rendered_count = 0
        for path in files:
            rel = str(path.relative_to(TEMPLATE))
            # Deliberately NOT skipping `ignored` files, though cargo-generate
            # (0.25) removes them before rendering: a file every case renders
            # is a file whose Liquid every case checks, stricter than needed.
            raw = path.read_text(encoding="utf-8", errors="replace")
            if matches_any(rel, excluded):
                out = raw
            else:
                try:
                    out = env.from_string(normalise(raw)).render(**vars_)
                except Exception as exc:  # noqa: BLE001 - report and continue
                    fail(f"{rel}: liquid error: {exc}")
                    continue
                leftovers = TAG.findall(out)
                if leftovers:
                    fail(f"{rel}: unexpanded template syntax: {leftovers[:3]}")
                rendered_count += 1

            suffix = path.suffix
            try:
                if suffix == ".toml":
                    tomllib.loads(out)
                elif suffix in (".yml", ".yaml"):
                    yaml.safe_load(out)
                elif suffix == ".json":
                    json.loads(out)
                elif suffix == ".nix" and nix and rel not in ignored:
                    parsed = subprocess.run(
                        [nix, "--parse", "-"], input=out, capture_output=True, text=True, check=False
                    )
                    if parsed.returncode != 0:
                        raise ValueError(parsed.stderr.strip())
            except Exception as exc:  # noqa: BLE001 - report and continue
                fail(f"{rel}: invalid {suffix.lstrip('.') or 'text'} after render: {exc}")

        # 4. The manifest must describe the target layout correctly.
        manifest_path = TEMPLATE / "Cargo.toml"
        manifest = tomllib.loads(
            env.from_string(normalise(manifest_path.read_text())).render(**vars_)
        )
        is_workspace = case["project_kind"] == "workspace"
        pkg = manifest["workspace"]["package"] if is_workspace else manifest["package"]
        # A workspace root inherits keywords but not categories or
        # description: those are per-member, and each member manifest
        # sets them (checked separately below).
        needed = ["keywords"] if is_workspace else ["keywords", "categories"]
        for key in needed:
            if not pkg.get(key):
                fail(f"{label}: clippy::cargo_common_metadata needs a non-empty {key}")
            elif any(not v.strip() for v in pkg[key]):
                fail(f"{label}: blank entry in {key}")
        is_ws = case["project_kind"] == "workspace"
        if is_ws != ("workspace" in manifest):
            fail(f"{label}: [workspace] table presence does not match project_kind")
        has_bin = "bin" in manifest
        if has_bin != (case["project_kind"] not in ("lib", "workspace")):
            fail(f"{label}: [[bin]] present={has_bin} for project_kind")
        if ("profile" in manifest and "dist" in manifest["profile"]) != (
            case["project_kind"] != "lib"
        ):
            fail(f"{label}: [profile.dist] does not match project_kind")
        expected_author = (
            "Jane Doe" if vars_["author_email"] == "" else "Jane Doe <jane@example.com>"
        )
        if pkg["authors"] != [expected_author]:
            fail(f"{label}: authors is {pkg['authors']!r}, expected [{expected_author!r}]")
        if pkg["license"] != case["license"]:
            fail(f"{label}: license is {pkg['license']!r}")

        # 5. Source files must exist for the layout, and only those.
        if is_workspace:
            # Every member manifest must render, parse, and carry the
            # per-member metadata the workspace root does not supply.
            members = sorted((TEMPLATE / "crates").iterdir())
            if len(members) != 2:
                fail(f"{label}: expected 2 member crates, found {len(members)}")
            for member in members:
                mf = member / "Cargo.toml"
                whole = tomllib.loads(
                    env.from_string(normalise(mf.read_text())).render(**vars_)
                )
                m = whole["package"]
                if not m.get("description") or not m.get("categories"):
                    fail(f"{label}: {member.name} must set its own description and categories")
                # `[lints]` is a top-level table: a member without
                # `workspace = true` silently opts out of the whole policy
                if whole.get("lints") != {"workspace": True}:
                    fail(f"{label}: {member.name} must inherit the lints: [lints] workspace = true")
        else:
            src = {p.name for p in (TEMPLATE / "src").iterdir()}
            for name, wanted in (
                ("lib.rs", case["project_kind"] != "bin"),
                ("main.rs", case["project_kind"] != "lib"),
            ):
                present = name in src and not matches_any(f"src/{name}", ignored)
                if present != wanted:
                    fail(f"{label}: src/{name} present={present}, wanted={wanted}")

        print(f"  rendered {rendered_count} files, manifest checks done")

    print()
    if failures:
        print(f"{len(failures)} FAILURE(S)")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
