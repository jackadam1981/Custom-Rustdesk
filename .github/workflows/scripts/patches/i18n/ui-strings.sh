_custom_patch_i18n_ui_strings() {
    local customer_name="${CUSTOM_CUSTOMER:-定制客户}"
    local studio_text="由郑州熵能科技工作室为${customer_name}倾情打造。"
    local powered_by_cn="由${customer_name}提供支持"
    local powered_by_en="Powered by ${customer_name}"
    local studio_text_json powered_by_cn_json powered_by_en_json

    studio_text_json=$(_custom_json_string "$studio_text")
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
            perl -0pi -e "s/(\(\"custom_studio_attribution\", )\"[^\"]*\"/\1$studio_text_json/" "src/lang/en.rs"
        else
            perl -0pi -e "s{(\(\"powered_by_me\", \"[^\"]*\"\),)}{\1\n        (\"custom_studio_attribution\", $studio_text_json),}" "src/lang/en.rs"
        fi
    fi
}
