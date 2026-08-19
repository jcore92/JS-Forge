# JS-Forge

**Version 1.2.0**

JS-Forge is a Bash application framework, launcher, and workflow automation tool for Linux. It combines a terminal UI, optional Zenity dialogs, environment probing, extension loading, package and Flatpak helpers, Git-backed script intake, and reusable GitHub AppImage installation support.

It is built for people who want to run curated scripts and for builders who want to create Linux tools, automation flows, and utility packs without rebuilding the same Bash infrastructure in every script.

## What it does

JS-Forge provides a branded shell application with a startup pipeline, dependency checks, extension menus, and a browser rooted in the user's script folder.

At launch, it initializes runtime variables, detects TUI or GUI mode, gathers system information, shows a version-gated MIT license prompt when required, runs xProbe, loads `.ext` extensions, and opens the main browser/menu flow.

## Core features

- Hybrid TUI/GUI behavior using terminal UI helpers and Zenity dialogs.
- A portable `runtime-core.lib` shared by standalone scripts and extensions.
- Native-package and Flatpak dependency helpers through `jsf_require_all`.
- GitHub AppImage installation through `jsf_install_github_appimage`.
- Package-manager-specific script visibility for `.apt`, `.dnf`, `.yum`, `.pacman`, and `.zypper` scripts.
- Extension loading from portable, AppImage, and optional user extension paths.
- Environment and dependency reporting through xProbe.
- Terminal-launch helpers for GUI-mode scripts that still need a shell session.
- Default paused installer behavior and optional no-pause launcher behavior.
- GitEngine repository-list, clone, pull, and delete workflows.
- GitHub release update checks.
- Emoji/font repair and optional diagnostic warning modules.

## Project layout

| File | Purpose |
|---|---|
| `AppRun` | Main launcher, metadata, UI-mode detection, branding, EULA flow, extension loading, browser/menu flow, and runtime bootstrapping. |
| `runtime-core.lib` | Shared terminal UI, package-manager, dependency, extension-path, terminal-launch, and GitHub AppImage helpers. |
| `01-xprobe.ext` | Environment report and dependency/Flatpak checks. |
| `02-gitengine.ext` | Repository-list-driven clone, pull, and delete workflow. |
| `03-updates.ext` | GitHub release update checker. |
| `04-emoji-support.ext` | Emoji and fontconfig repair helper. |
| `05-systemd-warning.ext` | Example systemd policy warning module. |
| `06-wayland-warning.ext` | Example Wayland policy warning module. |

## Getting started

Run JS-Forge locally:

```bash
chmod +x AppRun
./AppRun
```

After `AppRun` bootstraps the runtime library, scripts can source it from:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib
```

## Runtime model

`jsf_init_runtime_core` prepares the application data directory, temporary directory, extension search paths, privilege model, package-manager helpers, and shared runtime variables.

`jsf_require_all` provides a consistent way for scripts to request native packages, Flatpaks, or both.

### Base script template

Use this as the starting point for a normal JS-Forge script:

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

# Script actions go below this line.
```

### Native dependency example

Use `--native` when a script needs additional command-line tools or distribution packages.

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all --native ffmpeg imagemagick

# Script actions that use ffmpeg and imagemagick go below this line.
```

A larger native dependency list works the same way:

```bash
jsf_require_all --native git rsync yq curl jq
```

The runtime checks each command, maps common command names to distro-specific package names when necessary, and installs missing packages through the detected package manager.

### Flatpak dependency example

Use `--flatpak` when a script needs one or more Flatpak application IDs.

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all --flatpak org.keepassxc.KeePassXC

# Script actions that use KeePassXC go below this line.
```

Multiple Flatpaks can be requested together:

```bash
jsf_require_all --flatpak \
    org.keepassxc.KeePassXC \
    com.github.tchx84.Flatseal
```

The runtime checks installed user Flatpaks, adds Flathub if needed, and installs missing application IDs.

### Native and Flatpak example

A script can request both native tools and Flatpak applications in one call:

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
    --native ffmpeg yt-dlp \
    --flatpak org.videolan.VLC

# Script actions that use ffmpeg, yt-dlp, and VLC go below this line.
```

Keep every dependency after its matching marker: `--native` for native commands and `--flatpak` for Flatpak application IDs.

### When to use jsf_require_all

Use `jsf_require_all` for dependencies specific to the script you are writing.

xProbe already verifies JS-Forge's normal startup toolchain. A script launched through normal JS-Forge startup does not need to repeat checks for tools that xProbe already guarantees. Explicitly requesting a dependency is still valid when a script needs to run outside the normal JS-Forge startup flow.

## GitHub AppImage installation

JS-Forge 1.2.0 adds `jsf_install_github_appimage`, a shared runtime helper for AppImages published through GitHub Releases.

It checks for a previously managed copy, searches `~/AppImages`, queries the latest GitHub release, downloads a matching AppImage, integrates it with Gear Lever, records its final location, and can launch it.

### AppImage example: BleachBit

```bash
#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_install_github_appimage \
    "BleachBit" \
    "bleachbit/bleachbit" \
    "bleachbit.*x86_64.*appimage" \
    --launch
```

### AppImage example: WireGuard-GUI

```bash
#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${JSF_RUNTIME_CORE_PATH:-${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib}"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_install_github_appimage \
    "WireGuard-GUI" \
    "0xle0ne/wireguard-gui" \
    "wireguard-gui.*amd64.*appimage" \
    --launch
