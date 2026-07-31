#!/usr/bin/env python3
"""Create or update the automated buzz source update pull request."""

from __future__ import annotations

import argparse
import os
import subprocess
import sys
from dataclasses import dataclass

MANAGED_PATHS = [
    "packages/source/pin.json",
    "packages/build-buzz-frontend/hashes.json",
    "packages/build-buzz-rust/hashes.json",
    "packages/buzz-desktop/hashes.json",
]


@dataclass(frozen=True, slots=True)
class PullRequest:
    branch: str
    title: str
    body: str


def run(
    cmd: list[str], *, check: bool = True, capture: bool = False
) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        cmd,
        text=True,
        stdout=subprocess.PIPE if capture else None,
        stderr=subprocess.PIPE if capture else None,
        check=False,
    )
    if check and result.returncode != 0:
        if capture:
            sys.stdout.write(result.stdout)
            sys.stderr.write(result.stderr)
        raise RuntimeError(f"command failed with exit code {result.returncode}: {cmd}")
    return result


def remote_branch_sha(branch: str) -> str | None:
    result = run(["git", "ls-remote", "--heads", "origin", branch], capture=True)
    return result.stdout.split("\t", 1)[0].strip() or None


def pr_exists(branch: str) -> bool:
    return (
        run(["gh", "pr", "view", branch, "--json", "number"], check=False).returncode
        == 0
    )


def push_branch(branch: str) -> None:
    remote_sha = remote_branch_sha(branch)
    if remote_sha:
        run(
            [
                "git",
                "push",
                f"--force-with-lease=refs/heads/{branch}:{remote_sha}",
                "origin",
                f"HEAD:refs/heads/{branch}",
            ]
        )
    else:
        run(["git", "push", "origin", f"HEAD:refs/heads/{branch}"])


def create_or_update_pr(pr: PullRequest, *, auto_merge: bool) -> None:
    run(["git", "checkout", "-B", pr.branch])
    run(["git", "add", *MANAGED_PATHS])

    if run(["git", "diff", "--cached", "--quiet"], check=False).returncode == 0:
        raise RuntimeError(
            "updater reported changes but produced no managed metadata diff"
        )

    run(["git", "commit", "--signoff", "-m", pr.title, "-m", pr.body])
    push_branch(pr.branch)

    if pr_exists(pr.branch):
        run(["gh", "pr", "edit", pr.branch, "--title", pr.title, "--body", pr.body])
    else:
        run(
            [
                "gh",
                "pr",
                "create",
                "--base",
                "main",
                "--head",
                pr.branch,
                "--title",
                pr.title,
                "--body",
                pr.body,
            ]
        )

    if auto_merge:
        run(["gh", "pr", "merge", pr.branch, "--auto", "--merge"])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("old_version", help="currently pinned buzz version")
    parser.add_argument("new_version", help="new buzz version")
    parser.add_argument(
        "--no-auto-merge",
        action="store_true",
        help="create or update the PR without enabling GitHub auto-merge",
    )
    return parser.parse_args()


def main() -> None:
    if not os.environ.get("GH_TOKEN"):
        raise RuntimeError("GH_TOKEN environment variable is not set")

    args = parse_args()
    pr = PullRequest(
        branch=f"update/buzz-{args.new_version}",
        title=f"buzz: {args.old_version} -> {args.new_version}",
        body=(
            "https://github.com/block/buzz/compare/"
            f"v{args.old_version}...v{args.new_version}"
        ),
    )
    create_or_update_pr(pr, auto_merge=not args.no_auto_merge)


if __name__ == "__main__":
    main()
