#!/bin/bash
jsf_no_pause="1"
app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"
source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}
jsf_init_runtime_core

# Package names differ between the supported native backends.
case "$package_manager" in
    pacman|zypper)
        ssh_package="openssh"
        ;;
    apt)
        if [ -f /etc/pclinuxos-release ]; then
            ssh_package="openssh"
        else
            ssh_package="openssh-server"
        fi
        ;;
    dnf|yum)
        ssh_package="openssh-server"
        ;;
    *)
        echo "Unsupported native package manager: ${package_manager:-unknown}" >&2
        exit 1
        ;;
esac

jsf_require_all --native "$ssh_package" || exit 1

printf '\nOpenSSH server package installed or already present.\n'
printf 'Service startup follows your distribution/package defaults.\n'
printf 'No SSH configuration or firewall rules were changed by this script.\n'

if [ -t 0 ]; then
    read -r -p 'Press Enter to close...' _
fi
exit 0