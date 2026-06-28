_custom_patch_flutter_home_header() {
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"
    local logo_file="flutter/assets/logo.png"

    if [ ! -f "$logo_file" ]; then
        echo "source-patcher: $logo_file missing — apply B02 logo_url before F10" >&2
        return 1
    fi

    if [ -f "$home_file" ]; then
        python3 - "$home_file" "$logo_file" <<'PY'
import base64
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
logo_file = Path(sys.argv[2])
text = path.read_text(encoding="utf-8")
marker = "CUSTOM_RUSTDESK_HOME_HEADER"

if not logo_file.is_file():
    raise SystemExit(f"source-patcher: logo asset missing for F10: {logo_file}")

logo_b64 = base64.b64encode(logo_file.read_bytes()).decode("ascii")
logo_widget = f"""Image.memory(
                    base64Decode('{logo_b64}'),
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                    errorBuilder: (ctx, error, stackTrace) => loadIcon(48),
                  ), // CUSTOM_RUSTDESK_HOME_ICON"""
slogan_widget = """if (bind.mainGetBuildinOption(key: "custom-slogan").isNotEmpty)
                Text(
                  bind.mainGetBuildinOption(key: "custom-slogan"),
                  style: Theme.of(context).textTheme.bodySmall,
                ).marginOnly(top: 2), // CUSTOM_RUSTDESK_HOME_SLOGAN"""

if "import 'dart:convert';" not in text:
    if "import 'dart:async';" in text:
        text = text.replace(
            "import 'dart:async';",
            "import 'dart:async';\nimport 'dart:convert';",
            1,
        )
    else:
        raise SystemExit("source-patcher: cannot inject dart:convert import in desktop_home_page.dart")

text = re.sub(
    r"if \(bind\.isCustomClient\(\)\)\)\s*\n",
    "if (bind.isCustomClient())\n",
    text,
)

custom_block = f"""if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  {logo_widget}
                  Flexible(
                    child: Text(
                      bind.mainGetBuildinOption(key: "app-name"),
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              {slogan_widget}
            ],
          ),
        ), // CUSTOM_RUSTDESK_HOME_HEADER
      if (!bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadLogo(),
        ),"""

legacy_powered = re.compile(
    r"\s*if \(bind\.isCustomClient\(\) &&\s*"
    r"bind\.mainGetBuildinOption\(key: \"hide-powered-by-me\"\) != 'Y'\)\s*"
    r"Align\([\s\S]*?\), // CUSTOM_RUSTDESK_HOME_POWERED\s*",
    re.MULTILINE,
)
if legacy_powered.search(text):
    text = legacy_powered.sub("\n              ", text, count=1)

legacy_home_icon = re.compile(
    r"(?:Image\.memory\([\s\S]*?|Image\.asset\([\s\S]*?|Container\(\s*"
    r"constraints: const BoxConstraints\(maxWidth: 300, maxHeight: 72\),\s*"
    r"child: Image\.asset\([\s\S]*?)"
    r"// CUSTOM_RUSTDESK_HOME_ICON",
    re.MULTILINE,
)

if "CUSTOM_RUSTDESK_HOME_ICON" in text and marker in text:
    if not legacy_home_icon.search(text):
        raise SystemExit("source-patcher: F10 home icon marker found but block shape unexpected")
    text = legacy_home_icon.sub(logo_widget, text, count=1)
    if "CUSTOM_RUSTDESK_HOME_SLOGAN" not in text:
        text = re.sub(
            r"(</Row>,\s*)",
            r"\1\n              " + slogan_widget + "\n",
            text,
            count=1,
        )
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

legacy_custom_block = re.compile(
    r"if \(bind\.isCustomClient\(\)\)\)?\s*"
    r"Align\([\s\S]*?// CUSTOM_RUSTDESK_HOME_HEADER\s*"
    r"(?:if \(!bind\.isCustomClient\(\)\)\s*"
    r"Align\([\s\S]*?loadLogo\(\),\s*\),\s*)?",
    re.MULTILINE,
)
legacy_custom_block_else = re.compile(
    r"if \(bind\.isCustomClient\(\)\)\s*Align\([\s\S]*?// CUSTOM_RUSTDESK_HOME_HEADER\s*"
    r"else \.\.\.\[[\s\S]*?loadLogo\(\),\s*\),\s*\],",
    re.MULTILINE,
)
upstream_block = re.compile(
    r"if \(bind\.isCustomClient\(\)\)\s*"
    r"Align\(\s*alignment: Alignment\.center,\s*"
    r"child: loadPowered\(context\),\s*\),\s*"
    r"Align\(\s*alignment: Alignment\.center,\s*"
    r"child: loadLogo\(\),\s*\),",
    re.MULTILINE,
)

if marker in text or legacy_custom_block.search(text) or legacy_custom_block_else.search(text):
    if legacy_custom_block_else.search(text):
        text = legacy_custom_block_else.sub(custom_block, text, count=1)
    else:
        text = legacy_custom_block.sub(custom_block, text, count=1)
elif upstream_block.search(text):
    text = upstream_block.sub(custom_block, text, count=1)
else:
    raise SystemExit("source-patcher: home header anchor not found in desktop_home_page.dart")

required = (
    marker,
    "CUSTOM_RUSTDESK_HOME_ICON",
    "CUSTOM_RUSTDESK_HOME_SLOGAN",
    "base64Decode(",
    "Image.memory(",
    "loadIcon(48)",
)
forbidden = ("CUSTOM_RUSTDESK_HOME_POWERED", "loadPowered(context)")
missing = [item for item in required if item not in text]
if missing:
    raise SystemExit(
        "source-patcher: failed to inject custom home header in desktop_home_page.dart: "
        + ", ".join(missing)
    )
if any(item in text for item in forbidden):
    raise SystemExit(
        "source-patcher: home header must not include powered-by (connection page only)"
    )

path.write_text(text, encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_HOME_HEADER" "$home_file" &&
           grep -q "CUSTOM_RUSTDESK_HOME_ICON" "$home_file" &&
           grep -q "CUSTOM_RUSTDESK_HOME_SLOGAN" "$home_file" &&
           grep -q "base64Decode" "$home_file" &&
           grep -q "Image.memory" "$home_file" &&
           ! grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$home_file"; then
            echo "source-patcher: custom home header (base64 logo embed) injected in $home_file"
        else
            echo "source-patcher: failed to inject custom home header in $home_file" >&2
            return 1
        fi
    fi
}
