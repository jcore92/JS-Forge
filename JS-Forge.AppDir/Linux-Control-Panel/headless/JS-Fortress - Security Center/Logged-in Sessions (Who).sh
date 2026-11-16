#!/bin/bash
# Original who-rdp report and kick commands, driven by JS-Forge's cursor_menu.
jsf_no_pause="1"
app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"
source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}
jsf_init_runtime_core

INTERVAL=5
kick_user="${USER:-$(id -un)}"
declare -a action_labels action_types action_targets local_pids rdp_pids

pause_screen() {
    printf '\n'
    read -r -p 'Press Enter to continue...' _reply
}

collect() {
    local pid user terminal uptime
    who_snapshot="$(LC_ALL=C who -a)"
    ps_snapshot="$(LC_ALL=C ps -eo user:64,pid,etime,comm --no-headers)"
    local_pids=(); rdp_pids=()
    action_labels=("ALL $kick_user processes/sessions - pkill -u $kick_user")
    action_types=(user)
    action_targets=("$kick_user")

    # Preserve the original who -a / penultimate numeric field PID collection.
    while IFS=$'\t' read -r pid user terminal; do
        local_pids+=("$pid")
        action_labels+=("Local/Console: $user | $terminal | PID $pid")
        action_types+=(group)
        action_targets+=("$pid")
    done < <(printf '%s\n' "$who_snapshot" |
        awk '$(NF-1) ~ /^[0-9]+$/ {tty=($2=="+" || $2=="-" ? $3 : $2); printf "%s\t%s\t%s\n",$(NF-1),$1,tty}')

    while read -r user pid uptime; do
        rdp_pids+=("$pid")
        action_labels+=("XRDP: $user | PID $pid | up $uptime")
        action_types+=(group)
        action_targets+=("$pid")
    done < <(printf '%s\n' "$ps_snapshot" |
        awk '$4=="xrdp-chansrv" {print $1,$2,$3}')
}

report() {
    local pid rdp
    printf '\033[H\033[2J'
    printf 'Logged-on sessions - %s\n\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    echo '===================== Kick Commands ====================='
    printf 'pkill -u %s # ALL %s processes/sessions\n' "$kick_user" "$kick_user"
    for pid in "${local_pids[@]}"; do
        printf 'kill -- -$(ps -o pgid= -p %s | xargs) # Local/Console\n' "$pid"
    done
    for pid in "${rdp_pids[@]}"; do
        printf 'kill -- -$(ps -o pgid= -p %s | xargs) # XRDP\n' "$pid"
    done
    printf '\n==================== LOCAL / CONSOLE ====================\n'
    printf '%s\n' "$who_snapshot"
    printf '\n==================== REMOTE (XRDP) ======================\n'
    rdp="$(printf '%s\n' "$ps_snapshot" |
        awk '$4=="xrdp-chansrv" {printf "%-20s pid %-8s up %s\n",$1,$2,$3}')"
    if [ -n "$rdp" ]; then printf '%s\n' "$rdp"; else echo '(no RDP sessions)'; fi
}

run_privileged() {
    if (( EUID == 0 )); then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo -- "$@"
    else
        "$@"
    fi
}

run_action() {
    local index="$1" target="${action_targets[$1]}" pgid answer result
    local -a command_args
    if [ "${action_types[index]}" = user ]; then
        command_args=(pkill -u "$target")
    else
        # This is the same PID -> PGID -> negative-PGID kill as the original.
        pgid="$(ps -o pgid= -p "$target" | xargs)"
        if ! [[ "$pgid" =~ ^[0-9]+$ ]] || (( pgid <= 1 )); then
            echo 'That PID has no usable process group now. Refresh the list.'
            pause_screen
            return
        fi
        command_args=(kill -- "-$pgid")
    fi
    printf '\033[H\033[2J'
    printf '%s\n\n' "${action_labels[index]}"
    printf 'Command: '
    printf '%q ' "${command_args[@]}"
    printf '\n\nYour own session is allowed. The tool/connection may close immediately.\n'
    if [ "${action_types[index]}" = user ]; then
        printf 'pkill -u targets ALL matching user processes, not just login sessions.\n'
    else
        printf 'The kill targets the process group, as in your original script.\n'
    fi
    printf 'Unsaved work may be lost.\n\n'
    cursor_menu 'Run this command?' answer 'Cancel' 'Run selected command' || return
    [ "$answer" = 'Run selected command' ] || return 0
    run_privileged "${command_args[@]}"
    result=$?
    printf '\nCommand returned status %s.\n' "$result"
    pause_screen
}

watch_report() {
    local key
    while :; do
        collect
        report
        printf '\nRefreshing every %s seconds. Q or Enter returns.\n' "$INTERVAL"
        if read -r -s -n 1 -t "$INTERVAL" key; then
            case "$key" in q|Q|'') break ;; esac
        elif [ ! -t 0 ]; then break; fi
    done
}

case "${1:-}" in
    -1) collect; report; exit 0 ;;
    --watch) watch_report; exit 0 ;;
    -h|--help)
        echo 'Default: native cursor menu for the original kick commands.'
        echo '-1: one-shot original report. --watch: live report.'
        exit 0 ;;
    '') ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
esac

declare -F cursor_menu >/dev/null || { echo 'Runtime cursor_menu function not found.' >&2; exit 1; }
while :; do
    collect
    report
    printf '\n'
    menu=("${action_labels[@]}" 'Refresh' 'Watch report' 'Exit')
    cursor_menu 'Select the kick command to run:' selected "${menu[@]}" || break
    case "$selected" in
        Refresh) continue ;;
        'Watch report') watch_report ;;
        Exit) break ;;
        *)
            for ((n=0; n<${#action_labels[@]}; n++)); do
                if [ "$selected" = "${action_labels[n]}" ]; then
                    run_action "$n"
                    break
                fi
            done ;;
    esac
done
exit 0