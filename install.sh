#!/bin/sh
# gmux installer: https://get.wandpod.com/gmux
# Env: GMUX_VERSION (default latest), GMUX_INSTALL_DIR (default /usr/local/bin),
# GMUX_SHARE_DIR, GMUX_COMPLETION_INSTALL (1 force, 0 skip), GMUX_SHELL.
set -e

BASE="${GMUX_DOWNLOAD_BASE:-https://get.wandpod.com/gmux}"
INSTALL_DIR="${GMUX_INSTALL_DIR:-/usr/local/bin}"
PREFIX=$(dirname "$INSTALL_DIR")
SHARE_DIR="${GMUX_SHARE_DIR:-${PREFIX}/share}"

die() {
    echo "gmux install: $*" >&2
    exit 1
}

# fetch URL DEST: download or name the URL that failed.
fetch() {
    status=$(curl -sSL -o "$2" -w '%{http_code}' "$1") || die "cannot reach $1"
    [ "$status" = 200 ] || die "HTTP $status for $1"
}

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
case "$OS" in
    linux|darwin) ;;
    *) die "unsupported OS: $OS (Windows: use the release .tar.gz from github.com/wandpod/gmux)" ;;
esac
ARCH=$(uname -m)
case "$ARCH" in
    x86_64|amd64) ARCH="amd64" ;;
    aarch64|arm64) ARCH="arm64" ;;
    armv6l|armv7l|armv7|armhf|arm) ARCH="arm" ;;
    *) die "unsupported architecture: $ARCH" ;;
esac

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' 0

VERSION="${GMUX_VERSION:-}"
if [ -z "$VERSION" ]; then
    fetch "${BASE}/version" "${TMP}/version"
    VERSION=$(tr -d ' \r\n' < "${TMP}/version")
fi
VERSION="${VERSION#v}"
[ -n "$VERSION" ] || die "empty version from ${BASE}/version"

ARCHIVE="gmux-${OS}-${ARCH}.tar.gz"
echo "Installing gmux ${VERSION} (${OS}/${ARCH})..."
fetch "${BASE}/${VERSION}/${ARCHIVE}" "${TMP}/${ARCHIVE}"
tar xzf "${TMP}/${ARCHIVE}" -C "$TMP"

# Rename, never overwrite: macOS kills the next exec of a rewritten running binary.
install_file() {
    source=$1
    destination=$2
    mode=$3
    destination_dir=$(dirname "$destination")
    staged="${destination}.tmp.$$"

    if mkdir -p "$destination_dir" 2>/dev/null && [ -w "$destination_dir" ]; then
        cp "$source" "$staged"
        chmod "$mode" "$staged"
        mv -f "$staged" "$destination"
    else
        sudo mkdir -p "$destination_dir"
        sudo cp "$source" "$staged"
        sudo chmod "$mode" "$staged"
        sudo mv -f "$staged" "$destination"
    fi
}

install_file "${TMP}/gmux" "${INSTALL_DIR}/gmux" 755

BUNDLE="gmux-agent-binaries.tar.gz"
fetch "${BASE}/${VERSION}/${BUNDLE}" "${TMP}/${BUNDLE}"
AGENT_DIR="${PREFIX}/lib/gmux"
if mkdir -p "$AGENT_DIR" 2>/dev/null && [ -w "$AGENT_DIR" ]; then
    tar xzf "${TMP}/${BUNDLE}" -C "$AGENT_DIR"
else
    sudo mkdir -p "$AGENT_DIR"
    sudo tar xzf "${TMP}/${BUNDLE}" -C "$AGENT_DIR"
fi
install_file "${TMP}/completions/gmux.bash" "${SHARE_DIR}/bash-completion/completions/gmux" 644
install_file "${TMP}/completions/_gmux" "${SHARE_DIR}/zsh/site-functions/_gmux" 644
install_file "${TMP}/completions/gmux.fish" "${SHARE_DIR}/fish/vendor_completions.d/gmux.fish" 644
install_file "${TMP}/completions/gmux.nu" "${SHARE_DIR}/nushell/vendor/autoload/gmux.nu" 644
install_file "${TMP}/completions/gmux.ps1" "${SHARE_DIR}/gmux/completions/gmux.ps1" 644
install_file "${TMP}/LICENSE" "${SHARE_DIR}/licenses/gmux/LICENSE" 644
install_file "${TMP}/THIRD_PARTY_NOTICES" "${SHARE_DIR}/licenses/gmux/THIRD_PARTY_NOTICES" 644

detect_completion_shell() {
    completion_shell=${GMUX_SHELL:-}
    if [ -z "$completion_shell" ]; then
        if [ -n "${PSModulePath:-}" ]; then
            completion_shell=powershell
        else
            completion_shell=${SHELL:-}
        fi
    fi

    completion_shell=${completion_shell##*/}
    completion_shell=$(printf '%s' "$completion_shell" | tr '[:upper:]' '[:lower:]')
    completion_shell=${completion_shell%.exe}
    case "$completion_shell" in
        bash|zsh|fish) printf '%s\n' "$completion_shell" ;;
        pwsh|powershell) printf '%s\n' powershell ;;
        nu|nushell) printf '%s\n' nushell ;;
        *) return 1 ;;
    esac
}

activate_completion() {
    if [ "${GMUX_COMPLETION_INSTALL:-}" = 0 ]; then
        return
    fi

    if completion_shell=$(detect_completion_shell); then
        :
    else
        if [ "${GMUX_COMPLETION_INSTALL:-}" = 1 ]; then
            echo "Warning: could not detect a shell for completion activation." >&2
        fi
        return
    fi

    if [ "${GMUX_COMPLETION_INSTALL:-}" != 1 ]; then
        if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
            return
        fi
        if ! printf 'Install %s completion for your user? [Y/n] ' "$completion_shell" 2>/dev/null > /dev/tty; then
            return
        fi
        if ! IFS= read -r response 2>/dev/null < /dev/tty; then
            return
        fi
        case "$response" in
            ""|[Yy]|[Yy][Ee][Ss]) ;;
            *) return ;;
        esac
    fi

    if ! "${INSTALL_DIR}/gmux" completion install "$completion_shell"; then
        echo "Warning: completion activation failed; the binary and vendor files were installed." >&2
    fi
}

echo "gmux v${VERSION} installed to ${INSTALL_DIR}/gmux"
activate_completion
