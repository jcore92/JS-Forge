#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
jsf_require_all --native lf whiptail || exit 1

if (( EUID == 0 )); then
    lf "/"
    exit $?
fi

# Keep dialog drawing on the terminal and capture only whiptail's stderr result.
# Allocate our own descriptor; never overwrite inherited descriptor 3.
exec {lf_ui_fd}>&2
selection=$(whiptail     --title "JS-Forge: LF File Manager"     --default-item "user"     --cancel-button "Cancel"     --menu "Choose how to open LF.

Root mode can modify or delete system files. Use only when needed."     16 76 2     "user" "Current User - Home directory"     "root" "Root - System files (administrator access)"     2>&1 1>&"$lf_ui_fd")
selection_status=$?
exec {lf_ui_fd}>&-

[ "$selection_status" -eq 0 ] || exit 0

case "$selection" in
    user) lf -command 'set mouse true' "$HOME" ;;
    root) sudo -H lf -command 'set mouse true' "/" ;;
esac