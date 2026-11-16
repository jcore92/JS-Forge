#!/bin/bash
jsf_no_pause="1"
umask 077
app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib}"
source "$runtime_core_path" || { echo "Cannot load JS-Forge runtime: $runtime_core_path" >&2; exit 1; }
jsf_init_runtime_core
declare -F cursor_menu >/dev/null || { echo 'Runtime cursor_menu is unavailable.' >&2; exit 1; }
clusters_dir="$HOME/.clusterssh"
clusters_file="$clusters_dir/clusters"
ssh_file="$HOME/.ssh/config"
config_file="$clusters_dir/config"
backup_dir="${XDG_STATE_HOME:-$HOME/.local/state}/JS-Forge/clusterssh/backups"

pause_screen() { printf '\n'; read -r -p 'Press Enter to continue...' _reply || :; }
confirm_local() { local answer;cursor_menu "$1" answer 'Cancel' 'Proceed' || return 1;[ "$answer" = Proceed ]; }
root() { if (( EUID == 0 ));then "$@";else command -v sudo >/dev/null || { echo 'Root or sudo is needed only for package installation.';return 1; };sudo -- "$@";fi; }
show_command() { printf '  ';printf '%q ' "$@";printf '\n'; }
valid_target() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@:%+-]*$ ]]; }
valid_tag() { [[ "$1" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]]; }