```

### AppImage helper reference

```bash
jsf_install_github_appimage \
    "AppName" \
    "github-owner/repository" \
    "release-asset-pattern" \
    --launch
```

| Argument | Purpose |
|---|---|
| `"AppName"` | Readable application identifier used in status messages and the JS-Forge state filename. Use letters, numbers, hyphens, or underscores. |
| `"github-owner/repository"` | GitHub repository queried for the latest release. |
| `"release-asset-pattern"` | Case-insensitive regular expression used to choose the correct release asset. |
| `--launch` | Optional. Launches the app after a successful install or when a managed copy already exists. |

Do not add a separate dependency request for Gear Lever, `curl`, or `jq` to every AppImage script when xProbe already provides them during normal JS-Forge startup.

### Managed AppImage state

Successfully located AppImages are recorded in:

```text
${XDG_STATE_HOME:-$HOME/.local/state}/JS-Forge/appimages/
```

Examples:

```text
~/.local/state/JS-Forge/appimages/BleachBit.path
~/.local/state/JS-Forge/appimages/WireGuard-GUI.path
```

On later runs, the helper uses the saved path and does not download the AppImage again. If no state file exists, it searches `~/AppImages` to recognize Gear-Lever-integrated copies.

### AppImage limitations

- The helper uses GitHub's `releases/latest` endpoint; it does not pin an older release.
- It installs and launches AppImages; it is not a general AppImage updater.
- An AppImage can still require host packages, permissions, kernel modules, VPN tools, or other system configuration.
- Only add repositories and release assets you trust.

## Script visibility by package manager

JS-Forge recognizes ordinary `.sh` scripts and package-manager-specific suffixes:

```text
install-docker.apt
install-docker.dnf
install-docker.yum
install-docker.pacman
install-docker.zypper
```

A script with one of these suffixes is shown only when the matching package manager is active. This lets one script vault contain distro-targeted actions without showing users irrelevant choices.

## Pause and no-pause modes

Installer and repair scripts use the default paused launch behavior so users can read their output.

Launcher-style scripts can return immediately by placing this near the top:

```bash
#!/bin/bash
jsf_no_pause="1"
```

Use no-pause for quick app launchers, Flatpak handoffs, AppImage launchers, and short background actions. Leave it out for installers, repair tools, and workflows that need visible output.

## Extension system

Extensions are regular `.ext` Bash files sourced at startup from the resolved extension directories. They can register menu labels and callbacks through the global extension arrays without requiring edits to the main launcher.

This lets contributors ship a focused report, repair path, automation workflow, policy warning, or integration as a feature module.

## Included extension examples

### xProbe

xProbe checks the environment, rejects unsupported raw TTY and WSL use cases, validates dependencies and Flatpaks, and records system information in a report users can open later.

### GitEngine

GitEngine maintains a repository list, clones repositories into the script folder, updates them with `git pull`, and can bulk-delete cloned repositories.

### Updates

The updates extension queries a configured GitHub repository, compares the latest release version, and can notify automatically or manually.

### Emoji support

The emoji extension can detect missing fontconfig support or missing `Noto Color Emoji`, install needed packages, refresh font caches, and write a fallback fontconfig file.

## Workflow automation

JS-Forge can wrap desktop actions, package installs, Flatpak onboarding, AppImage installation, repository sync jobs, repair flows, bootstrap routines, maintenance tasks, and curated multi-step utilities in one consistent menu-driven environment.

## Forking and customizing

- Rebrand `AppRun` metadata, versioning, command name, and credits.
- Adjust xProbe dependencies and Flatpak requirements for the fork's own toolchain.
- Keep shared behavior in `runtime-core.lib` and build features as `.ext` modules.
- Enable user extensions with `allow_user_extensions="1"` when appropriate.
- Replace GitEngine's seed repository list with a curated script vault.
- Use package-manager-specific script suffixes for distro-targeted actions.
- Choose paused or no-pause behavior per script.
- Use `jsf_install_github_appimage` instead of duplicating GitHub release, download, Gear Lever, and state-tracking code.

## Building new scripts

1. Start from the base script template.
2. Source `runtime-core.lib` and call `jsf_init_runtime_core`.
3. Use `jsf_require_all` for script-specific native packages, Flatpaks, or both.
4. Use runtime UI helpers such as `center`, `divider`, `print_red`, `text_delay`, and terminal-launch helpers for a consistent experience.
5. Put runnable scripts or extensions in a discovered JS-Forge script/extension location.
6. Use package-manager suffixes for distro-specific scripts.
7. Use `jsf_no_pause="1"` for quick launchers when appropriate.
8. Use `jsf_install_github_appimage` for GitHub-hosted AppImages.

## Current Linux assumptions

JS-Forge is Linux-focused and xProbe rejects raw TTY and WSL environments. It expects a supported package-manager family and a desktop-oriented environment where Zenity, terminal emulators, Flatpak, Gear Lever, and common command-line tools are reasonable dependencies.

## Suggested repository shape

```text
JS-Forge/
├── AppRun
├── runtime-core.lib
├── 01-xprobe.ext
├── 02-gitengine.ext
├── 03-updates.ext
├── 04-emoji-support.ext
├── LICENSE
└── README.md
```

## Philosophy

JS-Forge is best treated as a Bash toolbox platform rather than one large script. The launcher, runtime core, and extensions provide lightweight shared infrastructure for interactive Linux utilities, AppImage installers, workflow automation, and curated script packs.
