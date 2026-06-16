_custom_patch_msi_preprocess_app_name() {
    echo "source-patcher: skipping MSI app-name patch (app_name is UI-only; MSI keeps RustDesk)"
    return 0
}
