#!/usr/bin/env python3
"""Generate ContainerApp/Resources/ThirdPartyNotices.txt.

The app links Apple's `container` client libraries, `containerization` and their
dependencies. Their licenses (Apache 2.0, MIT, BSD, OpenSSL/ISC) require the
license text, and for Apache 2.0 any NOTICE file, to ship with binary
distributions. This script collects them for every package Xcode resolved, plus
the licenses of C/C++ libraries some packages vendor in their sources.

Run after resolving packages (any build does that) and whenever a dependency
changes, then commit the result:

    python3 scripts/generate-third-party-notices.py

Needs network access: two vendored licenses (BoringSSL in swift-nio-ssl, libyaml
in Yams) are not included in their package's checkout and are fetched from
upstream at the vendored revision.
"""

import base64
import json
import re
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
RESOLVED = ROOT / "ContainerApp.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
OUTPUT = ROOT / "ContainerApp/Resources/ThirdPartyNotices.txt"

LICENSE_NAMES = ("LICENSE", "LICENSE.txt", "LICENSE.md", "License")
NOTICE_NAMES = ("NOTICE", "NOTICE.txt", "NOTICE.md", "NOTICES.txt")

# zstd is dual-licensed BSD-3-Clause or GPL-2.0; the app uses it under BSD, so
# only its LICENSE (not COPYING) is reproduced.
LICENSE_OVERRIDES = {"zstd": "LICENSE"}


def checkouts_dir() -> Path:
    """The SourcePackages/checkouts folder of the project's DerivedData."""
    settings = subprocess.run(
        ["xcodebuild", "-scheme", "ContainerApp", "-showBuildSettings"],
        cwd=ROOT, capture_output=True, text=True, check=True,
    ).stdout
    match = re.search(r"^\s*BUILD_DIR = (.+)$", settings, re.MULTILINE)
    if not match:
        sys.exit("error: could not read BUILD_DIR from xcodebuild -showBuildSettings")
    derived = Path(match.group(1)).parent.parent  # …/DerivedData/<project>/Build/Products
    checkouts = derived / "SourcePackages/checkouts"
    if not checkouts.is_dir():
        sys.exit(f"error: {checkouts} not found — build the app once so Xcode resolves packages")
    return checkouts


def fetch(url: str) -> str:
    with urllib.request.urlopen(url, timeout=30) as response:
        return response.read().decode("utf-8")


def boringssl_license(package_dir: Path, vendored_dir: str) -> str:
    """BoringSSL's LICENSE at the revision recorded in the vendored hash.txt."""
    hash_text = (package_dir / "Sources" / vendored_dir / "hash.txt").read_text()
    revision = re.search(r"[0-9a-f]{40}", hash_text).group(0)
    encoded = fetch(f"https://boringssl.googlesource.com/boringssl/+/{revision}/LICENSE?format=TEXT")
    return base64.b64decode(encoded).decode("utf-8")


def tomlplusplus_license(package_dir: Path) -> str:
    """toml++ states its MIT license in the header comment of the amalgamated toml.hpp."""
    header = (package_dir / "Sources/CTomlPlusPlus/toml.hpp").read_text()
    lines = []
    for line in header.splitlines():
        if not line.startswith("//"):
            break
        lines.append(line[2:].strip())
    text = "\n".join(lines)
    start = text.index("MIT License")
    end = text.index("SOFTWARE.", start) + len("SOFTWARE.")
    return text[start:end]


# Licenses of code vendored inside a package's sources and linked into the app.
# Each entry: package identity -> [(title, loader)].
VENDORED = {
    "swift-nio": [
        ("llhttp (vendored as CNIOLLHTTP)",
         lambda d: (d / "Sources/CNIOLLHTTP/LICENSE").read_text()),
    ],
    "swift-nio-ssl": [
        ("BoringSSL (vendored as CNIOBoringSSL)",
         lambda d: boringssl_license(d, "CNIOBoringSSL")),
    ],
    "swift-crypto": [
        ("BoringSSL (vendored as CCryptoBoringSSL)",
         lambda d: boringssl_license(d, "CCryptoBoringSSL")),
    ],
    "yams": [
        ("LibYAML (vendored as CYaml)",
         lambda d: fetch("https://raw.githubusercontent.com/yaml/libyaml/master/License")),
    ],
    "swift-toml": [
        ("toml++ (vendored as CTomlPlusPlus)", tomlplusplus_license),
    ],
}


def first_existing(directory: Path, names) -> Path | None:
    for name in names:
        if (directory / name).is_file():
            return directory / name
    return None


def license_kind(text: str) -> str:
    if "OpenSSL License" in text:
        return "OpenSSL and ISC"
    if "Apache License" in text and "Version 2.0" in text:
        return "Apache-2.0"
    if "Permission is hereby granted, free of charge" in text:
        return "MIT"
    if "Redistribution and use in source and binary forms" in text:
        return "BSD"
    return "see license text"


def section(title: str, body: str) -> str:
    rule = "-" * 78
    return f"{rule}\n{title}\n{rule}\n\n{body.strip()}\n"


def main() -> None:
    if not RESOLVED.is_file():
        sys.exit(f"error: {RESOLVED} not found — run `xcodegen generate` and build once")
    pins = json.loads(RESOLVED.read_text())["pins"]
    checkouts = checkouts_dir()

    # Checkout folders keep the repository's name (e.g. "Yams"), identities are lowercased.
    folders = {p.name.lower(): p for p in checkouts.iterdir() if p.is_dir()}

    parts = [
        "ContainerApp — third-party notices\n"
        "\n"
        "ContainerApp includes the open-source software listed below. Each component is\n"
        "distributed under its own license, reproduced in full together with any NOTICE\n"
        "file the component ships. ContainerApp itself is released under the MIT License.\n"
        "\n"
        "This file is generated by scripts/generate-third-party-notices.py.\n"
    ]
    summary = []

    for pin in sorted(pins, key=lambda p: p["identity"]):
        identity = pin["identity"]
        state = pin["state"]
        version = state.get("version") or state.get("revision", "")[:12]
        location = pin["location"].removesuffix(".git")
        name = Path(location).name
        directory = folders.get(name.lower()) or folders.get(identity)
        if directory is None:
            sys.exit(f"error: no checkout for {identity} in {checkouts}")

        license_path = (directory / LICENSE_OVERRIDES[identity]) if identity in LICENSE_OVERRIDES \
            else first_existing(directory, LICENSE_NAMES)
        if license_path is None:
            sys.exit(f"error: no license file found for {identity} in {directory}")
        license_text = license_path.read_text()
        kind = license_kind(license_text)

        body = [f"{location} — version {version}\nLicense: {kind}\n", license_text.strip()]
        notice_path = first_existing(directory, NOTICE_NAMES)
        if notice_path is not None:
            body.append(f"\n{notice_path.name}:\n\n{notice_path.read_text().strip()}")
        parts.append(section(f"{name} {version}", "\n".join(body)))
        summary.append(f"  {name} {version} ({kind})")

        for title, loader in VENDORED.get(identity, []):
            text = loader(directory)
            parts.append(section(f"{title} — included in {name}", text))
            summary.append(f"    + {title} ({license_kind(text)})")

    OUTPUT.write_text("\n".join(parts))
    print(f"Wrote {OUTPUT.relative_to(ROOT)} with {len(pins)} packages:")
    print("\n".join(summary))


if __name__ == "__main__":
    main()
