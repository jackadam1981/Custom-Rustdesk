_custom_patch_flutter_powered_by() {
    local home_file="flutter/lib/desktop/pages/desktop_home_page.dart"

    if [ -f "$home_file" ] && grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$home_file"; then
        perl -0pi -e 's/\n\s*if \(bind\.isCustomClient\(\) && bind\.mainGetBuildinOption\(key: "hide-powered-by-me"\) != '\''Y'\''\)\n\s*GestureDetector\([\s\S]*?\)\.marginOnly\(top: 4\), \/\/ CUSTOM_RUSTDESK_HOME_POWERED//g' "$home_file"
        perl -0pi -e 's/\n\s*if \(bind\.isCustomClient\(\)\)\s*Align\([\s\S]*?loadPowered\(context\),[\s\S]*?\/\/ CUSTOM_RUSTDESK_HOME_POWERED\s*\n//g' "$home_file"
        echo "source-patcher: removed misplaced customer powered_by from $home_file"
    fi

    local connection_file="flutter/lib/desktop/pages/connection_page.dart"
    if [ -f "$connection_file" ]; then
        python3 - "$connection_file" <<'PY'
import re
import sys
from pathlib import Path

path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
marker = "CUSTOM_RUSTDESK_HOME_POWERED"

powered_block = """          if (bind.isCustomClient() &&
              bind.mainGetBuildinOption(key: "hide-powered-by-me") != 'Y')
            Align(
              alignment: Alignment.centerLeft,
              child: loadPowered(context),
            ).paddingOnly(bottom: 8), // CUSTOM_RUSTDESK_HOME_POWERED
"""

# Drop legacy in-card placement (above getConnectionPageTitle).
text = re.sub(
    r"\s*if \(bind\.isCustomClient\(\)\)\s*"
    r"Align\(\s*alignment: Alignment\.centerLeft,\s*"
    r"child: loadPowered\(context\),\s*"
    r"\)\.paddingOnly\(left: 12, top: 12\), // CUSTOM_RUSTDESK_HOME_POWERED\s*\n",
    "\n",
    text,
)
text = re.sub(
    r"\s*if \(bind\.isCustomClient\(\) &&\s*"
    r'bind\.mainGetBuildinOption\(key: "hide-powered-by-me"\) != \'Y\'\)\s*'
    r"Align\([\s\S]*?// CUSTOM_RUSTDESK_HOME_POWERED\s*\n",
    "\n",
    text,
)

return_pat = re.compile(
    r"return Container\(\s*"
    r"constraints: const BoxConstraints\(maxWidth: 600\),\s*child: w\);\s*",
    re.MULTILINE,
)
return_with_column = re.compile(
    r"return Container\(\s*"
    r"constraints: const BoxConstraints\(maxWidth: 600\),\s*"
    r"child: Column\(\s*"
    r"crossAxisAlignment: CrossAxisAlignment\.stretch,\s*"
    r"children: \[\s*"
    r"[\s\S]*?// CUSTOM_RUSTDESK_HOME_POWERED\s*"
    r"w,\s*"
    r"\],\s*"
    r"\),\s*"
    r"\);\s*",
    re.MULTILINE,
)
return_with_powered = (
    "return Container(\n"
    "      constraints: const BoxConstraints(maxWidth: 600),\n"
    "      child: Column(\n"
    "        crossAxisAlignment: CrossAxisAlignment.stretch,\n"
    "        children: [\n"
    f"{powered_block}"
    "          w,\n"
    "        ],\n"
    "      ),\n"
    "    );"
)

if return_with_column.search(text):
    pass
elif return_pat.search(text):
    text = return_pat.sub(return_with_powered, text, count=1)
elif marker not in text:
    raise SystemExit(
        "source-patcher: _buildRemoteIDTextField return anchor not found in connection_page.dart"
    )

if marker not in text:
    raise SystemExit(
        "source-patcher: failed to inject customer powered_by in connection_page.dart"
    )

