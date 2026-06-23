#!/usr/bin/env python3
"""
Suggest the next safe Convoy version when master_check_version fails.

Run from the root of the checked-out repo (cwd = repo root).
Called by the suggest-version job in master_check_version.yml.
Credentials come from NEXUS_USERNAME / NEXUS_PASSWORD env vars.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from typing import Iterable, Optional

import requests
import yaml
from requests.auth import HTTPBasicAuth

DEFAULT_NEXUS_URL = "https://nexus.tessell.cloud"
DEFAULT_NEXUS_REPO_M2 = "tessell-repos-m2-component"
DEFAULT_NEXUS_REPO_PY = "tessell-repos-py-component"
REL_BRANCH_RE = re.compile(r"^rel-(\d+)\.(\d+)\.(\d+)$")
SEMVER_RE = re.compile(r"^(\d+)\.(\d+)\.(\d+)$")


@dataclass(frozen=True)
class SemVer:
    major: int
    minor: int
    patch: int

    @classmethod
    def parse(cls, raw: str) -> Optional["SemVer"]:
        m = SEMVER_RE.match((raw or "").strip())
        if not m:
            return None
        return cls(int(m.group(1)), int(m.group(2)), int(m.group(3)))

    def __str__(self) -> str:
        return f"{self.major}.{self.minor}.{self.patch}"

    def as_tuple(self) -> tuple[int, int, int]:
        return self.major, self.minor, self.patch


def run_git(*args: str) -> str:
    res = subprocess.run(
        ["git", *args],
        capture_output=True,
        text=True,
        check=False,
    )
    if res.returncode != 0:
        raise RuntimeError(
            f"git {' '.join(args)} failed: {res.stderr.strip()}"
        )
    return res.stdout


def fetch_branches() -> None:
    """Best-effort fetch so remote refs are up to date."""
    try:
        subprocess.run(
            ["git", "fetch", "--prune", "--quiet", "origin"],
            check=False,
            timeout=60,
        )
    except Exception as exc:  # noqa: BLE001
        print(f"warning: git fetch failed ({exc}); using local refs", file=sys.stderr)


def list_remote_branches() -> list[str]:
    out = run_git("for-each-ref", "--format=%(refname:short)", "refs/remotes/origin")
    return [line.strip().removeprefix("origin/") for line in out.splitlines() if line.strip()]


def current_branch() -> Optional[str]:
    try:
        name = run_git("rev-parse", "--abbrev-ref", "HEAD").strip()
    except RuntimeError:
        return None
    return name or None


def read_convoy_at(ref: str, rel_path: str) -> Optional[dict]:
    try:
        out = run_git("show", f"{ref}:{rel_path}")
    except RuntimeError:
        return None
    try:
        return yaml.safe_load(out) or {}
    except yaml.YAMLError as exc:
        print(f"warning: failed to parse {ref}:{rel_path}: {exc}", file=sys.stderr)
        return None


def read_convoy_local(rel_path: str) -> dict:
    with open(rel_path, "r", encoding="utf-8") as fh:
        return yaml.safe_load(fh) or {}


def pick_top_rel_branches(branches: Iterable[str], target_major: int, top_n: int) -> list[str]:
    candidates: list[tuple[int, int, int, str]] = []
    for name in branches:
        m = REL_BRANCH_RE.match(name)
        if not m:
            continue
        major, minor, patch = int(m.group(1)), int(m.group(2)), int(m.group(3))
        if major != target_major:
            continue
        candidates.append((major, minor, patch, name))
    candidates.sort(key=lambda t: (t[0], t[1], t[2]), reverse=True)
    return [name for *_unused, name in candidates[:top_n]]


def resolve_exporter(root_data: dict, dir_data: dict, language: str) -> Optional[str]:
    """Mirror master_check_version.yml exporter resolution rules."""
    try:
        exporter = dir_data["generates"]["artifacts"][0]["name"]
    except (KeyError, IndexError, TypeError):
        return None
    app_group = (root_data or {}).get("appGroup", "tessell")
    if language == "terraform":
        if app_group != "tessell":
            exporter = f"{app_group}-{exporter}"
    elif language == "python":
        exporter = exporter.replace("-", "_")
    return exporter


def nexus_repo_for_language(language: str) -> str:
    if language == "python":
        return DEFAULT_NEXUS_REPO_PY
    return DEFAULT_NEXUS_REPO_M2


def query_nexus_versions(
    base_url: str,
    repository: str,
    name: str,
    username: str,
    password: str,
) -> list[SemVer]:
    """Page through Nexus search results and return all parseable versions."""
    url = f"{base_url.rstrip('/')}/service/rest/v1/search"
    auth = HTTPBasicAuth(username, password)
    versions: list[SemVer] = []
    continuation_token: Optional[str] = None
    while True:
        params: dict[str, str] = {"repository": repository, "name": name}
        if continuation_token:
            params["continuationToken"] = continuation_token
        resp = requests.get(url, params=params, auth=auth, timeout=30)
        resp.raise_for_status()
        body = resp.json()
        for item in body.get("items", []):
            sv = SemVer.parse(item.get("version", ""))
            if sv:
                versions.append(sv)
        continuation_token = body.get("continuationToken")
        if not continuation_token:
            break
    return versions


def collect_branch_versions(
    branches: list[str],
    rel_path: str,
) -> dict[str, Optional[SemVer]]:
    out: dict[str, Optional[SemVer]] = {}
    for branch in branches:
        data = read_convoy_at(f"origin/{branch}", rel_path)
        if data is None:
            out[branch] = None
            continue
        out[branch] = SemVer.parse(str(data.get("version", "")))
    return out


def suggest_next(known: list[SemVer]) -> dict[str, SemVer]:
    """Return next patch / minor / major from the highest known version."""
    if not known:
        base = SemVer(0, 0, 0)
    else:
        base = max(known, key=lambda v: v.as_tuple())
    return {
        "patch": SemVer(base.major, base.minor, base.patch + 1),
        "minor": SemVer(base.major, base.minor + 1, 0),
        "major": SemVer(base.major + 1, 0, 0),
    }


def render_report(
    *,
    exporter: str,
    rel_path: str,
    current_version: Optional[SemVer],
    current_branch_name: Optional[str],
    branch_versions: dict[str, Optional[SemVer]],
    nexus_max: Optional[SemVer],
    nexus_count: Optional[int],
    suggestions: dict[str, SemVer],
    on_rel_branch: bool,
    fmt: str = "plain",
) -> str:
    if fmt == "markdown":
        lines: list[str] = [f"### `{exporter}` \u2014 `{rel_path}`", ""]
        lines.append("| Source | Version |")
        lines.append("|---|---|")
        for branch, ver in branch_versions.items():
            marker = " \u2190 this PR" if branch == current_branch_name else ""
            shown = f"`{ver}`{marker}" if ver else "*(missing)*"
            lines.append(f"| `{branch}` | {shown} |")
        if nexus_max is not None:
            lines.append(f"| Nexus (highest published) | `{nexus_max}` ({nexus_count} components) |")
        elif nexus_count is None:
            lines.append("| Nexus | *(credentials not provided)* |")
        lines.append("")
        if current_version:
            lines.append(f"**Current version in this PR:** `{current_version}`")
            lines.append("")
        lines.append("**Suggested next versions:**")
        p = str(suggestions['patch'])
        mi = str(suggestions['minor'])
        ma = str(suggestions['major'])
        lines.append(f"- Patch (recommended on rel-*): **{p}**")
        lines.append(f"- Minor: {mi}")
        lines.append(f"- Major: {ma}")
        return "\n".join(lines)
    lines: list[str] = []
    lines.append("=" * 72)
    lines.append(f"Convoy version report for: {exporter}  ({rel_path})")
    lines.append("=" * 72)
    lines.append("")
    lines.append(f"{'Source':<32} {'Version'}")
    lines.append(f"{'-' * 32} {'-' * 16}")
    for branch, ver in branch_versions.items():
        marker = "  <-- current PR" if branch == current_branch_name else ""
        shown = str(ver) if ver else "(missing / unparseable)"
        lines.append(f"{branch:<32} {shown}{marker}")
    if nexus_max is not None:
        lines.append(f"{'nexus (highest published)':<32} {nexus_max}  ({nexus_count} components)")
    elif nexus_count is None:
        lines.append(f"{'nexus':<32} (skipped: credentials not provided)")
    else:
        lines.append(f"{'nexus':<32} (no published versions found)")
    if current_version is not None:
        lines.append("")
        lines.append(f"current convoy.yaml version: {current_version}")
    lines.append("")
    lines.append("Suggested next versions:")
    rec_note = " (recommended on rel-* branches)" if on_rel_branch else " (recommended)"
    lines.append(f"  patch  -> {suggestions['patch']}{rec_note}")
    lines.append(f"  minor  -> {suggestions['minor']}")
    lines.append(f"  major  -> {suggestions['major']}")
    lines.append("")
    lines.append(f"=> RECOMMENDED: {suggestions['patch']}")
    return "\n".join(lines)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--dir", default=".", help="Subdirectory containing the convoy.yaml to check (default: repo root)")
    parser.add_argument("--top-n", type=int, default=4, help="Number of top rel-MAJOR.X.0 branches to consider (default: 4)")
    parser.add_argument("--no-fetch", action="store_true", help="Skip 'git fetch origin' before reading branches")
    parser.add_argument("--nexus-url", default=os.environ.get("NEXUS_URL", DEFAULT_NEXUS_URL))
    parser.add_argument("--nexus-repo", default=None, help="Override Nexus repository (default chosen by language)")
    parser.add_argument("--nexus-username", default=os.environ.get("NEXUS_USERNAME"))
    parser.add_argument("--nexus-password", default=os.environ.get("NEXUS_PASSWORD"))
    parser.add_argument("--format", choices=["plain", "markdown"], default="plain",
                        help="Output format for the report (plain or markdown)")
    parser.add_argument("--skip-nexus", action="store_true",
                        help="Do not contact Nexus even if credentials are available")
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    sub_dir = args.dir.strip("/") or "."
    rel_convoy = "convoy.yaml" if sub_dir in (".", "") else f"{sub_dir}/convoy.yaml"
    if not os.path.exists("convoy.yaml"):
        print("error: convoy.yaml not found in cwd", file=sys.stderr)
        return 2

    root_data = read_convoy_local("convoy.yaml")
    language = (root_data.get("language") or "").strip()
    if not language:
        print("error: 'language' missing from root convoy.yaml", file=sys.stderr)
        return 2

    try:
        dir_data = read_convoy_local(rel_convoy)
    except FileNotFoundError:
        print(f"error: {rel_convoy} not found in cwd", file=sys.stderr)
        return 2

    exporter = resolve_exporter(root_data, dir_data, language)
    if not exporter:
        print(f"error: could not resolve exporter name from {rel_convoy}", file=sys.stderr)
        return 2

    current_version = SemVer.parse(str(dir_data.get("version", "")))

    if not args.no_fetch:
        fetch_branches()

    branch_name = current_branch()
    target_major: Optional[int] = None
    on_rel_branch = False
    if branch_name:
        m = REL_BRANCH_RE.match(branch_name)
        if m:
            target_major = int(m.group(1))
            on_rel_branch = True
    if target_major is None and current_version is not None:
        target_major = current_version.major
    if target_major is None:
        target_major = 0

    all_branches = list_remote_branches()
    rel_branches = pick_top_rel_branches(all_branches, target_major, args.top_n)
    branches_to_check = (["main"] if "main" in all_branches else []) + rel_branches
    if branch_name and branch_name not in branches_to_check and REL_BRANCH_RE.match(branch_name):
        branches_to_check.append(branch_name)

    branch_versions = collect_branch_versions(branches_to_check, rel_convoy)

    nexus_versions: list[SemVer] = []
    nexus_count: Optional[int] = None
    nexus_max: Optional[SemVer] = None
    if not args.skip_nexus and args.nexus_username and args.nexus_password:
        repo = args.nexus_repo or nexus_repo_for_language(language)
        try:
            nexus_versions = query_nexus_versions(
                args.nexus_url, repo, exporter, args.nexus_username, args.nexus_password
            )
            nexus_count = len(nexus_versions)
            nexus_max = max(nexus_versions, key=lambda v: v.as_tuple()) if nexus_versions else None
        except requests.RequestException as exc:
            print(f"warning: Nexus query failed: {exc}", file=sys.stderr)

    known: list[SemVer] = [v for v in branch_versions.values() if v]
    known.extend(nexus_versions)
    if current_version:
        known.append(current_version)
    suggestions = suggest_next(known)

    print(render_report(
        exporter=exporter,
        rel_path=rel_convoy,
        current_version=current_version,
        current_branch_name=branch_name,
        branch_versions=branch_versions,
        nexus_max=nexus_max,
        nexus_count=nexus_count,
        suggestions=suggestions,
        on_rel_branch=on_rel_branch,
        fmt=getattr(args, "format", "plain"),
    ))
    return 0


if __name__ == "__main__":
    sys.exit(main())

