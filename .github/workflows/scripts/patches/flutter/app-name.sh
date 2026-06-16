_custom_patch_flutter_ui_app_name() {
    local common_file="flutter/lib/common.dart"

    if [ ! -f "$common_file" ]; then
        echo "source-patcher: $common_file not found, skipping UI app-name patch"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_UI_APP_NAME" "$common_file"; then
        echo "source-patcher: UI app-name patch already applied in $common_file"
        return 0
    fi

    python3 - "$common_file" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
old = """String getWindowName({WindowType? overrideType}) {
  final name = bind.mainGetAppNameSync();
"""
new = """String getWindowName({WindowType? overrideType}) {
  // CUSTOM_RUSTDESK_UI_APP_NAME
  var name = bind.mainGetAppNameSync();
  if (bind.isCustomClient()) {
    final customAppName = bind.mainGetBuildinOption(key: "app-name");
    if (customAppName.isNotEmpty) {
      name = customAppName;
    }
  }
"""
if old not in text:
    raise SystemExit(f"source-patcher: getWindowName anchor not found in {path}")
path.write_text(text.replace(old, new, 1), encoding="utf-8")
PY

    if grep -q "CUSTOM_RUSTDESK_UI_APP_NAME" "$common_file"; then
        echo "source-patcher: UI app-name patch applied in $common_file"
    else
        echo "source-patcher: failed to patch UI app-name in $common_file" >&2
        return 1
    fi
}
