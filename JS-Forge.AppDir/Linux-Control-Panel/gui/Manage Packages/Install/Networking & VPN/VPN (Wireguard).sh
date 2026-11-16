#!/bin/bash
jsf_no_pause="1"


app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"


source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}


jsf_init_runtime_core


find_resolvconf() {
    local candidate


    candidate="$(command -v resolvconf 2>/dev/null || true)"


    for candidate in \
        "$candidate" \
        /usr/local/sbin/resolvconf \
        /usr/local/bin/resolvconf \
        /usr/sbin/resolvconf \
        /usr/bin/resolvconf \
        /sbin/resolvconf \
        /bin/resolvconf; do

        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done


    return 1
}


ensure_resolvconf() {
    local distro_family
    local resolvconf_path


    if resolvconf_path="$(find_resolvconf)"; then
        echo "resolvconf is available: $resolvconf_path"
        return 0
    fi


    distro_family="$(jsf_detect_distro_family)"


    echo "resolvconf was not found."
    echo "Installing a compatible DNS resolver helper..."


    case "$distro_family" in
    debian | arch)
        jsf_require_all --native openresolv
        ;;
    mandriva)
        jsf_require_all --native resolvconf
        ;;
    suse)
        echo "No standard automatic resolvconf package is configured for openSUSE."
        echo "WireGuard-GUI will still be installed, but DNS-enabled wg-quick profiles"
        echo "may need an openSUSE-specific DNS configuration later."
        return 0
        ;;
    *)
        echo "No automatic resolvconf package is configured for this distro family."
        echo "WireGuard-GUI will still be installed."
        return 0
        ;;
    esac


    if resolvconf_path="$(find_resolvconf)"; then
        echo "resolvconf is ready: $resolvconf_path"
        return 0
    fi


    echo "A resolvconf-compatible helper could not be found after installation."
    return 1
}


# Requires your runtime-core mapping:
# "wg" | "wg-quick") echo "wireguard-tools" ;;
# wg-quick
jsf_require_all --native wg || exit 1

ensure_resolvconf || exit 1


jsf_install_github_appimage \
    "WireGuard-GUI" \
    "0xle0ne/wireguard-gui" \
    "wireguard-gui.*amd64.*appimage" \
    --launch