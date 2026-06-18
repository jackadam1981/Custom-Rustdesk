# Source all patch modules in dependency order.
PATCH_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=patches/lib/common.sh
source "$PATCH_DIR/lib/common.sh"
# shellcheck source=patches/lib/sciter-brand.sh
source "$PATCH_DIR/lib/sciter-brand.sh"
# shellcheck source=patches/manifest.sh
source "$PATCH_DIR/manifest.sh"
# shellcheck source=patches/core/r01.sh
source "$PATCH_DIR/core/r01.sh"
# shellcheck source=patches/core/is-custom-client.sh
source "$PATCH_DIR/core/is-custom-client.sh"
# shellcheck source=patches/brand/brand-files.sh
source "$PATCH_DIR/brand/brand-files.sh"
# shellcheck source=patches/brand/logo-assets.sh
source "$PATCH_DIR/brand/logo-assets.sh"
# shellcheck source=patches/i18n/ui-strings.sh
source "$PATCH_DIR/i18n/ui-strings.sh"
# shellcheck source=patches/flutter/app-name.sh
source "$PATCH_DIR/flutter/app-name.sh"
# shellcheck source=patches/flutter/home-header.sh
source "$PATCH_DIR/flutter/home-header.sh"
# shellcheck source=patches/flutter/powered-by.sh
source "$PATCH_DIR/flutter/powered-by.sh"
# shellcheck source=patches/flutter/about-studio.sh
source "$PATCH_DIR/flutter/about-studio.sh"
# shellcheck source=patches/sciter/home-ui.sh
source "$PATCH_DIR/sciter/home-ui.sh"
# shellcheck source=patches/sciter/about-studio.sh
source "$PATCH_DIR/sciter/about-studio.sh"
# shellcheck source=patches/sciter/config-menu-css.sh
source "$PATCH_DIR/sciter/config-menu-css.sh"
# shellcheck source=patches/platform/portable-workdir.sh
source "$PATCH_DIR/platform/portable-workdir.sh"
# shellcheck source=patches/platform/windows-signing.sh
source "$PATCH_DIR/platform/windows-signing.sh"
# shellcheck source=patches/platform/msi-noop.sh
source "$PATCH_DIR/platform/msi-noop.sh"
# shellcheck source=patches/platform/rust-cache-nonfatal.sh
source "$PATCH_DIR/platform/rust-cache-nonfatal.sh"
# shellcheck source=patches/orchestrator.sh
source "$PATCH_DIR/orchestrator.sh"
