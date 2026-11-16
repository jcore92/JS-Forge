#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
	echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
	exit 1
}

jsf_init_runtime_core

pia_download_page="https://www.privateinternetaccess.com/download/linux-vpn"
pia_download_dir="${XDG_DOWNLOAD_DIR:-$HOME/Downloads}"

get_pia_linux_installer_url() {
	curl --silent --show-error --fail \
		--location \
		"$pia_download_page" |
		grep -oE \
			'https://installers\.privateinternetaccess\.com/download/pia-linux-[0-9][^"]*\.run' |
		head -n 1
}

start_pia_service_for_legacy_init() {
	local init_name
	local service_dir="/etc/service/piavpn"
	local runit_service_dir="/etc/sv/piavpn"
	local sysv_service="/etc/init.d/piavpn"

	init_name="$(ps -p 1 -o comm= 2>/dev/null | tr -d '[:space:]')"

	case "$init_name" in
	systemd)
		echo "Systemd detected. PIA service startup is handled by the normal systemd flow."
		return 0
		;;
	runit)
		echo "runit detected. Enabling and starting the piavpn service..."

		if [ -d "$service_dir" ]; then
			echo "piavpn is already enabled through runit."
			return 0
		fi

		if [ -d "$runit_service_dir" ]; then
			$sudocmd ln -s "$runit_service_dir" "$service_dir" || {
				echo "Could not enable the piavpn runit service."
				return 1
			}

			echo "piavpn was enabled through runit."
			return 0
		fi

		echo "Could not find a runit service definition for piavpn."
		return 1
		;;
	init | sysvinit)
		echo "SysVinit detected. Starting the piavpn service..."

		if [ -x "$sysv_service" ]; then
			$sudocmd service piavpn start || $sudocmd "$sysv_service" start || {
				echo "Could not start the piavpn SysV service."
				return 1
			}

			echo "piavpn service started."
			return 0
		fi

		echo "Could not find the SysVinit service script: $sysv_service"
		return 1
		;;
	*)
		echo "Detected init system: ${init_name:-unknown}"
		echo "No automatic PIA service action is configured for this init system."
		return 0
		;;
	esac
}

install_pia_linux() {
	local selection
	local options=(
		"Continue with official PIA installer"
		"Cancel"
	)

	distro_family="$(jsf_detect_distro_family)"

    case "$distro_family" in
    arch)
        echo "PIA official installer does not currently work on Artix. Instead, please use WireGuard or OpenVPN configurations and Clients. Exiting..."
		sleep 7
		exit
        ;;
    *)
        sleep .1
        ;;
    esac

	clear
	echo "Private Internet Access VPN Installer"
	divider
	echo "Third-party installer warning"
	echo ""
	echo "This action downloads and runs the official Private Internet Access"
	echo "Linux installer from privateinternetaccess.com."
	echo ""
	echo "The installer can make system-level changes and may request your"
	echo "administrator password."
	echo ""
	echo "Continue only if you trust Private Internet Access and want to"
	echo "install its VPN client on this computer."
	echo ""

	cursor_menu "Continue?" selection "${options[@]}"

	[ "$selection" = "Continue with official PIA installer" ] || {
		echo "PIA installation cancelled."
		return 0
	}

	local installer_url
	local installer_path

	echo "Finding the latest Private Internet Access Linux installer..."

	installer_url="$(get_pia_linux_installer_url)" || {
		echo "Could not contact the PIA Linux download page."
		return 1
	}

	[ -n "$installer_url" ] || {
		echo "Could not locate the current PIA Linux installer URL."
		return 1
	}

	mkdir -p "$pia_download_dir" || return 1

	installer_path="$pia_download_dir/$(basename "$installer_url")"

	echo "Downloading: $(basename "$installer_url")"

	curl --fail --location \
		--connect-timeout 15 \
		--max-time 900 \
		"$installer_url" \
		--output "$installer_path" || {
		echo "Could not download the PIA Linux installer."
		return 1
	}

	chmod +x "$installer_path" || {
		echo "Could not make the PIA installer executable."
		return 1
	}

	echo "Starting the official PIA installer..."
	echo "The installer may request your password for system-level setup."

	bash "$installer_path"

	sleep 2

	#env XDG_SESSION_TYPE=X11 /opt/piavpn/bin/pia-client %u 2>&1 &
	setsid /opt/piavpn/bin/pia-client %u >/dev/null 2>&1 &
	disown 2>/dev/null || true

	sleep 2

	if [ "$?" -eq 0 ]; then
		start_pia_service_for_legacy_init
	else
		echo "The PIA installer did not finish successfully."
		return 1
	fi
}

install_pia_linux