path.write_text(text, encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_HOME_POWERED" "$connection_file"; then
            echo "source-patcher: customer powered_by injected above Control Remote Desktop card in $connection_file"
        else
            echo "source-patcher: failed to inject customer powered_by in $connection_file" >&2
            return 1
        fi
    fi

    local common_file="flutter/lib/common.dart"
    if [ -f "$common_file" ]; then
        python3 - "$common_file" <<'PY'
import re
import sys
from pathlib import Path

SIGNATURE = "Widget loadPowered(BuildContext context)"
OLD_CHILD = """      child: Opacity(
          opacity: 0.5,
          child: Text(
            translate("powered_by_me"),
            overflow: TextOverflow.clip,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
          )),"""
NEW_CHILD = """      child: bind.isCustomClient()
          ? Text(
              translate("powered_by_me"),
              overflow: TextOverflow.clip,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  decoration: TextDecoration.underline,
                  height: 1), // CUSTOM_RUSTDESK_POWERED_STYLE
            )
          : Opacity(
              opacity: 0.5,
              child: Text(
                translate("powered_by_me"),
                overflow: TextOverflow.clip,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
              )),"""
PREVIOUS_CUSTOM_CHILD = """      child: bind.isCustomClient()
          ? Text(
              translate("powered_by_me"),
              overflow: TextOverflow.clip,
              style: const TextStyle(
                  fontSize: 14,
                  color: Colors.black,
                  decoration: TextDecoration.underline),
            )
          : Opacity(
              opacity: 0.5,
              child: Text(
                translate("powered_by_me"),
                overflow: TextOverflow.clip,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(fontSize: 9, decoration: TextDecoration.underline),
              )),"""
PARTIAL_CHILD = """      child: Opacity(
          opacity: 0.5,
          child: Text(
            translate("powered_by_me"),
            overflow: TextOverflow.clip,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(fontSize: bind.isCustomClient() ? 12 : 9,
                    decoration: TextDecoration.underline),
          )),"""
LAUNCH_PATTERNS = (
    "launchUrl(Uri.parse('https://rustdesk.com'));",
    'launchUrl(Uri.parse("https://rustdesk.com"));',
    "launchUrlString('https://rustdesk.com');",
    'launchUrlString("https://rustdesk.com");',
)
NEW_LAUNCH = (
    "final poweredLink = bind.isCustomClient()\n"
    '              ? bind.mainGetBuildinOption(key: "custom-customer-link")\n'
    '              : "https://rustdesk.com";\n'
    "          if (poweredLink.isNotEmpty) launchUrl(Uri.parse(poweredLink)); // CUSTOM_RUSTDESK_POWERED_LINK"
)


def extract_function(text, signature):
    start = text.find(signature)
    if start == -1:
        return None
    brace = text.find("{", start + len(signature))
    if brace == -1:
        return None
    depth = 0
    for index in range(brace, len(text)):
        char = text[index]
        if char == "{":
            depth += 1
        elif char == "}":
            depth -= 1
            if depth == 0:
                return start, index + 1
    return None


path = Path(sys.argv[1])
text = path.read_text(encoding="utf-8")
span = extract_function(text, SIGNATURE)
if span is None:
    raise SystemExit("source-patcher: loadPowered function not found in common.dart")

start, end = span
function_text = text[start:end]
changed = False

if "CUSTOM_RUSTDESK_POWERED_LINK" not in function_text:
    old_launch = next((item for item in LAUNCH_PATTERNS if item in function_text), None)
    if old_launch is None:
        raise SystemExit("source-patcher: loadPowered launchUrl pattern not found in common.dart")
    function_text = function_text.replace(old_launch, NEW_LAUNCH, 1)
    changed = True

if NEW_CHILD not in function_text:
    if OLD_CHILD in function_text:
        function_text = function_text.replace(OLD_CHILD, NEW_CHILD, 1)
        changed = True
    elif PREVIOUS_CUSTOM_CHILD in function_text:
        function_text = function_text.replace(PREVIOUS_CUSTOM_CHILD, NEW_CHILD, 1)
        changed = True
    elif PARTIAL_CHILD in function_text:
        function_text = function_text.replace(PARTIAL_CHILD, NEW_CHILD, 1)
        changed = True
    elif "CUSTOM_RUSTDESK_POWERED_STYLE" in function_text:
        pass
    else:
        raise SystemExit("source-patcher: loadPowered style pattern not found in common.dart")

if changed:
    path.write_text(text[:start] + function_text + text[end:], encoding="utf-8")
PY
        if grep -q "CUSTOM_RUSTDESK_POWERED_LINK" "$common_file" &&
           grep -q "CUSTOM_RUSTDESK_POWERED_STYLE" "$common_file"; then
            echo "source-patcher: custom powered_by link and style wired in $common_file"
        else
            echo "source-patcher: failed to patch powered_by in $common_file" >&2
            return 1
        fi
    fi
}
