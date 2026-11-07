_custom_patch_portable_working_dir() {
    local file="libs/portable/src/main.rs"

    if [ ! -f "$file" ]; then
        echo "source-patcher: $file not found, skipping portable working directory patch"
        return 0
    fi

    if grep -q "CUSTOM_RUSTDESK_PORTABLE_WORKDIR_PATCH" "$file"; then
        echo "source-patcher: portable working directory already patched"
        return 0
    fi

    perl -0pi -e 's{let mut cmd = Command::new\(path\);\n}{// CUSTOM_RUSTDESK_PORTABLE_WORKDIR_PATCH\n    let current_dir = path.parent().map(|dir| dir.to_path_buf());\n    let mut cmd = Command::new(path);\n}' "$file"
    perl -0pi -e 's{cmd\.args\(args\);\n}{cmd.args(args);\n    if let Some(dir) = current_dir {\n        cmd.current_dir(dir);\n    }\n}' "$file"
}
