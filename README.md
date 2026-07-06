# JS-Forge

JS-Forge is a Bash-based launcher and script runtime built around a hybrid TUI/GUI workflow, lightweight environment probing, and extension loading. The main script is designed to detect the current session type, validate the host environment, load compatible extensions, and present a navigable menu for running compatible scripts.

## Overview

The main script identifies itself as `JS-Forge.sh`, uses `JS-Forge` as the application name, and currently reports version `1.0.0 beta`. It is authored by JCore Studios & jcore92 and includes built-in branding, startup checks, menu rendering, and runtime utilities.

JS-Forge is structured to work as a portable Bash application rather than a traditional packaged desktop program. Its core responsibilities are environment detection, dependency checks, menu generation, extension discovery, and script execution.

## Core behavior

At startup, the script determines whether it is running in terminal mode or GUI mode by checking whether standard input is attached to a terminal, then sets `tui_flag` or `gui_flag` accordingly. It stores key runtime locations such as a temp directory under `/tmp/JS-Forge` and a script root at `~/.JS-Forge`.

The `variables()` function acts as the central initializer for application metadata, runtime flags, locations, extension menu arrays, package-manager helpers, and GUI sizing presets. This function is the foundation of the application lifecycle and is loaded before the main runtime path proceeds.

## Main functions

### `variables()`

Initializes app identity, version values, mode flags, extension arrays, filesystem locations, package-manager bridge variables, and GUI defaults. It also contains helper routines for resolving extension directories and desktop-session context.

### `resolve_extension_dirs()`

Builds the list of extension search paths from the current script directory, the user extension path under `~/.local/share/JS-Forge/Extensions`, and an AppImage-aware path under `$APPDIR/usr/share/JS-Forge/Extensions` when available. This allows JS-Forge to support portable, user, and AppImage-backed extension locations.

### `detect_display_server()` and `detect_desktop_environment()`

These functions inspect the running Linux session and report values such as Wayland, X11, XWayland / Wayland, XLibre, or headless/SSH-oriented states. The desktop-environment detector checks common environment variables and falls back to process inspection and `xprop` when needed.

### `center()`, `print_red()`, `divider()`, `cursor_menu()`, and `text_delay()`

These functions provide the main TUI presentation layer. They handle centered text output, red-colored warning output, full-width separators, keyboard-driven cursor menus, and paced terminal output for a more polished command-line experience.

### Banner functions

`jcorestudios_banner()`, `jcore92_banner()`, and `JS-Forge_banner()` render the built-in ASCII/Unicode title art shown during startup and scene transitions. These functions are used throughout the TUI flow to reinforce branding and improve presentation.

### `entertocontinue()` and `endprog()`

These functions provide simple flow control for pausing and exiting. `entertocontinue()` renders a centered prompt and waits for input, while `endprog()` exits the script.

### `credits()`

Displays the application credits and About information in either Zenity or terminal form depending on the active mode. It includes version information, licensing text, project presentation links, and author credits.

### `eula_prompt()`

Shows the MIT License text to the user at startup using `less` in TUI mode or `zenity --text-info` in GUI mode. In the current script, it acts as the startup legal/notice gate before the rest of the application continues.

### `xprobe()`

`xProbe` is the environment analysis and dependency-validation routine. It checks for unsupported conditions such as raw TTY sessions, WSL, and unsupported package managers, reports OS and display information, validates required tools, and can attempt package installation through package-manager-specific helper commands.

### `load_extensions()`

Searches resolved extension directories for `.ext` files, sources them, and records successful loads in the `xprob_messages` report buffer. If no extensions are found, the script reports that condition and continues accordingly.

### `is_runnable_script()`, `run_selected_script()`, `view_script_source()`, and `browse_menu()`

These functions implement the runtime browsing and execution model. They identify compatible scripts, run selected files, allow source viewing through `nano`, and drive the nested main menu that mixes directories, runnable scripts, built-in actions, and extension menu entries.

## Runtime flow

When launched normally with no startup switch, the script initializes variables, shows the MIT license prompt, runs `xProbe`, loads extensions, and then enters the main browser menu rooted at `app_script_folder_loc`. In GUI mode, progress feedback is shown through Zenity; in TUI mode, the flow is rendered directly in the terminal with banners, centered text, and cursor-based menu navigation.

The browser menu can expose subdirectories, runnable scripts, About information, the xProbe report, and any extension-provided entries that were added to the extension menu arrays. The script then exits through the credits scene and final cleanup flow when the user chooses to leave the application.

## Startup switches

The script includes a `-s` switch that loads the runtime environment and presents a lightweight script-runtime scene, which is useful when the file is sourced or invoked for environment setup behavior. It also contains a `-t` testing/install-oriented path intended for installation runtime checks, though that path is clearly still marked as not ready in the current version.

## Dependency model

JS-Forge detects a supported package manager from `apt`, `dnf`, `yum`, `pacman`, or `zypper` and builds helper commands such as `pkgmngr_install` and `pkgmngr_refresh` from that result. The dependency check inside `xprobe()` currently validates tools including `flatpak`, `zenity`, `nano`, `git`, `jq`, `tput`, `chsh`, and `xdg-open`.

For Debian and Ubuntu-derived systems, the script treats the package-manager bridge as disabled because `apt` is already available; for other supported package-manager families, it reports that the bridge is enabled. Missing dependencies can trigger an interactive install path depending on the current mode and available terminal environment.

## Extension support

JS-Forge supports dynamically sourced `.ext` files and maintains extension menu labels, actions, and order through global arrays declared during initialization. In the current intended release direction, the updater extension is the primary extension expected to be documented and shipped alongside the main script.

The extension loader supports three search patterns: portable extensions beside the script, user extensions in `~/.local/share/JS-Forge/Extensions`, and AppImage-bundled extensions when `APPDIR` is present. This makes the script adaptable to multiple distribution models without hardwiring a single install path.

## Interface design

The TUI emphasizes centered banners, cursor-driven menus, explicit separators, and readable diagnostics. The GUI path uses Zenity for selection windows, progress dialogs, text viewers, and notifications, allowing the same main script to behave like a lightweight desktop tool when launched outside a terminal.

This dual-mode approach is one of the defining characteristics of the project. JS-Forge is not just a script runner; it is a Bash-driven shell application framework with its own startup pipeline, validation layer, and navigation model.

## Current scope

At its current version, JS-Forge is best understood as an open Bash framework for launching and organizing compatible scripts with built-in environment checks, optional extension support, and a branded interactive shell experience. Its main script already handles much of the hard infrastructure work: probing the system, preparing the runtime, loading extensions, and presenting the action menu.

## Suggested repository contents

A practical GitHub repository layout for the current project would include:

- `JS-Forge.sh` as the main entry point.
- A `LICENSE` file containing the MIT License text referenced by the script’s EULA prompt.
- This README to explain the runtime model, features, and function layout.
- The updater extension as the documented extension shipped with the main project direction.

## Usage

Example local execution:

```bash
chmod +x JS-Forge.sh
./JS-Forge.sh
```

Example runtime-environment switch:

```bash
./JS-Forge.sh -s
```

Example testing/install path:

```bash
./JS-Forge.sh -t
```

## Notes

The script is Linux-oriented and explicitly rejects unsupported raw TTY launches and WSL execution in the current implementation. It also depends on external utilities and terminal/desktop behavior that make it best suited to standard Linux desktop environments with common command-line tools installed.
