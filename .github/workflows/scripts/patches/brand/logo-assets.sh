_custom_fetch_image_source() {
    local source="$1"
    local dest="$2"

    if [ -z "$source" ]; then
        return 1
    fi

    if [[ "$source" =~ ^https?:// ]]; then
        if ! curl -fsSL -A "Custom-RustDesk-Build/1.0" "$source" -o "$dest"; then
            echo "source-patcher: failed to download image: $source" >&2
            return 1
        fi
        return 0
    fi

    local resolved=""
    if [ -f "$source" ]; then
        resolved="$source"
    elif [ -f "../$source" ]; then
        resolved="../$source"
    else
        local repo_root=""
        if [ -n "${CUSTOM_RUSTDESK_REPO:-}" ] && [ -d "${CUSTOM_RUSTDESK_REPO}" ]; then
            repo_root="${CUSTOM_RUSTDESK_REPO}"
        elif [ -n "${GITHUB_WORKSPACE:-}" ] && [ -d "${GITHUB_WORKSPACE}" ]; then
            repo_root="${GITHUB_WORKSPACE}"
        fi

        if [ -n "$repo_root" ]; then
            local stripped="${source#./}"
            stripped="${stripped#../}"
            for candidate in \
                "$repo_root/$source" \
                "$repo_root/$stripped" \
                "$repo_root/branding/$(basename "$source")"; do
                if [ -f "$candidate" ]; then
                    resolved="$candidate"
                    break
                fi
            done
        fi
    fi

    if [ -z "$resolved" ] || [ ! -f "$resolved" ]; then
        echo "source-patcher: image source is neither a URL nor a file: $source" >&2
        return 1
    fi

    cp "$resolved" "$dest"
}

_custom_patch_logo_assets() {
    local banner_source="${CUSTOM_BANNER_URL:-}"
    local icon_source="${CUSTOM_ICON_URL:-}"

    if [ -z "$banner_source" ] && [ -z "$icon_source" ]; then
        echo "source-patcher: no banner_url/icon_url configured, skipping logo assets"
        return 0
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local banner_input=""
    local icon_input=""

    if [ -n "$banner_source" ]; then
        banner_input="$work_dir/custom-banner"
        echo "source-patcher: banner_url configured"
        if ! _custom_fetch_image_source "$banner_source" "$banner_input"; then
            rm -rf "$work_dir"
            return 1
        fi
    fi

    if [ -n "$icon_source" ]; then
        icon_input="$work_dir/custom-icon"
        echo "source-patcher: icon_url configured"
        if ! _custom_fetch_image_source "$icon_source" "$icon_input"; then
            rm -rf "$work_dir"
            return 1
        fi
    fi

    if ! python3 - <<'PY' >/dev/null 2>&1
import PIL
PY
    then
        echo "source-patcher: installing Pillow for logo asset generation"
        python3 -m pip install --user pillow
    fi

    python3 - "$banner_input" "$icon_input" <<'PY'
import json
import re
import sys
from pathlib import Path

from PIL import Image

banner_path = Path(sys.argv[1]) if sys.argv[1] else None
icon_path = Path(sys.argv[2]) if sys.argv[2] else None

def open_image(path: Path) -> Image.Image:
    try:
        return Image.open(path).convert("RGBA")
    except Exception as exc:
        raise SystemExit(f"source-patcher: image cannot be opened by Pillow ({path}): {exc}")

def square_canvas(img: Image.Image, size: int) -> Image.Image:
    img = img.copy()
    img.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(img, ((size - img.width) // 2, (size - img.height) // 2))
    return canvas

def save_png(path: Path, img: Image.Image, size: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    square_canvas(img, size).save(path)

def save_fit_png(path: Path, img: Image.Image, max_width: int, max_height: int) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    banner = img.copy()
    banner.thumbnail((max_width, max_height), Image.LANCZOS)
    banner.save(path)

def save_ico(path: Path, img: Image.Image) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sizes = [
        (16, 16),
        (20, 20),
        (24, 24),
        (32, 32),
        (40, 40),
        (48, 48),
        (64, 64),
        (128, 128),
        (256, 256),
    ]
    square_canvas(img, 256).save(path, sizes=sizes)

if banner_path and banner_path.is_file():
    banner = open_image(banner_path)
    for target in (
        Path("flutter/assets/logo.png"),
        Path("flutter/assets/logo_light.png"),
        Path("flutter/assets/logo_dark.png"),
        Path("res/logo.png"),
    ):
        save_fit_png(target, banner, 300, 60)
    print("source-patcher: banner assets generated (300x60 fit)")

if icon_path and icon_path.is_file():
    icon = open_image(icon_path)
    for target in (
        Path("flutter/assets/icon.png"),
        Path("res/icon.png"),
    ):
        save_png(target, icon, 256)

    home_only = not (banner_path and banner_path.is_file())
    if home_only:
        print("source-patcher: icon assets generated (home header only, no tray/app ico)")
    else:
        windows_icon = Path("flutter/windows/runner/resources/app_icon.ico")
        if windows_icon.parent.exists():
            save_ico(windows_icon, icon)

        tray_icon = Path("res/tray-icon.ico")
        save_ico(tray_icon, icon)

        android_sizes = {
            "mipmap-mdpi": 48,
            "mipmap-hdpi": 72,
            "mipmap-xhdpi": 96,
            "mipmap-xxhdpi": 144,
            "mipmap-xxxhdpi": 192,
        }
        for folder, size in android_sizes.items():
            base = Path("flutter/android/app/src/main/res") / folder
            for name in ("ic_launcher.png", "ic_launcher_round.png", "ic_launcher_foreground.png"):
                target = base / name
                if target.exists():
                    save_png(target, icon, size)
            stat_logo = base / "ic_stat_logo.png"
            if stat_logo.exists():
                save_png(stat_logo, icon, max(24, size // 2))

        appicon_dir = Path("flutter/ios/Runner/Assets.xcassets/AppIcon.appiconset")
        contents = appicon_dir / "Contents.json"
        if contents.exists():
            data = json.loads(contents.read_text(encoding="utf-8"))
            for entry in data.get("images", []):
                filename = entry.get("filename")
                size_text = entry.get("size", "")
                scale_text = entry.get("scale", "1x")
                if not filename or "x" not in size_text:
                    continue
                points = float(size_text.split("x", 1)[0])
                scale = int(re.sub(r"\D", "", scale_text) or "1")
                save_png(appicon_dir / filename, icon, int(round(points * scale)))

        print("source-patcher: icon assets generated (256 square + tray/app icons)")
PY

    rm -rf "$work_dir"
}
