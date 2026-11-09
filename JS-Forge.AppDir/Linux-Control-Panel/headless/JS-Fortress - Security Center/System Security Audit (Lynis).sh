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

export PATH="$PATH:/usr/local/sbin:/usr/sbin:/sbin"

jsf_require_all --native lynis || exit 1

export_root="$HOME/JS-Forge-Exports"
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/jsforge-lynis.XXXXXX")" || exit 1
private_dir=''

as_root() {
    if (( EUID == 0 )); then "$@"; else sudo -- "$@"; fi
}

remove_private_files() {
    [ -n "$private_dir" ] || return 0
    if as_root rm -f -- "$private_dir/lynis.log" "$private_dir/lynis-report.dat" &&
       as_root rmdir -- "$private_dir"; then
        private_dir=''
    else
        printf 'Could not remove private audit workspace: %s\n' "$private_dir" >&2
        return 1
    fi
}

cleanup() {
    remove_private_files
    rm -f -- "$work_dir/console.txt" "$work_dir/lynis.log" \
        "$work_dir/lynis-report.dat" "$work_dir/summary.txt"
    rmdir -- "$work_dir" 2>/dev/null || :
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

view_file() {
    if command -v less >/dev/null 2>&1 && [ -t 0 ] && [ -t 1 ]; then
        LESSSECURE=1 LESSHISTFILE=- less -- "$1"
    else
        cat -- "$1"
    fi
}

make_summary() {
    {
        printf 'JS-Forge: Lynis Security Audit\n'
        printf 'Collected: %s\n' "$audit_time"
        printf 'Lynis command exit status: %s\n' "$audit_status"
        printf 'Screen capture exit status: %s\n\n' "$capture_status"
        printf 'Review findings in context; a hardening index is not proof of security.\n'
        printf 'This wrapper does not apply hardening changes or request data upload.\n\n'
        if [ -s "$work_dir/lynis-report.dat" ]; then
            awk '
                /^lynis_version=|^hardening_index=|^tests_performed=/ {print}
                /^warning\[\]=/ {warnings++}
                /^suggestion\[\]=/ {suggestions++}
                END {printf "\nWarnings: %d\nSuggestions: %d\n", warnings, suggestions}
            ' "$work_dir/lynis-report.dat"
            printf '\nWARNINGS\n'
            awk '/^warning\[\]=/ {sub(/^[^=]*=/, ""); print}' "$work_dir/lynis-report.dat"
            printf '\nSUGGESTIONS\n'
            awk '/^suggestion\[\]=/ {sub(/^[^=]*=/, ""); print}' "$work_dir/lynis-report.dat"
            printf '\nNative finding fields are preserved, separated by | where applicable.\n'
        else
            printf 'No native report was produced or could be copied.\n'
            printf 'Review console.txt for errors; this is NOT a clean audit result.\n'
        fi
        printf '\nEXPORT CONTENTS\n'
        printf 'summary.txt       Audit status, warning/suggestion counts, and findings\n'
        printf 'console.txt       Visible audit output (without color codes)\n'
        printf 'lynis.log         Detailed Lynis log, if available\n'
        printf 'lynis-report.dat  Native Lynis findings/data, if available\n'
        printf '\nReports may contain sensitive host, account, and network information.\n'
        printf 'Review/redact them before sharing. Incomplete scans may have partial results.\n'
    } > "$work_dir/summary.txt"
}

run_audit() {
    local file
    local pipeline_status=()
    if (( EUID != 0 )); then
        command -v sudo >/dev/null 2>&1 || { echo 'sudo is required for the full audit.' >&2; return 1; }
        sudo -v || return 1
    fi
    remove_private_files || return 1
    # Root writes only inside a fresh private directory, not a user-writable export path.
    private_dir="$(as_root mktemp -d /var/tmp/jsforge-lynis-root.XXXXXX)" || return 1
    rm -f -- "$work_dir/console.txt" "$work_dir/lynis.log" \
        "$work_dir/lynis-report.dat" "$work_dir/summary.txt"
    audit_time="$(date '+%Y-%m-%d %H:%M:%S %Z')"
    printf '\nRunning Lynis system audit with administrative access.\n'
    printf 'Results appear below. Export is offered when the audit finishes.\n\n'
    as_root lynis audit system --quick --no-colors \
        --log-file "$private_dir/lynis.log" \
        --report-file "$private_dir/lynis-report.dat" 2>&1 |
        tee "$work_dir/console.txt"
    pipeline_status=("${PIPESTATUS[@]}")
    audit_status="${pipeline_status[0]}"
    capture_status="${pipeline_status[1]}"
    for file in lynis.log lynis-report.dat; do
        if as_root test -f "$private_dir/$file"; then
            if ! as_root cat -- "$private_dir/$file" > "$work_dir/$file"; then
                printf 'Failed to copy %s; retaining the private workspace and stopping.\n' "$file" >&2
                # Do not delete the remaining source files on this failure.
                printf 'Private workspace: %s\n' "$private_dir" >&2
                private_dir=''
                return 1
            fi
        fi
    done
    remove_private_files || return 1
    make_summary
    printf '\nAudit command finished (status %s).\n' "$audit_status"
    if [ "$audit_status" -ne 0 ] || [ "$capture_status" -ne 0 ]; then
        printf 'There was an audit/capture error. Review the output; results may be incomplete.\n'
    fi
    printf 'Use V for findings, C for the full screen output, or E to export.\n'
}

export_audit() {
    local destination file
    mkdir -p -- "$export_root" || return 1
    destination="$(mktemp -d "$export_root/Lynis-$(date +%Y-%m-%d_%H-%M-%S).XXXXXX")" || return 1
    for file in summary.txt console.txt lynis.log lynis-report.dat; do
        if [ -f "$work_dir/$file" ]; then
            cp -- "$work_dir/$file" "$destination/$file" || {
                printf 'Export incomplete; check: %s\n' "$destination" >&2
                return 1
            }
        fi
    done
    printf '\nAudit exported to:\n%s\n' "$destination"
    printf 'Keep these files private; redact sensitive details before sharing.\n'
}

printf '\nJS-Forge: Lynis Security Audit\n'
printf 'Installs Lynis if needed, then audits this machine.\n'
printf 'No automatic hardening, firewall changes, or scheduled jobs are added.\n'
run_audit || exit 1

while :; do
    printf '\n[V] Findings  [C] Full output  [E] Export  [R] Run again  [Q] Quit\n'
    read -r -p 'Choose: ' choice || break
    case "$choice" in
        v|V) view_file "$work_dir/summary.txt" ;;
        c|C) view_file "$work_dir/console.txt" ;;
        e|E) export_audit ;;
        r|R) run_audit || exit 1 ;;
        q|Q|'') break ;;
        *) echo 'Choose V, C, E, R, or Q.' ;;
    esac
done
exit 0