_custom_patch_i18n_ui_strings() {
    local customer_name="${CUSTOM_CUSTOMER:-定制客户}"
    local studio_text="由郑州熵能科技工作室为${customer_name}倾情打造。"
    # 非中文语言走 en.rs 回落（src/lang.rs translate_locale 会 fallback 到 en）
    local studio_text_en="Crafted by Zhengzhou Zhengneng Technology Studio for ${customer_name}."
    local powered_by_cn="由${customer_name}提供支持"
    local powered_by_en="Powered by ${customer_name}"
    local studio_text_json powered_by_cn_json powered_by_en_json studio_text_en_json

    studio_text_json=$(_custom_json_string "$studio_text")
    studio_text_en_json=$(_custom_json_string "$studio_text_en")
    powered_by_cn_json=$(_custom_json_string "$powered_by_cn")
    powered_by_en_json=$(_custom_json_string "$powered_by_en")

    if [ -f "src/lang/cn.rs" ]; then
        perl -0pi -e "s/(\(\"powered_by_me\", )\"[^\"]*\"/\1$powered_by_cn_json/" "src/lang/cn.rs"
        if grep -q 'custom_studio_attribution' "src/lang/cn.rs"; then
            perl -0pi -e "s/(\(\"custom_studio_attribution\", )\"[^\"]*\"/\1$studio_text_json/" "src/lang/cn.rs"
        else
            perl -0pi -e "s{(\(\"powered_by_me\", \"[^\"]*\"\),)}{\1\n        (\"custom_studio_attribution\", $studio_text_json),}" "src/lang/cn.rs"
        fi
    fi
    if [ -f "src/lang/en.rs" ]; then
        perl -0pi -e "s/(\(\"powered_by_me\", )\"[^\"]*\"/\1$powered_by_en_json/" "src/lang/en.rs"
        if grep -q 'custom_studio_attribution' "src/lang/en.rs"; then
            perl -0pi -e "s/(\(\"custom_studio_attribution\", )\"[^\"]*\"/\1$studio_text_en_json/" "src/lang/en.rs"
        else
            perl -0pi -e "s{(\(\"powered_by_me\", \"[^\"]*\"\),)}{\1\n        (\"custom_studio_attribution\", $studio_text_en_json),}" "src/lang/en.rs"
        fi
    fi

    # en.rs 是所有非中文语言的回落源；缺 key 会让界面直接显示 key 本身，必须失败而不是静默
    if ! grep -q 'custom_studio_attribution' "src/lang/en.rs" 2>/dev/null; then
        echo "source-patcher: failed to add custom_studio_attribution to src/lang/en.rs" >&2
        return 1
    fi
}