ensure_tools() {
    local tool manager='' ssh_package=openssh-clients package
    local -a missing=() packages=()
    for tool in "$@";do command -v "$tool" >/dev/null 2>&1 || missing+=("$tool");done
    [ "${#missing[@]}" -gt 0 ] || return 0
    if command -v apt-get >/dev/null;then manager=apt-get;command -v dpkg-query >/dev/null && ssh_package=openssh-client
    elif command -v dnf >/dev/null;then manager=dnf
    elif command -v yum >/dev/null;then manager=yum
    elif command -v zypper >/dev/null;then manager=zypper;ssh_package=openssh
    elif command -v pacman >/dev/null;then manager=pacman;ssh_package=openssh
    fi
    for tool in "${missing[@]}";do
        case "$tool" in cssh) package=clusterssh ;; ssh) package="$ssh_package" ;; nano|xterm) package="$tool" ;; *) echo "Install this tool manually: $tool";return 1 ;; esac
        packages+=("$package")
    done
    printf 'Missing commands: %s\nPackages: %s\n' "${missing[*]}" "${packages[*]}"
    [ -n "$manager" ] || { echo 'No recognized native package installer found. Editing/other actions remain available.';return 1; }
    echo 'Review the native package transaction. No repositories or services will be configured by this wrapper.'
    confirm_local 'Install the displayed missing packages?' || return 1
    case "$manager" in
        apt-get) root apt-get install "${packages[@]}" || return 1 ;;
        dnf|yum) root "$manager" install "${packages[@]}" || return 1 ;;
        zypper) root zypper install "${packages[@]}" || return 1 ;;
        pacman) root pacman -S --needed "${packages[@]}" || return 1 ;;
    esac
    hash -r
    for tool in "${missing[@]}";do command -v "$tool" >/dev/null 2>&1 || { echo "Package command completed but $tool is still unavailable. Check repository/package availability.";return 1; };done
}
backup_file() {
    local source="$1" destination
    [ -e "$source" ] || return 0
    [ -f "$source" ] || { echo "Not a regular configuration file: $source";return 1; }
    mkdir -p -- "$backup_dir" || return 1
    destination="$(mktemp "$backup_dir/$(basename "$source").$(date +%Y%m%d-%H%M%S).XXXXXX")" || return 1
    if ! cat -- "$source" > "$destination";then rm -f -- "$destination";return 1;fi
    chmod 600 -- "$destination" || return 1
    echo "Backup: $destination"
}
create_file() {
    local path="$1" kind="$2"
    if [ -e "$path" ] || [ -L "$path" ];then [ -f "$path" ] || { echo "Not an existing regular file: $path";return 1; };return 0;fi
    mkdir -p -- "$(dirname -- "$path")" || return 1
    # Noclobber protects a file created concurrently; existing content is never seeded over.
    case "$kind" in
        clusters) (set -o noclobber;cat > "$path" <<'SEED_CLUSTERS'
# ClusterSSH server groups: tag host1 host2 user@host3:2222
# Prefer SSH aliases for keys, jump hosts, ports, domain usernames or IPv6.
# Examples only; uncomment/edit with your actual hosts:
# lab    lab-one lab-two
# web    web-one web-two
# all    lab web
# Do not create recursive tag references.
SEED_CLUSTERS
        ) ;;
        ssh) (set -o noclobber;cat > "$path" <<'SEED_SSH'
# SSH client aliases (not the SSH server configuration).
# Host lab-one
#     HostName 192.0.2.10
#     User yourusername
#     Port 22
#     IdentityFile ~/.ssh/id_ed25519
#     IdentitiesOnly yes
#
# Host lab-two
#     HostName 192.0.2.11
#     User yourusername
#     ProxyJump your-jump-host
#
# For a domain account, User can be youruser@your.actual.domain.
SEED_SSH
        ) ;;
        config) (set -o noclobber;cat > "$path" <<'SEED_CONFIG'
# ClusterSSH preferences. Uncomment/change only the settings you want.
# Native defaults and /etc/csshrc still apply.
# terminal_font = 6x13
# terminal_size = 100x30
# screen_reserve_top = 40
# screen_reserve_bottom = 60
# window_tiling = 1
# auto_close = 0
# Prefer ~/.ssh/config for SSH identity/key/jump-host settings.
SEED_CONFIG
        ) ;;
        *) return 1 ;;
    esac
}
edit_config() {
    local path="$1" kind="$2"
    ensure_tools nano || return 1
    printf 'Editing as %s: %s\n' "$(id -un)" "$path"
    create_file "$path" "$kind" || return 1
    backup_file "$path" || return 1
    nano -- "$path"
}
show_lists() {
    local path
    for path in /etc/clusters "$clusters_file" /etc/tags "$clusters_dir/tags";do
        printf '\n--- %s ---\n' "$path"
        if [ -f "$path" ];then cat -- "$path";else echo '(not present)';fi
    done
    echo 'Additional files/external tag commands may be configured in ClusterSSH. Use native List all tags for those.'
}
add_cluster() {
    local tag line token found=0
    local -a hosts=()
    read -r -p 'New cluster tag (e.g. lab; empty cancels): ' tag || return 1
    valid_tag "$tag" || { echo 'Use letters, digits, underscores, dots or hyphens; no leading hyphen.';return 1; }
    if [ -f "$clusters_file" ] && awk -v tag="$tag" '$1 == tag {found=1} END {exit !found}' "$clusters_file";then
        echo 'Tag already exists in your cluster file. Use nano to edit it; no duplicate appended.';return 1
    fi
    read -r -p 'Space-separated hosts/SSH aliases (e.g. lab-one lab-two; empty cancels): ' line || return 1
    IFS=$' \t' read -r -a hosts <<< "$line"
    [ "${#hosts[@]}" -gt 0 ] || return 1
    for token in "${hosts[@]}";do valid_target "$token" || { echo "Unsupported target syntax: $token. Use SSH aliases or edit the native file in nano for advanced syntax.";return 1; };[ "$token" != "$tag" ] || { echo 'Direct self-referencing tag refused.';return 1; };done
    printf 'Proposed entry: %s' "$tag";printf ' %s' "${hosts[@]}";printf '\nFile: %s\n' "$clusters_file"
    echo 'This writes only a definition; it does not connect. Review indirect tag cycles manually.'
    confirm_local 'Append this cluster definition?' || return 1
    create_file "$clusters_file" clusters && backup_file "$clusters_file" || return 1
    { printf '\n%s' "$tag";printf ' %s' "${hosts[@]}";printf '\n'; } >> "$clusters_file"
}
check_display() {
    [ -n "${DISPLAY:-}" ] || { echo 'ClusterSSH needs an X11 display. Use a desktop terminal; Wayland needs a working XWayland display.';echo 'Editing and the plain SSH test remain available without a display.';return 1; }
    if command -v timeout >/dev/null && command -v xdpyinfo >/dev/null;then
        timeout 4 xdpyinfo >/dev/null 2>&1 || { echo 'DISPLAY is set but X11 access failed. Check the session/display authorization.';return 1; }
    fi
}
launch_targets() {
    local token login port
    local -a targets=("$@") cmd=(cssh --title 'JS-Forge ClusterSSH')
    [ "${#targets[@]}" -gt 0 ] || { echo 'No targets selected; native default cluster was not launched.';return 1; }
    for token in "${targets[@]}";do valid_target "$token" || { echo "Unsupported target: $token";return 1; };done
    check_display || return 1
    ensure_tools cssh ssh xterm || return 1
    read -r -p 'Default SSH username (blank uses SSH/ClusterSSH settings): ' login || return 1
    if [ -n "$login" ];then
        [[ "$login" =~ ^[A-Za-z0-9_][A-Za-z0-9_.@+\\-]*$ ]] || { echo 'Unsupported username. Use User in ~/.ssh/config for advanced identities.';return 1; }
        cmd+=(--username "$login")
    fi
    read -r -p 'Default port override (blank keeps native settings): ' port || return 1
    if [ -n "$port" ];then
        [[ "$port" =~ ^[0-9]{1,5}$ ]] && (( 10#$port >= 1 && 10#$port <= 65535 )) || { echo 'Port must be 1-65535.';return 1; }
        cmd+=(--port "$port")
    fi
    cmd+=("${targets[@]}")
    printf '\nLaunch command:\n';show_command "${cmd[@]}"
    echo 'The ClusterSSH console broadcasts keystrokes to its connected terminals.'
    echo 'Verify every host before typing; enter passwords in the individual terminal that requests them.'
    echo 'Existing native ClusterSSH/SSH configuration is honored and may define hooks or extra tags.'
    confirm_local 'Open this ClusterSSH session?' || return 1
    echo 'Close the ClusterSSH console when finished to return to this menu.'
    "${cmd[@]}"
}
launch_saved() {
    local choice path tag
    local -a tags=()
    while IFS= read -r tag;do valid_tag "$tag" && tags+=("$tag");done < <(
        for path in /etc/clusters "$clusters_file";do [ ! -f "$path" ] || awk '!/^[[:space:]]*#/ && NF>1 {print $1}' "$path";done | LC_ALL=C sort -u
    )
    if [ "${#tags[@]}" = 0 ];then echo 'No tags in standard cluster files. Edit the server list, add a cluster, or type a tag/host manually.';return 1;fi
    cursor_menu 'Choose a standard-file cluster:' choice 'Cancel' "${tags[@]}" || return 1
    [ "$choice" != Cancel ] || return 0
    launch_targets "$choice"
}
launch_manual() {
    local line
    local -a targets=()
    read -r -p 'Space-separated hosts, SSH aliases or cluster tags (empty cancels): ' line || return 1
    IFS=$' \t' read -r -a targets <<< "$line"
    launch_targets "${targets[@]}"
}
ssh_test() {
    local host
    read -r -p 'One SSH alias/hostname (use an alias for custom user/port; empty cancels): ' host || return 1
    [[ "$host" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { echo 'Use a single hostname or SSH alias, not a command or host:port.';return 1; }
    ensure_tools ssh || return 1
    show_command ssh "$host"
    confirm_local 'Open this ordinary single-host SSH session?' || return 1
    ssh "$host"
}
show_status() {
    local tool path
    printf 'User: %s | HOME: %s\nDISPLAY: %s\n' "$(id -un)" "$HOME" "${DISPLAY:-(unset)}"
    for tool in cssh xterm ssh nano;do printf '%-8s ' "$tool";command -v "$tool" || :;done
    for path in "$clusters_file" "$config_file" "$ssh_file";do
        printf '\n%s\n' "$path";[ ! -e "$path" ] || ls -l -- "$path"
    done
    printf '\nBackups: %s\n' "$backup_dir"
}
show_notes() {
    cat <<'NOTES'
SERVER LIST: ~/.clusterssh/clusters (tag host1 host2 ...).
SSH CLIENT:  ~/.ssh/config (Host aliases, User, HostName, Port, keys, ProxyJump).
CSSH SETUP:  ~/.clusterssh/config (terminal font, tiling and other native options).
Do not confuse the SSH client config with /etc/ssh/sshd_config on the servers.

Start with SSH aliases and test each alias with ordinary SSH. Then put the aliases
on a cluster line such as: lab lab-one lab-two. You can nest tags, but do not form
cycles. The saved-tag chooser reads /etc/clusters and your standard cluster file;
custom/external/reverse tags remain accessible by manually entering their names.
Native 'List all tags' uses cssh --list and may evaluate native tag helpers.

Nano: Ctrl+O, Enter saves; Ctrl+X exits. Every wrapper edit has a private timestamped
backup before nano starts. Existing config is not overwritten with defaults.
Seed templates are comments only. Backup listing shows where to restore manually;
no automatic overwrite/restore or system-wide configuration editing is included.

Run as your normal desktop/domain user. Files and launches use THIS process HOME,
UID, SSH agent and display; they are not elevated with sudo. Package installation
alone may request sudo. If the entire app runs as root, its HOME/credentials are
root's and the menu warns accordingly; it does not silently switch accounts.

cssh uses X11/xterm. A Wayland session needs usable XWayland/DISPLAY; a headless
terminal can edit configs and run plain SSH, but cannot open ClusterSSH without
an authorized X display. Nothing enables X forwarding, xhost, or agent forwarding.
Native host-key checking, authentication and key permissions are not weakened.
No passwords/private keys are collected or written by this wrapper.

Typed targets are quoted arguments, never eval. Restricted simple target syntax
is deliberate; use SSH aliases for IPv6, complex domain names or jump hosts, and
nano for native brace expansions. Manually edited configs are trusted native
inputs; this wrapper is NOT a sandbox for shell hooks in those configs.

Broadcasting is powerful: confirm all hosts and environment labels before typing.
Do not assume password prompts or file contents are synchronized on all hosts.
No automatic remote command/action is added. Launch stays foreground so errors
remain visible; a daemonizing native configuration can alter that behavior.
No service-manager or distro-name whitelist; package availability still varies.
NOTES
}
main() {
    local choice rc
    while :;do
        printf '\033[H\033[2JJS-Forge: ClusterSSH Manager\n\nUser: %s | HOME: %s\n' "$(id -un)" "$HOME"
        if (( EUID == 0 ));then echo 'WARNING: running as root. Configs/SSH identity use the current root process context; prefer your desktop user.';fi
        cursor_menu 'Select an action:' choice \
            'Launch a saved cluster' 'Launch typed hosts / aliases / tags' \
            'Edit server / cluster list in nano' 'Add a cluster (guided)' \
            'Edit SSH client aliases in nano' 'Edit ClusterSSH settings in nano' \
            'Show standard server lists' 'List all tags (native cssh)' \
            'Test one host with ordinary SSH' 'Install / check ClusterSSH tools' \
            'Status / paths' 'List config backups' 'Help / examples' 'Exit' || return 0
        rc=0
        case "$choice" in
            'Launch a saved cluster') launch_saved || rc=$? ;;
            'Launch typed hosts / aliases / tags') launch_manual || rc=$? ;;
            'Edit server / cluster list in nano') edit_config "$clusters_file" clusters || rc=$? ;;
            'Add a cluster (guided)') add_cluster || rc=$? ;;
            'Edit SSH client aliases in nano') edit_config "$ssh_file" ssh || rc=$? ;;
            'Edit ClusterSSH settings in nano') edit_config "$config_file" config || rc=$? ;;
            'Show standard server lists') show_lists || rc=$? ;;
            'List all tags (native cssh)') ensure_tools cssh && cssh --list || rc=$? ;;
            'Test one host with ordinary SSH') ssh_test || rc=$? ;;
            'Install / check ClusterSSH tools') ensure_tools cssh ssh xterm nano || rc=$? ;;
            'Status / paths') show_status || rc=$? ;;
            'List config backups') if [ -d "$backup_dir" ];then ls -lt -- "$backup_dir";else echo 'No wrapper backups yet.';fi ;;
            'Help / examples') show_notes ;;
            *) return 0 ;;
        esac
        [ "$rc" = 0 ] || echo 'Action failed or was cancelled. Review the output; no later automatic action ran.'
        pause_screen
    done
}
main "$@"