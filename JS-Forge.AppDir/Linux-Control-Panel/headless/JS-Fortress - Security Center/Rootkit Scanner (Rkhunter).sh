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
jsf_require_all --native rkhunter || exit 1
scanner="$(command -v rkhunter)" || { echo 'rkhunter is unavailable. Check your native repositories/install output.' >&2; exit 1; }
declare -F cursor_menu >/dev/null || { echo 'Runtime cursor_menu function not found.' >&2; exit 1; }

tool_title='Rootkit Hunter'
export_prefix='RKHunter'
export_root="$HOME/JS-Forge-Exports"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/jsforge-rkhunter.XXXXXX")" || exit 1
private_dir=''

pause_screen() { printf '\n'; read -r -p 'Press Enter to continue...' _reply; }
as_root() { if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi; }
authorize_root() {
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || { echo 'sudo is required for the check.' >&2; return 1; }
        sudo -v || return 1
    fi
}

remove_private_log() {
    [ -n "$private_dir" ] || return 0
    if as_root rm -f -- "$private_dir/rkhunter.log" "$private_dir/rkhunter.log.old" && as_root rmdir -- "$private_dir"; then
        private_dir=''
    else
        printf 'Private log workspace remains at: %s\n' "$private_dir" >&2
        return 1
    fi
}

