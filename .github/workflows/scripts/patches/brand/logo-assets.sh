_custom_patch_logo_assets() {
    local logo_source="${CUSTOM_LOGO_URL:-}"

    if [ -z "$logo_source" ]; then
        echo "source-patcher: no custom logo configured, skipping icon assets"
        return 0
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local input_image="$work_dir/custom-logo"

    echo "source-patcher: custom logo configured"
    if [[ "$logo_source" =~ ^https?:// ]]; then
        if ! curl -fsSL -A "Custom-RustDesk-Build/1.0" "$logo_source" -o "$input_image"; then
            echo "source-patcher: failed to download logo_url" >&2
            rm -rf "$work_dir"
            return 1
        fi
    elif [ -f "$logo_source" ]; then
        cp "$logo_source" "$input_image"
    elif [ -f "../$logo_source" ]; then
        cp "../$logo_source" "$input_image"
    else
        echo "source-patcher: logo_url is neither a downloadable URL nor an existing file: $logo_source" >&2
        rm -rf "$work_dir"
        return 1
    fi

    if ! python3 - <<'PY' >/dev/null 2>&1
import PIL
PY
    then
        echo "source-patcher: installing Pillow for logo asset generation"
        python3 -m pip install --user pillow
    fi

    python3 - "$input_image" <<'PY'
import json
import os
import re
import sys
from pathlib import Path

from PIL import Image

source = Path(sys.argv[1])
try:
    image = Image.open(source).convert("RGBA")
except Exception as exc:
    raise SystemExit(f"source-patcher: logo image cannot be opened by Pillow: {exc}")

def square_canvas(img, size):
    img.thumbnail((size, size), Image.LANCZOS)
    canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    canvas.alpha_composite(img, ((size - img.width) // 2, (size - img.height) // 2))
    return canvas

def save_png(path, size):
    path.parent.mkdir(parents=True, exist_ok=True)
    square_canvas(image.copy(), size).save(path)

def save_fit_png(path, max_width, max_height):
    path.parent.mkdir(parents=True, exist_ok=True)
    banner = image.copy()
    banner.thumbnail((max_width, max_height), Image.LANCZOS)
    banner.save(path)

for target in (
    Path("flutter/assets/logo.png"),
    Path("flutter/assets/logo_light.png"),
    Path("flutter/assets/logo_dark.png"),
    Path("res/logo.png"),
):
    save_fit_png(target, 300, 60)

for target in (
    Path("flutter/assets/icon.png"),
    Path("res/icon.png"),
):
    save_png(target, 256)

windows_icon = Path("flutter/windows/runner/resources/app_icon.ico")
if windows_icon.exists():
    windows_icon.parent.mkdir(parents=True, exist_ok=True)
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
    square_canvas(image.copy(), 256).save(windows_icon, sizes=sizes)

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
            save_png(target, size)
    stat_logo = base / "ic_stat_logo.png"
    if stat_logo.exists():
        save_png(stat_logo, max(24, size // 2))

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
        save_png(appicon_dir / filename, int(round(points * scale)))

print("source-patcher: custom logo assets generated")
PY

    rm -rf "$work_dir"
}
