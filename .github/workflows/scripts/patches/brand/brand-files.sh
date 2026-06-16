_custom_patch_brand_files() {
    local app_name_xml
    app_name_xml=$(_custom_xml_escape "$CUSTOM_APP_NAME")

    # UI labels on mobile/desktop shells only. Windows exe/MSI identity stays RustDesk.
    _custom_replace_file "flutter/android/app/src/main/res/values/strings.xml" \
        '<string name="app_name">[^<]*</string>' \
        "<string name=\"app_name\">$app_name_xml</string>"

    _custom_replace_file "flutter/android/app/src/main/AndroidManifest.xml" \
        'android:label="RustDesk"' \
        "android:label=\"$app_name_xml\""

    _custom_replace_file "flutter/ios/Runner/Info.plist" \
        '(<key>CFBundleDisplayName</key>[[:space:]]*<string>)[^<]*(</string>)' \
        "\${1}$app_name_xml\${2}"
    _custom_replace_file "flutter/ios/Runner/Info.plist" \
        '(<key>CFBundleName</key>[[:space:]]*<string>)[^<]*(</string>)' \
        "\${1}$app_name_xml\${2}"

    _custom_replace_file_once "res/rustdesk.desktop" '(?m)^Name=.*$' "Name=$CUSTOM_APP_NAME"
    _custom_replace_file_once "res/rustdesk-link.desktop" '(?m)^Name=.*$' "Name=$CUSTOM_APP_NAME"
}