cleanup() {
    remove_private_log
    rm -f -- "$work_dir"/*
    rmdir -- "$work_dir" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

view_file() {
    if [ ! -f "$1" ]; then echo 'No results yet. Run the check first.'; pause_screen; return; fi
    if command -v less >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        LESSSECURE=1 LESSHISTFILE=- less -- "$1"
    else cat -- "$1"; pause_screen; fi
}

make_findings() {
    {
        printf 'JS-Fortress: %s - Review Aid\n\n' "$tool_title"
        printf 'These are keyword matches from the latest check, NOT a confirmed-infection list.\n'
        printf 'Read full output and logs for context. No matches does not prove the host is clean.\n'
        printf 'Warnings may reflect normal system configuration or legitimate package changes.\n'
        printf 'Exit status alone is not a verdict. An interrupted scan is incomplete.\n\n'
        grep -nE '(^|[^[:alpha:]])(Warning|WARNING|INFECTED|Suspicious|suspicious)([^[:alpha:]]|$)' "$work_dir/check-output.txt" || :
    } > "$work_dir/findings.txt"
}

export_results() {
    local destination file
    local -a files=()
    for file in "$work_dir"/*; do [ -f "$file" ] && files+=("$file"); done
    if [ "${#files[@]}" -eq 0 ]; then echo 'No results to export yet.'; pause_screen; return; fi
    mkdir -p -- "$export_root" || return 1
    destination="$(mktemp -d "$export_root/$export_prefix-$(date +%Y-%m-%d_%H-%M-%S).XXXXXX")" || return 1
    for file in "${files[@]}"; do
        cp -- "$file" "$destination/" || { echo "Export incomplete: $destination" >&2; pause_screen; return 1; }
    done
    printf '\nExported to:\n%s\n' "$destination"
    printf 'Reports may include usernames, paths, and network/system details. Review before sharing.\n'
    pause_screen
}

show_notes() {
    printf '\033[H\033[2JJS-Fortress: Rootkit Check Notes\n\n'
    printf 'These tools look for signs of known rootkits and suspicious system changes.\n'
    printf 'A warning is not proof of compromise. No warnings is not proof of a clean host.\n'
    printf 'A compromised host can mislead tools running on that same host.\n'
    printf 'Investigate findings; do not automatically delete/quarantine flagged system files.\n'
    printf 'For a suspected compromise, preserve evidence and investigate using trusted media/tools.\n'
    printf 'This wrapper does not remove rootkits, change firewall rules, whitelist warnings,\n'
    printf 'schedule jobs, or create/reset rkhunter file-property baselines.\n'
    printf 'Native package installation may apply the distribution package defaults.\n\n'
    printf 'Results stay temporary until you export. Export before exit or rerunning a check.\n'
    pause_screen
}

run_job() {
    local mode="$1" interrupted=0 result
    local -a args=() status
    case "$mode" in
        check) args=(--check --skip-keypress --nocolors) ;;
        update) args=(--update --nocolors) ;;
        config) args=(--config-check --nocolors) ;;
        *) return 1 ;;
    esac
    authorize_root || { pause_screen; return; }
    remove_private_log || { pause_screen; return; }
    private_dir="$(as_root mktemp -d /var/tmp/jsforge-rkhunter-log.XXXXXX)" || return 1
    {
        printf 'JS-Fortress: Rootkit Hunter\nOperation: %s\nStarted: %s\n\n' "$mode" "$(date '+%Y-%m-%d %H:%M:%S %Z')"
        printf 'Warnings require review. No baseline refresh or automatic remediation requested.\n\n'
    } > "$work_dir/$mode-output.txt"
    rm -f -- "$work_dir/$mode-rkhunter.log"
    if [ "$mode" = check ]; then rm -f -- "$work_dir/findings.txt"; fi
    cat -- "$work_dir/$mode-output.txt"
    trap 'interrupted=1' INT
    as_root "$scanner" "${args[@]}" --logfile "$private_dir/rkhunter.log" --noappend-log 2>&1 |
        tee -a "$work_dir/$mode-output.txt"
    status=("${PIPESTATUS[@]}")
    trap 'exit 130' INT
    result="${status[0]}"
    {
        printf '\nFinished: %s\nTool exit status: %s | Capture status: %s\n' "$(date '+%Y-%m-%d %H:%M:%S %Z')" "$result" "${status[1]}"
        if [ "$interrupted" = 1 ]; then echo 'Interrupted: results are incomplete.'
        elif [ "$mode" = update ]; then
            case "$result" in
                0) echo 'Updater reports no updates were available.' ;;
                2) echo 'Updater reports updates were installed successfully.' ;;
                *) echo 'Update failed or did not finish normally; review the output.' ;;
            esac
        elif [ "$result" -ne 0 ]; then
            echo 'The tool reported warnings/errors or abnormal completion. Review the full output and log.'
        else echo 'Command completed. Review findings, test coverage, and the full log; this is not proof of a clean host.'; fi
        if [ "${status[1]}" -ne 0 ]; then echo 'Capture failed; the saved output may be incomplete.'; fi
    } | tee -a "$work_dir/$mode-output.txt"
    if as_root test -f "$private_dir/rkhunter.log"; then
        if ! as_root cat -- "$private_dir/rkhunter.log" > "$work_dir/$mode-rkhunter.log"; then
            printf 'Could not copy detailed log. Preserved at: %s/rkhunter.log\n' "$private_dir"
            private_dir=''
            [ "$mode" = check ] && make_findings
            pause_screen
            return
        fi
    fi
    remove_private_log
    [ "$mode" = check ] && make_findings
    pause_screen
}

while :; do
    printf '\033[H\033[2JJS-Fortress: Rootkit Hunter\n\n'
    printf 'Visible checks, manual data updates, findings review, and export.\n'
    printf 'No automatic --propupd: never trust changed files merely to silence warnings.\n\n'
    cursor_menu 'Select an action:' selected \
        'Run rootkit / system check' 'Update rkhunter data files' 'Validate rkhunter configuration' \
        'View latest check findings' 'View full check output' 'View detailed check log' \
        'View latest update output' 'Export current results' 'Show tool version' 'Read important notes' 'Exit' || break
    case "$selected" in
        'Run rootkit / system check') run_job check ;;
        'Update rkhunter data files') run_job update ;;
        'Validate rkhunter configuration') run_job config ;;
        'View latest check findings') view_file "$work_dir/findings.txt" ;;
        'View full check output') view_file "$work_dir/check-output.txt" ;;
        'View detailed check log') view_file "$work_dir/check-rkhunter.log" ;;
        'View latest update output') view_file "$work_dir/update-output.txt" ;;
        'Export current results') export_results ;;
        'Show tool version') "$scanner" --version; pause_screen ;;
        'Read important notes') show_notes ;;
        Exit) break ;;
    esac
done
exit 0