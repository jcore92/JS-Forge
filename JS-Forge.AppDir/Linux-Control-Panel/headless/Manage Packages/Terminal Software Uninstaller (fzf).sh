#!/bin/bash
jsf_no_pause="1"
umask 077


pause_action() {
    if [ -t 0 ]; then read -r -p 'Press Enter to return to the search...' _; fi
}


read_context() {
    state_dir="$1"
    [ -d "$state_dir" ] && [ -f "$state_dir/manager" ] || return 1
    IFS= read -r package_manager < "$state_dir/manager"
    IFS= read -r appimage_dir < "$state_dir/appimage-dir"
}


add_record() {
    local kind="$1" target="$2" scope="$3" version="$4" name="$5" shown record_key
    # Tabs/newlines are record delimiters, not supported pathname characters here.
    case "$target$scope$version$name" in *$'\t'*|*$'\n'*|*$'\r'*) return ;; esac
    ((record_id+=1))
    record_key="${inventory_generation}-${record_id}"
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$record_key" "$kind" "$target" "$scope" "$version" "$name" >> "$meta_build"
    case "$kind" in
        native) printf -v shown '%-20s %-44s %s' '[Native]' "$name" "$version" ;;
        flatpak) printf -v shown '%-20s %-44s %s | %s' "[Flatpak:$scope]" "$name" "$version" "$target" ;;
        appimage) printf -v shown '%-20s %-44s %s' '[AppImage]' "$name" "$target" ;;
    esac
    printf '%s\t%s\n' "$record_key" "$shown" >> "$list_build"
}


build_inventory() {
    local record_id=0 status target version name scope branch arch path
    local inventory_generation="${BASHPID}_${RANDOM}_${RANDOM}"
    local meta_build="$state_dir/meta.$inventory_generation"
    local list_build="$state_dir/list.$inventory_generation"
    local sorted_build="$state_dir/sorted.$inventory_generation"
    : > "$meta_build"; : > "$list_build"
    case "$package_manager" in
        apt)
            while IFS=$'\t' read -r status target version; do
                [ "$status" = installed ] && add_record native "$target" apt "$version" "$target"
            done < <(dpkg-query -W -f='${db:Status-Status}\t${binary:Package}\t${Version}\n')
            ;;
        pacman)
            while read -r target version; do
                [ -n "$target" ] && add_record native "$target" pacman "$version" "$target"
            done < <(pacman -Q)
            ;;
        dnf|yum|zypper)
            while IFS=$'\t' read -r target version; do
                [ -n "$target" ] && add_record native "$target" "$package_manager" "$version" "$target"
            done < <(rpm -qa --qf '%{NAME}.%{ARCH}\t%{VERSION}-%{RELEASE}\n')
            ;;
    esac
    if command -v flatpak >/dev/null 2>&1; then
        # A visible placeholder avoids collapsing empty tab-separated fields in read.
        while IFS=$'\t' read -r name target version branch arch scope; do
            [ -n "$target" ] && [ "$branch" != '-' ] && [ "$arch" != '-' ] && [ "$scope" != '-' ] || continue
            add_record flatpak "app/$target/$arch/$branch" "$scope" "$version" "$name"
        done < <(flatpak list --app --columns=name,application,version,branch,arch,installation |
            awk -F '\t' 'NF >= 6 {for(i=1;i<=6;i++) if($i=="") $i="-"; OFS="\t"; print $1,$2,$3,$4,$5,$6}')
    fi
    if [ -d "$appimage_dir" ]; then
        while IFS= read -r -d '' path; do
            [ -f "$path" ] || continue
            name="${path##*/}"
            add_record appimage "$path" file '-' "$name"
        done < <(find "$appimage_dir" \( -type f -o -type l \) -iname '*.appimage' -print0)
    fi
    LC_ALL=C sort -t $'\t' -k2,2 "$list_build" > "$sorted_build"
    mv -- "$meta_build" "$state_dir/meta"
    mv -- "$sorted_build" "$state_dir/list"
    rm -f -- "$list_build"
    date '+%Y-%m-%d %H:%M:%S %Z' > "$state_dir/collected"
}


export_inventory() {
    local destination="$1" report
    if ! mkdir -p -- "$destination"; then echo 'Cannot create export directory.' >&2; pause_action; return 1; fi
    report="$(mktemp "$destination/JS-Forge-Installed-Software-$(date +%Y-%m-%d_%H-%M-%S).XXXXXX.txt")" || return 1
    if {
        printf 'JS-Forge: Installed Software Inventory\n'
        printf 'Collected: %s\n' "$(cat "$state_dir/collected")"
        printf 'Exported: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf 'Entries: %s\n\n' "$(wc -l < "$state_dir/list" | tr -d ' ')"
        printf 'Full inventory, independent of the current search filter.\n'
        printf 'Native entries include libraries/dependencies; AppImages are discovered files.\n\n'
        printf '%-20s %-44s %s\n' Source Name 'Version / Ref / Path'
        cut -f2- "$state_dir/list"
    } > "$report"; then
        printf '\nFull inventory exported to:\n%s\n' "$report"
    else
        rm -f -- "$report"; echo 'Export failed.' >&2; pause_action; return 1
    fi
    pause_action
}


