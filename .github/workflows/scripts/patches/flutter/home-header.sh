_custom_patch_flutter_home_header() {
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"

    if [ -f "$home_file" ]; then
        python3 - "$home_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "CUSTOM_RUSTDESK_HOME_HEADER"
text = re.sub(
    r"if \(bind\.isCustomClient\(\)\)\)\s*\n",
    "if (bind.isCustomClient())\n",
    text,
)
if "CUSTOM_RUSTDESK_HOME_ICON" in text and marker in text:
    text = re.sub(
        r"Image\.asset\(\s*'assets/icon\.png',[\s\S]*?// CUSTOM_RUSTDESK_HOME_ICON",
        "loadIcon(48), // CUSTOM_RUSTDESK_HOME_ICON",
        text,
        count=1,
    )
    text = re.sub(
        r"\s*if \(bind\.mainGetBuildinOption\(key: \"custom-slogan\"\)\.isNotEmpty\)\s*"
        r"Text\([\s\S]*?// CUSTOM_RUSTDESK_HOME_SLOGAN",
        "",
        text,
    )
    path.write_text(text, encoding="utf-8")
    raise SystemExit(0)

custom_block = """if (bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  loadIcon(48), // CUSTOM_RUSTDESK_HOME_ICON
                  Flexible(
                    child: Text(
                      bind.mainGetBuildinOption(key: "app-name"),
                      style: Theme.of(context).textTheme.titleLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ), // CUSTOM_RUSTDESK_HOME_HEADER
      if (!bind.isCustomClient())
        Align(
          alignment: Alignment.center,
          child: loadLogo(),
        ),"""
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

if marker not in text or "CUSTOM_RUSTDESK_HOME_ICON" not in text:
    raise SystemExit("source-patcher: failed to inject custom home header in desktop_home_page.dart")
path.write_text(text, encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_HOME_HEADER" "$home_file" &&
           grep -q "CUSTOM_RUSTDESK_HOME_ICON" "$home_file"; then
            echo "source-patcher: custom home header injected in $home_file"
        else
            echo "source-patcher: failed to inject custom home header in $home_file" >&2
            return 1
        fi
    fi
}
