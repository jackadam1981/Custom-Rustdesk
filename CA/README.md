# OneCloudDesk Test Code Signing CA

This directory is for local test code-signing material.

Commit public files such as `*.cer` if useful. Do not commit private keys or
PFX bundles. The repository `.gitignore` excludes `CA/private/` and `CA/*.pfx`.

Expected GitHub Secrets for Windows test signing:

- `ONECLOUD_WINDOWS_PFX_BASE64`
- `ONECLOUD_WINDOWS_PFX_PASSWORD`

Generate a local test CA and PFX on Windows:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CA\new-test-code-signing-cert.ps1
```

Then import the generated public root certificate into local trust:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\CA\install-test-ca.ps1
```

The script writes GitHub secret values to `CA/private/github-secrets.txt`.
That directory is intentionally ignored by git.