run_privileged() {
    if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi
}


flatpak_scope_args() {
    case "$1" in
        user) scope_args=(--user) ;;
        system|default) scope_args=(--system) ;;
        ''|-) return 1 ;;
        *) scope_args=("--installation=$1") ;;
    esac
}


remove_inventory_item() {
    local wanted="$1" record id kind target scope version name message gear_output line gear_path
    local selected_real running_real managed_path='' protected flags count status result=0
    local scope_args=() command_args=()
    [[ "$wanted" =~ ^[0-9_]+-[0-9]+$ ]] || return 1
    record="$(awk -F '\t' -v wanted="$wanted" '$1 == wanted {print; exit}' "$state_dir/meta")"
    [ -n "$record" ] || { echo 'Selection is stale. Refresh with Ctrl+R.'; pause_action; return 1; }
    IFS=$'\t' read -r id kind target scope version name <<< "$record"
    case "$kind" in
        native)
            # Guard the inventory's immediate runtime dependencies. Not a full OS safety list.
            protected="${target%%:*}"; protected="${protected%.x86_64}"; protected="${protected%.aarch64}"
            case "$protected" in
                bash|fzf|whiptail|apt|dpkg|rpm|pacman|dnf|yum|zypper|sudo|coreutils|findutils|gawk|mawk|flatpak)
                    printf 'Removal blocked: %s is needed by this tool or its management workflow.\n' "$target"
                    pause_action; return 1 ;;
            esac
            case "$scope" in
                apt)
                    status="$(dpkg-query -W -f='${db:Status-Status}' -- "$target" 2>/dev/null)"
                    [ "$status" = installed ] || { echo 'Package is no longer installed. Refresh first.'; pause_action; return 1; }
                    flags="$(dpkg-query -W -f='${Essential}\t${Protected}' -- "$target" 2>/dev/null)"
                    if [[ "$flags" == *yes* ]]; then echo 'Removal blocked: essential/protected package.'; pause_action; return 1; fi
                    command_args=(apt remove -- "$target") ;;
                pacman)
                    pacman -Q -- "$target" >/dev/null 2>&1 || { echo 'Package is no longer installed.'; pause_action; return 1; }
                    command_args=(pacman -R -- "$target") ;;
                dnf|yum|zypper)
                    count="$(rpm -q --qf '%{NAME}\n' -- "$target" 2>/dev/null | wc -l)"
                    if [ "$count" -ne 1 ]; then
                        echo 'Removal blocked: package is absent or has multiple installed versions. Use the native manager directly.'
                        pause_action; return 1
                    fi
                    if [ "$scope" = zypper ]; then command_args=(zypper remove -- "$target")
                    else command_args=("$scope" --setopt=clean_requirements_on_remove=False remove -- "$target"); fi ;;
                *) echo 'Unsupported native removal backend.'; pause_action; return 1 ;;
            esac
            message="Remove this native package?\n\n$target\nVersion: $version\nManager: $scope\n\nThe manager may propose removing OTHER packages that depend on it. Review its transaction and decline if unsure. No purge or automatic yes is requested."
            ;;
        flatpak)
            flatpak_scope_args "$scope" || { echo 'Unknown Flatpak installation; refusing removal.'; pause_action; return 1; }
            flatpak info "${scope_args[@]}" "$target" >/dev/null 2>&1 || {
                echo 'That exact Flatpak ref is no longer installed in the recorded scope.'; pause_action; return 1;
            }
            command_args=(flatpak uninstall "${scope_args[@]}" "$target")
            message="Remove this Flatpak application?\n\n$name\n$target\nInstallation: $scope\n\nApplication data will be kept. Flatpak retains its own confirmation prompt."
            ;;
        appimage)
            [ -f "$target" ] || { echo 'AppImage is no longer present.'; pause_action; return 1; }
            selected_real="$(readlink -f -- "$target")" || return 1
            if [ -n "${APPIMAGE:-}" ]; then
                running_real="$(readlink -f -- "$APPIMAGE" 2>/dev/null)"
                if [ "$selected_real" = "$running_real" ]; then
                    echo 'Removal blocked: this is the currently running JS-Forge AppImage.'; pause_action; return 1
                fi
            fi
            # Do not use a desktop manager through an SSH/headless session.
            if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ] ||
               [ "${JSF_DESKTOP_CAPABLE:-1}" = 0 ] ||
               [ -z "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ]; then
                echo 'AppImage removal through Gear Lever is unavailable in this headless/SSH session.'
                pause_action; return 1
            fi
            if ! command -v flatpak >/dev/null 2>&1 ||
               ! flatpak info it.mijorus.gearlever >/dev/null 2>&1; then
                echo 'Gear Lever is unavailable. No manual deletion fallback is performed.'; pause_action; return 1
            fi
            gear_output="$(flatpak run it.mijorus.gearlever --list-installed)" || {
                echo 'Unable to query Gear Lever; nothing removed.'; pause_action; return 1;
            }
            while IFS= read -r line; do
                # Match the absolute path following whitespace; keep internal spaces.
                if [[ "$line" =~ [[:space:]](/.*)$ ]]; then
                    gear_path="${BASH_REMATCH[1]}"
                    gear_path="${gear_path%"${gear_path##*[![:space:]]}"}"
                    # Exact reported pathname only: no guessing from names or versions.
                    if [ "$gear_path" = "$target" ]; then managed_path="$gear_path"; break; fi
                fi
            done <<< "$gear_output"
            if [ -z "$managed_path" ]; then
                echo 'Gear Lever does not report this exact AppImage path as integrated. Nothing removed.'
                pause_action; return 1
            fi
            command_args=(flatpak run it.mijorus.gearlever --remove "$managed_path" --yes)
            message="Remove this Gear Lever-managed AppImage?\n\n$name\n$managed_path\n\nGear Lever will trash the AppImage and remove its desktop integration. JS-Forge will not manually delete application settings."
            ;;
        *) echo 'Unknown item type; nothing removed.'; pause_action; return 1 ;;
    esac
    if ! whiptail --title 'JS-Forge: Confirm Single-Item Removal' --defaultno \
        --yes-button 'Continue' --no-button 'Cancel' --yesno "$message" 21 80; then
        return 0
    fi
    printf '\nRequested command: '
    printf '%q ' "${command_args[@]}"; printf '\n\n'
    if [ "$kind" = native ]; then run_privileged "${command_args[@]}"; result=$?
    else "${command_args[@]}"; result=$?; fi
    if [ "$result" -eq 0 ]; then echo 'Manager command completed; refreshing the inventory.'
    else printf 'Manager returned status %s. Review its output; the inventory will be refreshed.\n' "$result"; fi
    pause_action
    build_inventory
    return 0
}


