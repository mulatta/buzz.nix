#!/usr/bin/env python3
"""Update the pinned block/buzz release and fixed-output hashes."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

SOURCE_HASHES_PATH = Path("packages/source/hashes.json")
RUST_HASHES_PATH = Path("packages/build-buzz-rust/hashes.json")
DESKTOP_HASHES_PATH = Path("packages/buzz-desktop/hashes.json")
MANAGED_HASH_PATHS = (SOURCE_HASHES_PATH, RUST_HASHES_PATH, DESKTOP_HASHES_PATH)
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
GOT_HASH_RE = re.compile(r"got:\s+(sha256-[A-Za-z0-9+/=]+)")


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, text=True, capture_output=True, check=check)


def latest_tag() -> str:
    result = run(
        [
            "gh",
            "api",
            "repos/block/buzz/releases/latest",
            "--jq",
            ".tag_name",
        ],
        check=False,
    )
    if result.returncode == 0 and result.stdout.strip():
        return result.stdout.strip()

    result = run(
        [
            "gh",
            "api",
            "repos/block/buzz/tags",
            "--jq",
            ".[0].name",
        ]
    )
    return result.stdout.strip()


def prefetch_source(tag: str) -> tuple[str, Path]:
    url = f"https://github.com/block/buzz/archive/refs/tags/{tag}.tar.gz"
    result = run(["nix", "store", "prefetch-file", "--json", "--unpack", url])
    data = json.loads(result.stdout)
    return data["hash"], Path(data["storePath"])


def read_toml_version(path: Path) -> str:
    in_package = False
    for line in path.read_text().splitlines():
        stripped = line.strip()
        if stripped == "[package]":
            in_package = True
            continue
        if in_package and stripped.startswith("["):
            break
        if in_package and stripped.startswith("version"):
            return stripped.split("=", 1)[1].strip().strip('"')
    raise RuntimeError(f"version not found in {path}")


def read_rust_version(source: Path) -> str:
    toolchain = source / "rust-toolchain.toml"
    for line in toolchain.read_text().splitlines():
        stripped = line.strip()
        if stripped.startswith("channel"):
            return stripped.split("=", 1)[1].strip().strip('"')
    raise RuntimeError(f"channel not found in {toolchain}")


def load_hashes(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text())


def save_hashes(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n")


def write_output(key: str, value: str) -> None:
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a") as f:
            f.write(f"{key}={value}\n")
    else:
        print(f"output: {key}={value}")


def git_has_changes() -> bool:
    return (
        run(
            ["git", "diff", "--quiet", "--", *map(str, MANAGED_HASH_PATHS)],
            check=False,
        ).returncode
        != 0
    )


def parse_got_hash(output: str) -> str:
    matches = GOT_HASH_RE.findall(output)
    if not matches:
        sys.stderr.write(output)
        raise RuntimeError("could not find fixed-output hash mismatch")
    return matches[-1]


def refresh_cargo_hash(attr: str) -> str:
    result = run(["nix", "build", "--no-link", attr], check=False)
    combined = result.stdout + result.stderr
    if result.returncode == 0:
        raise RuntimeError(f"{attr} unexpectedly built with fake hash")
    return parse_got_hash(combined)


def update(tag: str) -> None:
    source_hash, source_path = prefetch_source(tag)
    version = tag.removeprefix("v")
    rust_version = read_rust_version(source_path)
    relay_version = read_toml_version(source_path / "crates/buzz-relay/Cargo.toml")

    source_data = load_hashes(SOURCE_HASHES_PATH)
    rust_data = load_hashes(RUST_HASHES_PATH)
    desktop_data = load_hashes(DESKTOP_HASHES_PATH)

    source_data.update(
        {
            "version": version,
            "relayVersion": relay_version,
            "rustVersion": rust_version,
            "rev": tag,
            "hash": source_hash,
        }
    )
    rust_data["cargoHash"] = FAKE_HASH
    desktop_data["cargoHash"] = FAKE_HASH
    save_hashes(SOURCE_HASHES_PATH, source_data)
    save_hashes(RUST_HASHES_PATH, rust_data)
    save_hashes(DESKTOP_HASHES_PATH, desktop_data)

    rust_data["cargoHash"] = refresh_cargo_hash(".#buzz-cli")
    save_hashes(RUST_HASHES_PATH, rust_data)

    desktop_data["cargoHash"] = refresh_cargo_hash(".#buzz-desktop")
    save_hashes(DESKTOP_HASHES_PATH, desktop_data)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="buzz tag to pin, defaults to latest release")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    tag = args.tag or latest_tag()
    update(tag)
    version = tag.removeprefix("v")
    write_output("new_version", version)
    write_output("updated", str(git_has_changes()).lower())


if __name__ == "__main__":
    main()
