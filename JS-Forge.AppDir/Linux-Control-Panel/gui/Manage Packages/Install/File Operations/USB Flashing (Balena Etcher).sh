#!/bin/bash
jsf_no_pause="1"


app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"


source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}


jsf_init_runtime_core


jsf_require_all \
  --native curl jq unzip


etcher_repository="balena-io/etcher"
etcher_asset_pattern='^balenaEtcher-linux-x64-.*\.zip$'

etcher_install_dir="$HOME/Downloads/balenaEtcher"
etcher_download_dir="$etcher_install_dir/downloads"
etcher_extract_dir="$etcher_install_dir/current"
etcher_state_dir="$etcher_install_dir/.state"

etcher_binary_file="$etcher_state_dir/executable-path"
etcher_asset_file="$etcher_state_dir/asset-name"

etcher_api_url="https://api.github.com/repos/$etcher_repository/releases/latest"


etcher_find_executable() {
    local candidate

    candidate="$(find "$etcher_extract_dir" \
        -type f \
        -name "balena-etcher" \
        -print -quit 2>/dev/null)"

    [ -n "$candidate" ] || return 1

    chmod +x "$candidate" 2>/dev/null || return 1
    printf '%s\n' "$candidate"
}


etcher_saved_binary() {
    local saved_binary

    [ -r "$etcher_binary_file" ] || return 1

    saved_binary="$(cat "$etcher_binary_file" 2>/dev/null)"

    [ -n "$saved_binary" ] || return 1
    [ -f "$saved_binary" ] || return 1

    chmod +x "$saved_binary" 2>/dev/null || return 1
    printf '%s\n' "$saved_binary"
}


mkdir -p \
    "$etcher_download_dir" \
    "$etcher_extract_dir" \
    "$etcher_state_dir" || {
    echo "Error: could not create Etcher directory:"
    echo "$etcher_install_dir"
    exit 1
}


echo "Checking the latest balenaEtcher release..."

etcher_release_json="$(curl -fsSL \
    --connect-timeout 15 \
    --max-time 45 \
    -H "Accept: application/vnd.github+json" \
    "$etcher_api_url")" || {
    echo "Error: could not contact GitHub for balenaEtcher releases." >&2
    exit 1
}


etcher_download_url="$(printf '%s' "$etcher_release_json" | jq -r \
    --arg pattern "$etcher_asset_pattern" \
    '.assets[]
    | select(.name | test($pattern; "i"))
    | .browser_download_url' \
    | head -n 1)"


etcher_asset_name="$(printf '%s' "$etcher_release_json" | jq -r \
    --arg pattern "$etcher_asset_pattern" \
    '.assets[]
    | select(.name | test($pattern; "i"))
    | .name' \
    | head -n 1)"


if [ -z "$etcher_download_url" ] || [ "$etcher_download_url" = "null" ]; then
    echo "Error: no Linux x64 balenaEtcher ZIP asset was found in the latest release." >&2
    exit 1
fi


etcher_binary="$(etcher_saved_binary)"
etcher_saved_asset=""

if [ -r "$etcher_asset_file" ]; then
    etcher_saved_asset="$(cat "$etcher_asset_file" 2>/dev/null)"
fi


if [ -n "$etcher_binary" ] && [ "$etcher_saved_asset" = "$etcher_asset_name" ]; then
    echo "balenaEtcher is already current."
    echo "Using: $etcher_binary"
else
    etcher_zip_path="$etcher_download_dir/$etcher_asset_name"
    etcher_partial_path="$etcher_zip_path.part"

    if [ ! -f "$etcher_zip_path" ]; then
        echo "Downloading: $etcher_asset_name"

        curl --fail \
            --location \
            --connect-timeout 15 \
            --max-time 900 \
            --output "$etcher_partial_path" \
            "$etcher_download_url" || {
            rm -f -- "$etcher_partial_path"
            echo "Error: Etcher download failed." >&2
            exit 1
        }

        mv -f -- "$etcher_partial_path" "$etcher_zip_path" || {
            rm -f -- "$etcher_partial_path"
            echo "Error: could not save the Etcher ZIP archive." >&2
            exit 1
        }
    else
        echo "Using already-downloaded archive:"
        echo "$etcher_zip_path"
    fi

    rm -rf -- "$etcher_extract_dir"
    mkdir -p "$etcher_extract_dir" || {
        echo "Error: could not create extraction directory." >&2
        exit 1
    }

    echo "Extracting balenaEtcher..."

    unzip -q -o "$etcher_zip_path" -d "$etcher_extract_dir" 2>&1 || true

    etcher_binary="$(etcher_find_executable)" || {
        echo "Error: could not locate balena-etcher after extraction." >&2
        echo "Expected file: */balenaEtcher-linux-x64/balena-etcher" >&2
        exit 1
    }

    printf '%s\n' "$etcher_binary" > "$etcher_binary_file"
    printf '%s\n' "$etcher_asset_name" > "$etcher_asset_file"

    echo "balenaEtcher is ready:"
    echo "$etcher_binary"
fi


echo "Launching balenaEtcher..."
setsid "$etcher_binary" >/dev/null 2>&1 &
disown 2>/dev/null || true