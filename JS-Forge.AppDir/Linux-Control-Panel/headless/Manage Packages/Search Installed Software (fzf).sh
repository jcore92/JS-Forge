#!/bin/bash
jsf_no_pause="1"

# Internal export action: no runtime initialization or package changes needed.
if [ "${1:-}" = "--export-inventory" ]; then
    inventory_source="${2:-}"
    export_directory="${3:-}"
    snapshot_time="${4:-unknown}"
    export_status=0
    if [ ! -f "$inventory_source" ] || [ -z "$export_directory" ]; then
        printf 'Export failed: inventory or destination unavailable.\n' >&2
        export_status=1
    elif ! mkdir -p -- "$export_directory"; then
        printf 'Export failed: cannot create destination directory.\n' >&2
        export_status=1
    else
        export_file="$(mktemp "$export_directory/JS-Forge-Installed-Software-$(date +%Y-%m-%d_%H-%M-%S).XXXXXX.txt")"
        if [ -z "$export_file" ]; then
            printf 'Export failed: cannot create report file.\n' >&2
            export_status=1
        else
            if {
                printf 'JS-Forge: Installed Software Inventory\n'
                printf 'Snapshot collected: %s\n' "$snapshot_time"
                printf 'Exported: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
                printf 'Entries: %s\n' "$(wc -l < "$inventory_source" | tr -d ' ')"
                printf '\nFull inventory, regardless of the current search filter.\n'
                printf 'Native packages include libraries and dependencies.\n'
                printf 'AppImage entries represent files found, not a package database.\n'
                printf '\n%-18s %-44s %s\n' 'Source' 'Name' 'Version / ID / Path'
                cat -- "$inventory_source"
            } > "$export_file"; then
                printf '\nFull inventory exported to:\n%s\n' "$export_file"
            else
                rm -f -- "$export_file"
                printf 'Export failed while writing the report.\n' >&2
                export_status=1
            fi
        fi
    fi
    if [ -t 0 ]; then
        read -r -p 'Press Enter to return to the search...' _
    fi
    exit "$export_status"
fi

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
jsf_require_all --native fzf || exit 1
command -v fzf >/dev/null 2>&1 || {
    echo "fzf is unavailable. Check the dependency installation output." >&2
    exit 1
}

# Change these locations if desired.
appimage_dir="$HOME/AppImages"
export_dir="$HOME/JS-Forge-Exports"

list_native_packages() {
    case "$package_manager" in
        apt)
            dpkg-query -W -f='${db:Status-Status}\t${binary:Package}\t${Version}\n' |
                awk -F '\t' '$1 == "installed" {
                    printf "%-18s %-44s %s\n", "[Native]", $2, $3
                }'
            ;;
        pacman)
            pacman -Q | awk '{
                printf "%-18s %-44s %s\n", "[Native]", $1, $2
            }'
            ;;
        dnf|yum|zypper)
            rpm -qa --qf '%{NAME}\t%{VERSION}-%{RELEASE}.%{ARCH}\n' |
                awk -F '\t' '{
                    printf "%-18s %-44s %s\n", "[Native]", $1, $2
                }'
            ;;
        *)
            printf 'Native inventory is not configured for package manager: %s\n' "$package_manager" >&2
            ;;
    esac
}

list_flatpak_apps() {
    command -v flatpak >/dev/null 2>&1 || return 0
    flatpak list --app --columns=name,application,version,installation |
        awk -F '\t' 'NF >= 2 {
            scope = ($4 != "" ? $4 : "installed")
            version = ($3 != "" ? $3 : "-")
            printf "%-18s %-44s %s  |  %s\n", "[Flatpak:" scope "]", $1, version, $2
        }'
}

list_appimages() {
    [ -d "$appimage_dir" ] || return 0
    local file name display_path
    while IFS= read -r -d '' file; do
        [ -f "$file" ] || continue
        name="${file##*/}"
        name="$(printf '%s' "$name" | tr '\t\r\n' '   ')"
        display_path="$(printf '%s' "$file" | tr '\t\r\n' '   ')"
        printf '%-18s %-44s %s\n' '[AppImage]' "$name" "$display_path"
    done < <(find "$appimage_dir" \( -type f -o -type l \) -iname '*.appimage' -print0)
}

inventory_file="$(mktemp "${TMPDIR:-/tmp}/jsforge-inventory.XXXXXX")" || exit 1
trap 'rm -f -- "$inventory_file"' EXIT
snapshot_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'Collecting installed software...\n'
{
    list_native_packages
    list_flatpak_apps
    list_appimages
} | LC_ALL=C sort -u > "$inventory_file"

if [ ! -s "$inventory_file" ]; then
    printf 'No inventory entries found. Press Enter to close.'
    read -r _
    exit 0
fi

script_path="$(readlink -f -- "${BASH_SOURCE[0]}")" || exit 1
printf -v export_command 'bash %q --export-inventory %q %q %q' \
    "$script_path" "$inventory_file" "$export_dir" "$snapshot_time"

# Launch only our export action. No listed software is run or modified.
SHELL=/bin/bash FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' \
    fzf --layout=reverse --border --no-sort \
        --prompt='Search installed > ' \
        --header=$'JS-Forge: Installed Software\nType to filter | Arrows/PgUp/PgDn to browse | Ctrl+U to clear | Esc to close\nCtrl+E: export FULL inventory to ~/JS-Forge-Exports/\nSource             Name                                         Version / ID / Path\nNative includes libraries/dependencies; AppImages are files found in your AppImages folder.' \
        --bind='enter:ignore' \
        --bind="ctrl-e:execute($export_command)" \
        < "$inventory_file" > /dev/null
status=$?
case "$status" in
    0|1|130) exit 0 ;;
    *) exit "$status" ;;
esac