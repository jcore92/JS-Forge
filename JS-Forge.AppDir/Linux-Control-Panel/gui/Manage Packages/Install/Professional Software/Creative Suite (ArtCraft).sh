#!/bin/bash
jsf_no_pause="1"
app_name="JS-Forge"

if (( EUID == 0 )); then
    echo 'Run this script as your desktop user, not with sudo/root.' >&2
    exit 1
fi

runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib}"
source "$runtime_core_path" || {
    printf 'Fatal: cannot source %s\n' "$runtime_core_path" >&2
    exit 1
}
jsf_init_runtime_core
jsf_require_all --native flatpak || exit 1
command -v flatpak >/dev/null 2>&1 || { echo 'Flatpak is unavailable.' >&2; exit 1; }
declare -F jsf_is_flatpak_installed >/dev/null || {
    echo 'The JS-Forge Flatpak installation check is unavailable.' >&2
    exit 1
}

app_id="ai.storyteller.artcraft-launcher"
remote_name="artcraft-oci"
remote_file="https://getartcraft.com/artcraft-oci.flatpakrepo"
expected_url="oci+https://getartcraft.com"
remote_found=0

remotes="$(flatpak remotes --user --columns=name,url)" || exit 1
while IFS=$'\t' read -r name url; do
    [ "$name" = "$remote_name" ] || continue
    remote_found=1
    if [ "${url%/}" != "$expected_url" ]; then
        printf 'Existing %s points to an unexpected URL: %s\n' "$remote_name" "$url" >&2
        echo 'Nothing was changed; review that remote before continuing.' >&2
        exit 1
    fi
done <<< "$remotes"

if [ "$remote_found" = 0 ]; then
    echo 'Adding the official ArtCraft repository for this user...'
    echo 'Third-party source: its published descriptor currently sets GPGVerify=false.'
    flatpak remote-add --user --if-not-exists "$remote_name" "$remote_file" || exit 1
fi

if ! jsf_is_flatpak_installed "$app_id"; then
    echo 'Installing ArtCraft Launcher...'
    flatpak install --user "$remote_name" "$app_id" || exit 1
fi

jsf_is_flatpak_installed "$app_id" || {
    echo 'ArtCraft Launcher installation could not be verified.' >&2
    exit 1
}

echo 'Opening ArtCraft Launcher...'
exec flatpak run --user "$app_id"