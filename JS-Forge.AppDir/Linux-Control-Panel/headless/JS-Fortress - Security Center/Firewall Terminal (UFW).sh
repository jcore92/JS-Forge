#!/bin/bash
jsf_no_pause="1"
umask 077
app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"
source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}
jsf_init_runtime_core
PATH="$PATH:/usr/sbin:/sbin"
export PATH
jsf_require_all --native ufw || exit 1
ufw_bin="$(command -v ufw)" || { echo 'Required native tool unavailable: ufw' >&2; exit 1; }
declare -F cursor_menu >/dev/null || { echo 'Runtime cursor_menu function not found.' >&2; exit 1; }
export_root="$HOME/JS-Forge-Exports"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/jsfortress-ufw.XXXXXX")" || exit 1
trap 'rm -f -- "$work_dir"/*; rmdir -- "$work_dir" 2>/dev/null || :' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

pause_screen() { printf '\n'; read -r -p 'Press Enter to continue...' _reply; }
as_root() { if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi; }
authorize_root() {
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || { echo 'sudo is required.' >&2; return 1; }
        sudo -v || return 1
    fi
}
ufw_read() { as_root env LC_ALL=C "$ufw_bin" "$@"; }
confirm_action_local() {
    local answer
    cursor_menu "$1" answer 'Cancel' 'Proceed' || return 1
    [ "$answer" = Proceed ]
}
print_command() { printf '  '; printf '%q ' ufw "$@"; printf '\n'; }
view_file() {
    if command -v less >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        LESSSECURE=1 LESSHISTFILE=- less -- "$1"
    else cat -- "$1"; pause_screen; fi
}
remote_warning() {
    printf '\nFirewall changes can disconnect SSH, XRDP, VPNs, or other remote access.\n'
    printf 'There is NO automatic rollback. Keep local/VM-console access available.\n'
}
run_change() {
    local -a status
    authorize_root || return 1
    {
        printf '\n[%s] Requested command:\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        print_command "$@"
    } | tee -a "$work_dir/actions.txt"
    ufw_read "$@" 2>&1 | tee -a "$work_dir/actions.txt"
    status=("${PIPESTATUS[@]}")
    printf 'UFW exit status: %s | Capture status: %s\n' "${status[0]}" "${status[1]}" | tee -a "$work_dir/actions.txt"
    if [ "${status[0]}" -ne 0 ] || [ "${status[1]}" -ne 0 ]; then
        echo 'Command/capture failed or was interrupted. Review output and current status.'
        return 1
    fi
    return 0
}
refresh_status() {
    status_text="$(ufw_read status verbose 2>&1)"
    local rc=$?
    firewall_state=Unknown
    if [ "$rc" -eq 0 ]; then
        case "$status_text" in
            'Status: active'*) firewall_state=Active ;;
            'Status: inactive'*) firewall_state=Inactive ;;
        esac
    fi
    [ "$firewall_state" != Unknown ]
}
show_status() {
    {
        printf 'JS-Fortress: UFW Status\nCaptured: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        ufw_read status verbose
        printf '\n===== SAVED UFW USER RULES (including when inactive) =====\n'
        ufw_read show added
        printf '\nUFW status is not an inventory of every rule from every firewall tool.\n'
    } > "$work_dir/status.txt" 2>&1
    view_file "$work_dir/status.txt"
}
valid_single_port() {
    [[ "$1" =~ ^[0-9]{1,5}$ ]] || return 1
    local value=$((10#$1))
    ((value>=1 && value<=65535))
}
valid_ports() {
    local first last
    if [[ "$1" =~ ^([0-9]{1,5}):([0-9]{1,5})$ ]]; then
        first="${BASH_REMATCH[1]}"; last="${BASH_REMATCH[2]}"
        valid_single_port "$first" && valid_single_port "$last" || return 1
        ((10#$first <= 10#$last))
    else valid_single_port "$1"; fi
}
read_ports() {
    local allow_empty="${1:-0}"
    while :; do
        printf '\nUse a port (443) or inclusive range (8000:8010), from 1 to 65535.\n'
        if [ "$allow_empty" = 1 ]; then
            read -r -p 'Port/range (empty means ALL ports): ' ports || return 1
            [ -n "$ports" ] || return 0
        else
            read -r -p 'Port/range (empty cancels): ' ports || return 1
            [ -n "$ports" ] || return 1
        fi
        valid_ports "$ports" && return 0
        echo 'Invalid port/range. Use ascending values from 1 to 65535.'
    done
}
read_source() {
    local optional="${1:-0}"
    while :; do
        printf '\nEnter a literal IPv4/IPv6 address or CIDR subnet, not a hostname.\n'
        if [ "$optional" = 1 ]; then
            read -r -p 'Source (empty means any address): ' source_address || return 1
            [ -n "$source_address" ] || { source_address=any; return 0; }
        else
            read -r -p 'Source (empty cancels): ' source_address || return 1
            [ -n "$source_address" ] || return 1
        fi
        if [[ "$source_address" =~ ^[0-9A-Fa-f:.]+(/[0-9]{1,3})?$ ]]; then
            return 0
        fi
        echo 'Enter an IP address/subnet only. UFW validates the actual address before applying it.'
    done
}
choose_protocol() {
    local selection
    cursor_menu 'Protocol:' selection 'Cancel' 'TCP' 'UDP' 'TCP and UDP' || return 1
    case "$selection" in
        TCP) protocol=tcp ;;
        UDP) protocol=udp ;;
        'TCP and UDP') protocol=both ;;
        *) return 1 ;;
    esac
}
add_rule() {
    local action="$1" source_only="${2:-0}" ports source_address protocol
    local -a args
    printf '\033[H\033[2JJS-Fortress: %s incoming access\n' "$action"
    if [ "$source_only" = 1 ]; then
        read_source 0 || return
        read_ports 1 || return
    else
        read_ports 0 || return
        read_source 1 || return
    fi
    args=("$action" in from "$source_address" to any)
    if [ -n "$ports" ]; then
        choose_protocol || return
        args+=(port "$ports")
        [ "$protocol" = both ] || args+=(proto "$protocol")
    fi
    printf '\nProposed incoming rule(s):\n'
    if [ -n "$ports" ] && [ "$protocol" = both ]; then
        print_command "${args[@]}" proto tcp
        print_command "${args[@]}" proto udp
        echo 'Two separate rules will be requested. If one fails, the other is not rolled back.'
    else
        print_command "${args[@]}"
    fi
    if [ -z "$ports" ]; then echo 'WARNING: this allows ALL incoming ports/protocols from the specified source.'; fi
    printf 'Existing rules are retained. Earlier matching rules can take precedence.\n'
    printf 'A new deny rule does not override an earlier matching allow rule.\n'
    [ "$action" = deny ] && remote_warning
    confirm_action_local 'Apply the displayed incoming rule(s)?' || return
    if [ -n "$ports" ] && [ "$protocol" = both ]; then
        if run_change "${args[@]}" proto tcp; then
            run_change "${args[@]}" proto udp || echo 'UDP request failed; any successful TCP rule remains.'
        else echo 'TCP request failed; UDP was not attempted. Review status for any partial changes.'; fi
    else
        run_change "${args[@]}"
    fi
    pause_screen
}
ssh_preflight() {
    local port client client_port server extra
    printf '\nSSH session detected. Before enabling, explicitly allow its TCP listening port.\n'
    if [ -n "${SSH_CONNECTION:-}" ]; then
        read -r client client_port server port extra <<< "$SSH_CONNECTION"
    fi
    if ! valid_single_port "${port:-}"; then
        read -r -p 'Actual SSH server port (empty cancels enabling): ' port || return 1
        valid_single_port "$port" || { echo 'Valid SSH port required; enabling cancelled.'; return 1; }
    fi
    printf 'Proposed access rule for SSH port %s:\n' "$port"
    print_command allow in proto tcp from any to any port "$port"
    printf 'This opens that TCP port from any address, not only this client.\n'
    printf 'Existing earlier deny rules can still prevent access. Review your rules first.\n'
    confirm_action_local 'Add this SSH allowance before enabling?' || return 1
    run_change allow in proto tcp from any to any port "$port" || return 1
    echo 'SSH allowance requested. This is not a guarantee of reconnectability.'
}
enable_firewall() {
    refresh_status || { printf '%s\nCannot determine UFW status; enabling cancelled.\n' "$status_text"; pause_screen; return; }
    [ "$firewall_state" != Active ] || { echo 'UFW is already active.'; pause_screen; return; }
    remote_warning
    printf 'This enables UFW now and its startup configuration. Existing policies/rules are retained.\n'
    printf 'Make sure required SSH/XRDP/VPN/service allowances exist BEFORE proceeding.\n'
    if [ -n "${SSH_CONNECTION:-}${SSH_TTY:-}${SSH_CLIENT:-}" ]; then
        ssh_preflight || { echo 'Enabling cancelled. Any approved SSH rule already added is retained.'; pause_screen; return; }
    fi
    confirm_action_local 'Enable UFW and startup protection?' || return
    # Preserve UFW's native prompt; never use --force to bypass SSH warnings.
    run_change enable
    pause_screen
}
disable_firewall() {
    remote_warning
    printf 'Disabling UFW removes its active protection and disables its startup configuration.\n'
    printf 'Saved UFW user rules are retained. This does not disable every other networking/firewall component.\n'
    confirm_action_local 'Disable UFW protection?' || return
    run_change disable
    pause_screen
}
manage_rules() {
    local listing fresh line number match='' normalized
    listing="$(ufw_read status numbered 2>&1)" || { printf '%s\n' "$listing"; pause_screen; return; }
    printf '\033[H\033[2JJS-Fortress: UFW numbered rules\n\n%s\n' "$listing"
    if [[ "$listing" != 'Status: active'* ]]; then
        printf '\nInactive UFW does not provide the active numbered-rule list.\n'
        printf 'Saved rules are shown below; this wrapper will NOT enable UFW just to remove a rule.\n\n'
        ufw_read show added
        pause_screen
        return
    fi
    printf '\nA numbered deletion removes ONE entry; separate IPv4/IPv6 entries remain separate.\n'
    read -r -p 'Rule number to remove (empty returns): ' number || return
    [ -n "$number" ] || return
    [[ "$number" =~ ^[0-9]{1,6}$ ]] || { echo 'Invalid rule number.'; pause_screen; return; }
    normalized=$((10#$number))
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*\[[[:space:]]*([0-9]+)\][[:space:]] ]]; then
            if ((10#${BASH_REMATCH[1]} == normalized)); then match="$line"; break; fi
        fi
    done <<< "$listing"
    [ -n "$match" ] || { echo 'That number is not in the displayed snapshot.'; pause_screen; return; }
    printf '\nRemove this exact displayed entry:\n%s\n' "$match"
    remote_warning
    confirm_action_local 'Remove this UFW rule?' || return
    fresh="$(ufw_read status numbered 2>&1)" || { echo 'Could not refresh rules; nothing deleted.'; pause_screen; return; }
    [ "$fresh" = "$listing" ] || { echo 'Rule list changed. Nothing deleted; reopen this menu and select again.'; pause_screen; return; }
    # Native confirmation stays enabled; no --force. Avoid simultaneous GUI edits.
    run_change delete "$normalized"
    pause_screen
}
configure_logging() {
    local selection level
    cursor_menu 'UFW logging:' selection 'Cancel' 'Off' 'Low (recommended)' 'Medium' || return
    case "$selection" in
        Off) level=off ;;
        'Low (recommended)') level=low ;;
        Medium) level=medium ;;
        *) return ;;
    esac
    print_command logging "$level"
    printf 'Log availability/storage depends on the host logging configuration.\n'
    confirm_action_local 'Apply this logging setting?' || return
    run_change logging "$level"
    pause_screen
}
export_report() {
    local destination section rc failed=0
    mkdir -p -- "$export_root" || { pause_screen; return; }
    destination="$(mktemp -d "$export_root/Firewall-UFW-$(date +%Y-%m-%d_%H-%M-%S).XXXXXX")" || { pause_screen; return; }
    {
        printf 'JS-Fortress: UFW Firewall Report\nExported: %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf 'Read-only UFW report; not a complete firewall backup or full kernel ruleset.\n'
        printf 'Review addresses, ports, and comments before sharing.\n'
        for section in version verbose numbered added; do
            printf '\n===== %s =====\n' "$section"
            case "$section" in
                version) ufw_read version ;;
                verbose) ufw_read status verbose ;;
                numbered) ufw_read status numbered ;;
                added) ufw_read show added ;;
            esac
            rc=$?
            printf '\nCommand exit status: %s\n' "$rc"
        done
    } > "$destination/report.txt" 2>&1 || failed=1
    if [ -f "$work_dir/actions.txt" ]; then
        cp -- "$work_dir/actions.txt" "$destination/session-actions.txt" || failed=1
    fi
    chmod 600 -- "$destination"/* || failed=1
    if [ "$failed" = 0 ]; then printf '\nExported private report folder:\n%s\n' "$destination"
    else printf '\nExport incomplete; review:\n%s\n' "$destination"; fi
    pause_screen
}
show_notes() {
    cat > "$work_dir/notes.txt" <<'NOTES'
JS-Fortress: UFW Firewall - Important Notes

This controller manages UFW only. It does not manage other firewall backends.
Opening the controller does not enable/disable UFW or rewrite policies/rules.
Native dependency installation may be offered by the shared JS-Forge runtime.

Enable/disable also changes UFW's startup configuration. Actual boot integration
still depends on the distribution's UFW package/init setup; no systemctl calls
or custom service/startup files are added by this wrapper.

Only incoming allow/deny rules are added here. Existing default policies,
forwarding rules, advanced rules, and interface settings are not rewritten.
Earlier matching rules can take precedence. Adding a deny does not override
an earlier allow. Check the numbered list when a rule does not behave as expected.

IPv6 behavior follows the host's UFW configuration; this wrapper does not turn
IPv6 support on/off. Review IPv4 and IPv6 entries independently.

When active, numbered deletion removes one displayed entry, not a v4/v6 pair.
When inactive, saved rules can be viewed, but numbered deletion is unavailable
in this wrapper. No automatic enabling is done to expose a numbered list.
Avoid editing rules simultaneously in this controller and another UFW frontend.
The pre-delete snapshot check is a safeguard, not an atomic transaction lock.

UFW validates source addresses and rules. Inputs are passed as Bash-array
arguments, never evaluated as shell commands. A successful command is not proof
that a port is reachable or blocked; verify status and test the actual connection.

SSH enable preflight uses SSH_CONNECTION's server port when available, otherwise
asks for it. It never assumes port 22. An approved rule opens that TCP port from
any source; earlier deny rules or custom rules can still prevent access.
SSH environment detection is best effort, not proof of whether access is remote.
XRDP/VPN/container access is not automatically detected or protected.
There is NO automatic rollback. Keep local/VM-console access available.

UFW status lists UFW-managed rules, not every rule in the kernel. Container/VPN
networking and other firewall tools may affect traffic outside this basic view.
Do not assume 'UFW inactive' means the host has no other packet filtering.

Exports are reports, not restore-ready backups. No reset, flush-all, automatic
rule cleanup, daemon management, or advanced backend integration is provided.
NOTES
    view_file "$work_dir/notes.txt"
}

# Startup: authorize inspection only. Never enable/disable or add rules here.
authorize_root || { pause_screen; exit 1; }
while :; do
    refresh_status || :
    printf '\033[H\033[2JJS-Fortress: Firewall\n\nBackend: UFW\nStatus: %s\n' "$firewall_state"
    if [ "$firewall_state" = Active ]; then
        while IFS= read -r status_line; do
            case "$status_line" in 'Default:'*|'Logging:'*) printf '%s\n' "$status_line" ;; esac
        done <<< "$status_text"
    elif [ "$firewall_state" = Unknown ]; then
        printf 'Status unavailable. View status for the actual diagnostic.\n'
    fi
    printf '\nNo automatic policy changes. Incoming-rule basics only.\n\n'
    cursor_menu 'Select an action:' selected \
        'View firewall status' 'Enable firewall' 'Disable firewall' \
        'View / remove existing rules' 'Allow a port or port range' \
        'Block a port or port range' 'Allow access from an IP address / subnet' \
        'Configure logging' 'Export firewall report' 'Read important notes' 'Exit' || break
    case "$selected" in
        'View firewall status') show_status ;;
        'Enable firewall') enable_firewall ;;
        'Disable firewall') disable_firewall ;;
        'View / remove existing rules') manage_rules ;;
        'Allow a port or port range') add_rule allow ;;
        'Block a port or port range') add_rule deny ;;
        'Allow access from an IP address / subnet') add_rule allow 1 ;;
        'Configure logging') configure_logging ;;
        'Export firewall report') export_report ;;
        'Read important notes') show_notes ;;
        Exit) break ;;
    esac
done
exit 0