# Internal actions invoked by the interactive browser, not a general uninstall CLI.
case "${1:-}" in
    --export)
        read_context "$2" || exit 1
        export_inventory "$3"; exit $? ;;
    --remove)
        read_context "$2" || exit 1
        remove_inventory_item "${3:-}"; exit $? ;;
    --refresh)
        read_context "$2" || exit 1
        build_inventory
        cat -- "$state_dir/list"; exit 0 ;;
esac


app_name=JS-Forge
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"
source "$runtime_core_path" || { echo "Fatal: failed to source $runtime_core_path" >&2; exit 1; }
jsf_init_runtime_core
jsf_require_all --native fzf whiptail || exit 1
for tool in fzf whiptail; do
    command -v "$tool" >/dev/null 2>&1 || { echo "Required tool unavailable: $tool" >&2; exit 1; }
done


# Editable locations.
appimage_dir="$HOME/AppImages"
export_dir="$HOME/JS-Forge-Exports"
state_dir="$(mktemp -d "${TMPDIR:-/tmp}/jsforge-software.XXXXXX")" || exit 1
# Remove only files created by this script, never listed software.
trap 'rm -f -- "$state_dir"/*; rmdir -- "$state_dir" 2>/dev/null || :' EXIT
printf '%s\n' "$package_manager" > "$state_dir/manager"
printf '%s\n' "$appimage_dir" > "$state_dir/appimage-dir"
echo 'Collecting installed software...'
build_inventory
if [ ! -s "$state_dir/list" ]; then echo 'No inventory entries found.'; pause_action; exit 0; fi


script_path="$(readlink -f -- "${BASH_SOURCE[0]}")" || exit 1
printf -v export_command 'bash %q --export %q %q' "$script_path" "$state_dir" "$export_dir"
printf -v remove_command 'bash %q --remove %q {1}' "$script_path" "$state_dir"
printf -v refresh_command 'bash %q --refresh %q' "$script_path" "$state_dir"
printf -v read_command 'cat -- %q' "$state_dir/list"


SHELL=/bin/bash FZF_DEFAULT_OPTS='' FZF_DEFAULT_OPTS_FILE='' \
    fzf --layout=reverse --border --no-sort --no-multi \
        --delimiter=$'\t' --with-nth=2.. \
        --prompt='Search installed > ' \
        --header=$'JS-Forge: Terminal Software Uninstaller\nType to search | Ctrl+U clear | Esc close | Ctrl+R refresh\nCtrl+E export FULL list | Ctrl+D / double-click: request removal of ONE item\nEnter does nothing. Native entries include libraries; review all manager transactions.' \
        --bind='enter:ignore' \
        --bind="ctrl-e:execute($export_command)" \
        --bind="ctrl-d:execute($remove_command)+reload($read_command)" \
        --bind="double-click:execute($remove_command)+reload($read_command)" \
        --bind="ctrl-r:reload($refresh_command)" \
        < "$state_dir/list" > /dev/null
status=$?
case "$status" in 0|1|130) exit 0 ;; *) exit "$status" ;; esac