#!/bin/bash
# Resolve VERSION from the [package] version in the upstream Cargo.toml that is being built.
#
# The vendored flutter-build.yml used to pin VERSION: "1.4.9", but the packaged artifacts
# take their version from Cargo.toml (deb/rpm). Every filename that env.VERSION builds then
# drifted from the real package version, which made
#   - appimage/flatpak fail with "Artifact not found for name: rustdesk-1.4.9-<arch>.deb",
#   - the upload step warn "No files were found with the provided path: rustdesk-1.4.9-...",
#   - the archlinux publish pattern "res/rustdesk-1.4.9*.zst" match nothing.
#
# This script derives the value from the source tree that is actually being built and exports
# it to later steps via $GITHUB_ENV. It never falls back to a hardcoded value: a missing or
# unparsable version is a hard error.

set -euo pipefail

cargo_toml="${1:-Cargo.toml}"

if [ ! -f "$cargo_toml" ]; then
    echo "::error::Cargo.toml not found at $cargo_toml; cannot resolve VERSION from its [package] section"
    exit 1
fi

version="$(awk '
    /^\[/ { in_package = ($0 ~ /^\[package\][[:space:]]*$/) }
    in_package && /^[[:space:]]*version[[:space:]]*=/ {
        line = $0
        sub(/^[^=]*=[[:space:]]*/, "", line)
        gsub(/["\r[:space:]]/, "", line)
        print line
        exit
    }
' "$cargo_toml")"

if [ -z "$version" ]; then
    echo "::error::$cargo_toml declares no version in its [package] section"
    exit 1
fi

if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+([-.][0-9A-Za-z.]+)?$ ]]; then
    echo "::error::Cargo.toml package version is not a numeric version: $version"
    exit 1
fi

echo "VERSION=$version" >> "$GITHUB_ENV"
echo "✅ VERSION resolved from $cargo_toml: $version"
