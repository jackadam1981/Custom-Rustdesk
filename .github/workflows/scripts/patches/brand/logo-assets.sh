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
    local logo_source="${CUSTOM_LOGO_URL:-}"
    local icon_source="${CUSTOM_ICON_URL:-}"

    if [ -z "$banner_source" ] && [ -z "$logo_source" ] && [ -z "$icon_source" ]; then
        echo "source-patcher: no banner_url/logo_url/icon_url configured, skipping logo assets"
        return 0
    fi

    local work_dir
    work_dir=$(mktemp -d)
    local banner_input=""
    local logo_input=""
    local icon_input=""

    if [ -n "$banner_source" ]; then
        banner_input="$work_dir/custom-banner"
        echo "source-patcher: banner_url configured"
        if ! _custom_fetch_image_source "$banner_source" "$banner_input"; then
            rm -rf "$work_dir"
            return 1
        fi
    fi

    if [ -n "$logo_source" ]; then
        logo_input="$work_dir/custom-logo"
        echo "source-patcher: logo_url configured"
        if ! _custom_fetch_image_source "$logo_source" "$logo_input"; then
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

    python3 - "$banner_input" "$logo_input" "$icon_input" <<'PY'
import json
import re
import sys
from pathlib import Path

from PIL import Image

banner_path = Path(sys.argv[1]) if sys.argv[1] else None
logo_path = Path(sys.argv[2]) if sys.argv[2] else None
icon_path = Path(sys.argv[3]) if sys.argv[3] else None

HOME_LOGO_SQUARE = 72
ICON_ONLY_HOME_LOGO = 72
BANNER_MAX = (300, 60)
# ratio >= WIDE_BANNER_RATIO → 300×60 横幅；否则按方图处理（避免方图压进 60px 高几乎看不见）
WIDE_BANNER_RATIO = 1.5

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
    fitted = img.copy()
    fitted.thumbnail((max_width, max_height), Image.LANCZOS)
    fitted.save(path)

def aspect_ratio(img: Image.Image) -> float:
    w, h = img.size
    return w / h if h else 1.0

def is_wide_banner(img: Image.Image) -> bool:
    return aspect_ratio(img) >= WIDE_BANNER_RATIO

def write_home_logo_square(img: Image.Image) -> None:
    for target in (
        Path("flutter/assets/logo.png"),
        Path("res/logo.png"),
    ):
        save_png(target, img, HOME_LOGO_SQUARE)

def write_wide_banner_assets(img: Image.Image) -> None:
    for target in (
        Path("flutter/assets/banner.png"),
        Path("res/banner.png"),
    ):
        save_fit_png(target, img, *BANNER_MAX)
    for target in (
        Path("flutter/assets/logo_light.png"),
        Path("flutter/assets/logo_dark.png"),
    ):
        save_fit_png(target, img, *BANNER_MAX)

def write_home_logo_wide(img: Image.Image) -> None:
    for target in (
        Path("flutter/assets/logo.png"),
        Path("res/logo.png"),
    ):
        save_fit_png(target, img, *BANNER_MAX)

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

def write_platform_icons(icon: Image.Image) -> None:
    windows_icon = Path("flutter/windows/runner/resources/app_icon.ico")
    if windows_icon.parent.exists():
        save_ico(windows_icon, icon)

    save_ico(Path("res/tray-icon.ico"), icon)

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

if banner_path and banner_path.is_file():
    banner = open_image(banner_path)
    ratio = aspect_ratio(banner)
    if is_wide_banner(banner):
        write_wide_banner_assets(banner)
        print(
            f"source-patcher: banner_url -> banner.png + logo_light/dark "
            f"(300x60 fit, ratio={ratio:.2f})"
        )
    else:
        write_home_logo_square(banner)
        for target in (
            Path("flutter/assets/banner.png"),
            Path("res/banner.png"),
            Path("flutter/assets/logo_light.png"),
            Path("flutter/assets/logo_dark.png"),
        ):
            save_png(target, banner, HOME_LOGO_SQUARE)
        print(
            f"source-patcher: banner_url square/portrait (ratio={ratio:.2f}) "
            f"-> logo assets {HOME_LOGO_SQUARE}px square (use logo_url for home row)"
        )

if logo_path and logo_path.is_file():
    logo = open_image(logo_path)
    write_home_logo_square(logo)
    print(f"source-patcher: logo_url -> logo.png ({HOME_LOGO_SQUARE}px square, home row)")
elif banner_path and banner_path.is_file():
    banner = open_image(banner_path)
    if is_wide_banner(banner):
        write_home_logo_wide(banner)
        print("source-patcher: banner_url -> logo.png (300x60 fit, no logo_url)")

if icon_path and icon_path.is_file():
    icon = open_image(icon_path)
    for target in (
        Path("flutter/assets/icon.png"),
        Path("res/icon.png"),
    ):
        save_png(target, icon, 256)

    if not (logo_path and logo_path.is_file()) and not (banner_path and banner_path.is_file()):
        for target in (
            Path("flutter/assets/logo.png"),
            Path("res/logo.png"),
        ):
            save_png(target, icon, ICON_ONLY_HOME_LOGO)
        print(
            f"source-patcher: icon_url only -> logo.png ({ICON_ONLY_HOME_LOGO}px square fallback)"
        )

    write_platform_icons(icon)
    print("source-patcher: icon_url -> icon.png (256 square + tray/app icons)")
PY

    rm -rf "$work_dir"
}
