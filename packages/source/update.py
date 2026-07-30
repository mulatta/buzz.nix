#!/usr/bin/env python3
"""Update the pinned block/buzz release and all source-derived hashes."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tomllib
from collections.abc import Iterable
from pathlib import Path
from typing import Any

REPO_ROOT = Path(__file__).resolve().parents[2]
SOURCE_PIN_PATH = REPO_ROOT / "packages/source/pin.json"
FRONTEND_HASHES_PATH = REPO_ROOT / "packages/build-buzz-frontend/hashes.json"
RUST_HASHES_PATH = REPO_ROOT / "packages/build-buzz-rust/hashes.json"
DESKTOP_HASHES_PATH = REPO_ROOT / "packages/buzz-desktop/hashes.json"
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
GOT_HASH_RE = re.compile(r"got:\s+(sha256-[A-Za-z0-9+/=]+)")
SRI_HASH_RE = re.compile(r"sha256-[A-Za-z0-9+/]{43}=")
SEMVER_TAG_RE = re.compile(
    r"v(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)\."
    r"(?:0|[1-9][0-9]*)"
    r"(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
    r"(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?"
)
SHERPA_ARCHIVE_SUFFIXES = {
    "x86_64-linux": "linux-x64-static-lib.tar.bz2",
    "aarch64-linux": "linux-aarch64-static-lib.tar.bz2",
    "aarch64-darwin": "osx-arm64-static-lib.tar.bz2",
}


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        cmd,
        cwd=REPO_ROOT,
        text=True,
        capture_output=True,
        check=False,
    )
    if check and result.returncode != 0:
        sys.stderr.write(result.stdout)
        sys.stderr.write(result.stderr)
        raise RuntimeError(f"command failed with exit code {result.returncode}: {cmd}")
    return result


def is_release_tag(tag: str) -> bool:
    return SEMVER_TAG_RE.fullmatch(tag) is not None


def require_release_tag(tag: str) -> str:
    if not is_release_tag(tag):
        raise RuntimeError(f"not a v-prefixed semantic-version tag: {tag!r}")
    return tag


def select_release_tag(latest_release: str, fallback_tags: Iterable[str]) -> str:
    if is_release_tag(latest_release):
        return latest_release
    for tag in fallback_tags:
        if is_release_tag(tag):
            return tag
    raise RuntimeError("GitHub returned no v-prefixed semantic-version tag")


def latest_tag() -> str:
    release = run(
        [
            "gh",
            "api",
            "repos/block/buzz/releases/latest",
            "--jq",
            ".tag_name",
        ],
        check=False,
    )
    latest_release = release.stdout.strip() if release.returncode == 0 else ""
    if is_release_tag(latest_release):
        return latest_release

    tags = run(
        [
            "gh",
            "api",
            "--paginate",
            "repos/block/buzz/tags",
            "--jq",
            ".[].name",
        ]
    )
    return select_release_tag(latest_release, tags.stdout.splitlines())


def parse_prefetch_result(output: str) -> tuple[str, Path]:
    data = json.loads(output)
    if not isinstance(data, dict):
        raise RuntimeError("nix store prefetch-file returned non-object JSON")
    hash_value = data.get("hash")
    store_path = data.get("storePath")
    if not isinstance(hash_value, str) or SRI_HASH_RE.fullmatch(hash_value) is None:
        raise RuntimeError("nix store prefetch-file returned an invalid hash")
    if not isinstance(store_path, str):
        raise RuntimeError("nix store prefetch-file returned no store path")
    return hash_value, Path(store_path)


def prefetch_url(url: str, *, unpack: bool = False) -> tuple[str, Path]:
    cmd = ["nix", "store", "prefetch-file", "--json"]
    if unpack:
        cmd.append("--unpack")
    cmd.append(url)
    return parse_prefetch_result(run(cmd).stdout)


def prefetch_source(tag: str) -> tuple[str, Path]:
    url = f"https://github.com/block/buzz/archive/refs/tags/{tag}.tar.gz"
    return prefetch_url(url, unpack=True)


def load_toml(path: Path) -> dict[str, Any]:
    with path.open("rb") as file:
        data = tomllib.load(file)
    if not isinstance(data, dict):
        raise RuntimeError(f"expected a TOML object in {path}")
    return data


def read_package_version(path: Path) -> str:
    package = load_toml(path).get("package")
    if not isinstance(package, dict) or not isinstance(package.get("version"), str):
        raise RuntimeError(f"package.version not found in {path}")
    return package["version"]


def read_rust_version(path: Path) -> str:
    toolchain = load_toml(path).get("toolchain")
    if not isinstance(toolchain, dict) or not isinstance(toolchain.get("channel"), str):
        raise RuntimeError(f"toolchain.channel not found in {path}")
    return toolchain["channel"]


def read_locked_package_version(path: Path, package_name: str) -> str:
    packages = load_toml(path).get("package")
    if not isinstance(packages, list):
        raise RuntimeError(f"package list not found in {path}")
    versions = [
        package.get("version")
        for package in packages
        if isinstance(package, dict) and package.get("name") == package_name
    ]
    if len(versions) != 1 or not isinstance(versions[0], str):
        raise RuntimeError(
            f"expected exactly one {package_name!r} package with a version in {path}"
        )
    return versions[0]


def load_json(path: Path) -> dict[str, Any]:
    data = json.loads(path.read_text())
    if not isinstance(data, dict):
        raise RuntimeError(f"expected a JSON object in {path}")
    return data


def save_json(path: Path, data: dict[str, Any]) -> None:
    path.write_text(json.dumps(data, indent=2) + "\n")


def parse_single_got_hash(output: str) -> str:
    matches = GOT_HASH_RE.findall(output)
    if len(matches) != 1:
        raise RuntimeError(
            f"expected exactly one fixed-output 'got:' hash, found {len(matches)}"
        )
    return matches[0]


def iter_strings(value: Any) -> Iterable[str]:
    if isinstance(value, str):
        yield value
    elif isinstance(value, dict):
        for nested_value in value.values():
            yield from iter_strings(nested_value)
    elif isinstance(value, list):
        for nested_value in value:
            yield from iter_strings(nested_value)


def assert_no_fake_hashes(*objects: dict[str, Any]) -> None:
    count = sum(value == FAKE_HASH for data in objects for value in iter_strings(data))
    if count != 0:
        raise RuntimeError(f"metadata contains {count} unresolved fake hash(es)")


def require_hash(data: dict[str, Any], key: str, path: Path) -> None:
    value = data.get(key)
    if not isinstance(value, str) or SRI_HASH_RE.fullmatch(value) is None:
        raise RuntimeError(f"{key} is missing or invalid in {path}")


def refresh_fixed_output_hash(
    attr: str,
    key: str,
    data: dict[str, Any],
    path: Path,
) -> str:
    assert_no_fake_hashes(data)
    data[key] = FAKE_HASH
    save_json(path, data)

    result = run(["nix", "build", "--no-link", attr], check=False)
    combined = result.stdout + result.stderr
    if result.returncode == 0:
        raise RuntimeError(f"{attr} unexpectedly built with fake {key}")
    try:
        hash_value = parse_single_got_hash(combined)
    except RuntimeError:
        sys.stderr.write(combined)
        raise

    data[key] = hash_value
    save_json(path, data)
    return hash_value


def sherpa_archive_files(version: str) -> dict[str, str]:
    return {
        system: f"sherpa-onnx-v{version}-{suffix}"
        for system, suffix in SHERPA_ARCHIVE_SUFFIXES.items()
    }


def can_reuse_sherpa_metadata(data: dict[str, Any], version: str) -> bool:
    if data.get("version") != version:
        return False
    archives = data.get("archives")
    if not isinstance(archives, dict):
        return False
    expected_files = sherpa_archive_files(version)
    if set(archives) != set(expected_files):
        return False
    for system, expected_file in expected_files.items():
        archive = archives.get(system)
        if not isinstance(archive, dict):
            return False
        hash_value = archive.get("hash")
        if archive.get("file") != expected_file:
            return False
        if not isinstance(hash_value, str) or SRI_HASH_RE.fullmatch(hash_value) is None:
            return False
    return True


def prefetch_sherpa_metadata(version: str) -> dict[str, Any]:
    archives: dict[str, dict[str, str]] = {}
    for system, file_name in sherpa_archive_files(version).items():
        url = (
            "https://github.com/k2-fsa/sherpa-onnx/releases/download/"
            f"v{version}/{file_name}"
        )
        hash_value, _store_path = prefetch_url(url)
        archives[system] = {"file": file_name, "hash": hash_value}
    return {"version": version, "archives": archives}


def resolve_sherpa_metadata(
    current_data: dict[str, Any], version: str
) -> dict[str, Any]:
    if can_reuse_sherpa_metadata(current_data, version):
        return current_data
    return prefetch_sherpa_metadata(version)


def update(
    tag: str,
    *,
    force: bool = False,
    source_pin_path: Path = SOURCE_PIN_PATH,
    frontend_hashes_path: Path = FRONTEND_HASHES_PATH,
    rust_hashes_path: Path = RUST_HASHES_PATH,
    desktop_hashes_path: Path = DESKTOP_HASHES_PATH,
) -> bool:
    tag = require_release_tag(tag)
    source_data = load_json(source_pin_path)
    frontend_data = load_json(frontend_hashes_path)
    rust_data = load_json(rust_hashes_path)
    desktop_data = load_json(desktop_hashes_path)
    metadata = (source_data, frontend_data, rust_data, desktop_data)

    assert_no_fake_hashes(*metadata)
    require_hash(source_data, "hash", source_pin_path)
    require_hash(frontend_data, "pnpmHash", frontend_hashes_path)
    require_hash(rust_data, "cargoHash", rust_hashes_path)
    require_hash(desktop_data, "cargoHash", desktop_hashes_path)

    sherpa_data = desktop_data.get("sherpaOnnx")
    if not isinstance(sherpa_data, dict):
        raise RuntimeError(f"sherpaOnnx is missing or invalid in {desktop_hashes_path}")

    version = tag.removeprefix("v")
    if source_data.get("version") == version and not force:
        return False

    managed_paths = (
        source_pin_path,
        frontend_hashes_path,
        rust_hashes_path,
        desktop_hashes_path,
    )
    originals = {path: path.read_text() for path in managed_paths}

    try:
        source_hash, source_path = prefetch_source(tag)
        relay_version = read_package_version(
            source_path / "crates/buzz-relay/Cargo.toml"
        )
        rust_version = read_rust_version(source_path / "rust-toolchain.toml")
        sherpa_version = read_locked_package_version(
            source_path / "desktop/src-tauri/Cargo.lock",
            "sherpa-onnx-sys",
        )
        desktop_data["sherpaOnnx"] = resolve_sherpa_metadata(
            sherpa_data, sherpa_version
        )

        source_data.update(
            {
                "version": version,
                "relayVersion": relay_version,
                "rustVersion": rust_version,
                "hash": source_hash,
            }
        )
        save_json(source_pin_path, source_data)
        save_json(desktop_hashes_path, desktop_data)

        refresh_fixed_output_hash(
            ".#buzz-cli",
            "cargoHash",
            rust_data,
            rust_hashes_path,
        )
        refresh_fixed_output_hash(
            ".#buzz-web",
            "pnpmHash",
            frontend_data,
            frontend_hashes_path,
        )
        refresh_fixed_output_hash(
            ".#buzz-desktop",
            "cargoHash",
            desktop_data,
            desktop_hashes_path,
        )
        assert_no_fake_hashes(*metadata)
    except BaseException:
        for path, contents in originals.items():
            path.write_text(contents)
        raise

    return any(path.read_text() != originals[path] for path in managed_paths)


def write_output(key: str, value: str) -> None:
    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with Path(github_output).open("a") as file:
            file.write(f"{key}={value}\n")
    else:
        print(f"output: {key}={value}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--tag", help="buzz tag to pin, defaults to latest release")
    parser.add_argument(
        "--force",
        action="store_true",
        help="refresh hashes even when the requested tag is already pinned",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    old_version = load_json(SOURCE_PIN_PATH).get("version")
    if not isinstance(old_version, str):
        raise RuntimeError(f"version is missing or invalid in {SOURCE_PIN_PATH}")

    tag = require_release_tag(args.tag) if args.tag else latest_tag()
    changed = update(tag, force=args.force)
    write_output("old_version", old_version)
    write_output("new_version", tag.removeprefix("v"))
    write_output("updated", str(changed).lower())


if __name__ == "__main__":
    main()
