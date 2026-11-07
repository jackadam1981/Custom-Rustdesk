_custom_patch_rust_cache_nonfatal() {
    local file=".github/workflows/flutter-build.yml"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping rust-cache nonfatal patch"
        return 0
    fi

    if ! grep -q 'Swatinem/rust-cache' "$file"; then
        echo "source-patcher: no Swatinem/rust-cache step found, skipping rust-cache nonfatal patch"
        return 0
    fi

    local cache_steps patched_steps
    cache_steps="$(grep -c 'Swatinem/rust-cache' "$file" || true)"
    patched_steps="$(awk '
        /Swatinem\/rust-cache/ { saw_cache=1; next }
        saw_cache && /continue-on-error: true/ { count++; saw_cache=0; next }
        saw_cache { saw_cache=0 }
        END { print count+0 }
    ' "$file")"

    if [ "$cache_steps" -eq "$patched_steps" ]; then
        echo "source-patcher: rust-cache nonfatal patch already applied"
        return 0
    fi

    perl -0pi -e 's/^(\s*- uses: Swatinem\/rust-cache@[^\n]*\n)(?!\s+continue-on-error:)/$1        continue-on-error: true\n/gm' "$file"

    echo "source-patcher: marked Swatinem/rust-cache steps as continue-on-error"
}
