# JS-Forge

## Go Forth, And Create!

### Version 1.2.1

Release metadata dated October 31, 2026. The current launcher metadata uses the beta stage. Documentation updated November 7, 2026.

JS-Forge is a Bash application framework, launcher, and workflow automation tool for Linux. It combines a terminal UI, optional Zenity dialogs, environment probing, extension loading, package and Flatpak helpers, Git-backed script intake, and reusable GitHub AppImage installation support.

It is built for people who want to run curated scripts and for builders who want to create Linux tools, automation flows, and utility packs without rebuilding the same Bash infrastructure in every script.

This README is a living document for the current Bash-based build. Collection scripts and their behavior continue to evolve; examples and reported test results are not guarantees of support on every host.

## What it does

JS-Forge provides a branded shell application with a startup pipeline, session-aware dependency checks, extension menus, and separate Linux Control Panel and GitEngine Scripts browser roots. Linux Control Panel is bundled with JS-Forge; GitEngine supplies an additional repository-backed script collection.

At launch, it initializes runtime variables, detects TUI or GUI mode, gathers system information, shows a version-gated MIT license prompt when required, loads `.ext` extensions (including xProbe), and opens the main browser/menu flow.

## Core features

- Hybrid TUI/GUI behavior using terminal UI helpers and Zenity dialogs.
- Bundled Linux Control Panel scripts, with recursively merged GUI/headless categories.
- Session-aware script visibility and a minimal dependency profile for SSH/headless use.
- A portable `runtime-core.lib` shared by standalone scripts and extensions.
- Native-package and Flatpak dependency helpers through `jsf_require_all`.
- GitHub AppImage installation through `jsf_install_github_appimage`.
- Package-manager-specific script visibility for `.apt`, `.dnf`, `.yum`, `.pacman`, and `.zypper` scripts.
- Extension loading from portable, AppImage, and optional user extension paths.
- Environment and dependency reporting through xProbe.
- Terminal-launch helpers for GUI-mode scripts that still need a shell session.
- Default paused installer behavior and optional no-pause launcher behavior.
- Enabled GitEngine repository-list, clone, pull, and delete workflows for additional script repositories.
- Installed-software search, full-inventory export, and a single-selection removal beta.
- Terminal utilities and audit workflows, including LF, lnav, an OpenSSH server installer, and Lynis auditing with optional export.
- Script-generated inventory and audit exports under `~/JS-Forge-Exports/`.
- GitHub release update checks.
- Emoji/font repair and optional diagnostic warning modules.

## System Requirements

### AppImage Requirement: FUSE

Running the JS-Forge AppImage requires a working FUSE (Filesystem in Userspace)
setup. This applies to both terminal/SSH and desktop/GUI sessions.

Depending on the AppImage runtime, your distribution may also need the FUSE 2
compatibility library, even if FUSE 3 is already installed. Package names vary
by distribution; Debian-based systems commonly provide it as `libfuse2` or
`libfuse2t64`.

Install the appropriate compatibility library without removing or replacing
your system's existing FUSE 3 installation.

FUSE must be available before launching the AppImage—JS-Forge's startup
dependency checks cannot install it if the AppImage cannot mount.

Running directly from the source AppDir or an extracted AppImage does not
require FUSE to mount JS-Forge.

### Recommended Usage

Run JS-Forge directly from its AppImage to keep bundled files read-only.
Extraction is useful for development or FUSE troubleshooting, but extracted
files may be writable. Read-only mounting protects the bundle; it does not
sandbox scripts or prevent changes elsewhere on your system.

### Terminal / SSH Dependencies

The minimal headless startup profile checks:

- `tput`
- `nano`
- `curl` and `jq` while the updates extension is enabled.
- `git` while GitEngine is enabled.

With both extensions enabled in the current configuration, the list is `tput`,
`nano`, `curl`, `jq`, and `git`. Headless startup does not guarantee `whiptail` or
`chsh`; scripts that need tools outside this profile must request them explicitly.

### Desktop / GUI Dependencies

Desktop-capable sessions retain the terminal toolchain and desktop dependencies,
including:

- `whiptail`
- `chsh`
- `zenity`
- `xdg-open`
- `flatpak`

Required Flatpak applications:

| Application | Flatpak ID |
| --- | --- |
| Gear Lever | `it.mijorus.gearlever` |
| Flatseal | `com.github.tchx84.Flatseal` |

Desktop dependencies apply to desktop-capable sessions even when using the
terminal interface. SSH/headless sessions do not require the desktop-only tools
or Flatpak applications.

Individual scripts may require additional software beyond these startup
dependencies. Request those dependencies through the runtime rather than expanding
the minimal headless profile for every script.

## Supported Linux Distributions

### Full Support

All or most features have been tested and are working:

- MX Linux

### Partial Support

Some features may be unsupported or may not work as expected:

- LCOS
- Artix Linux
- PCLinuxOS
- openSUSE
- Other distros (zero support)

## Project layout

| File | Purpose |
| --- | --- |
| `AppRun` | Main launcher, metadata, UI-mode detection, branding, EULA flow, extension loading, browser/menu flow, and runtime bootstrapping. |
| `runtime-core.lib` | Shared terminal UI, package-manager, dependency, extension-path, terminal-launch, and GitHub AppImage helpers. |
| `01-xprobe.ext` | Environment report and dependency/Flatpak checks. |
| `02-gitengine.ext` | Enabled repository-list-driven clone, pull, and delete workflow; exposes GitEngine options and its script collection. |
| `03-updates.ext` | GitHub release update checker. |
| `04-emoji-support.ext` | Emoji and fontconfig repair helper. |
| `05-systemd-warning.ext` | Example systemd policy warning module. |
| `06-wayland-warning.ext` | Example Wayland policy warning module. |
| `Linux-Control-Panel/headless/` | Bundled scripts available in desktop and supported headless sessions. |
| `Linux-Control-Panel/gui/` | Additional bundled scripts available in desktop-capable sessions, including the terminal interface. |

## Session modes and script roots

Session capability and interface choice are separate. A desktop-capable session
can use the terminal interface without losing access to desktop scripts.

| Session | Bundled Linux Control Panel collections |
| --- | --- |
| Desktop GUI launch | `headless` + `gui`, merged into one category tree |
| Terminal inside a desktop with detected graphical access | `headless` + `gui`, merged into one category tree |
| Interactive SSH, including X11 forwarding | `headless` only |
| Other supported interactive session without detected graphical access | `headless` only |
| Raw Linux virtual/serial console | Blocked by default; `headless` only if explicitly enabled |

Bundled collections live beside AppRun under `Linux-Control-Panel/` inside the
AppDir/AppImage. The scripts are maintained in this repository; no separate
repository checkout is required for the bundled Linux Control Panel menu.

GitEngine Scripts is a separate collection rooted at `~/.JS-Forge/`. It is not split
into GUI/headless subdirectories by the browser. Its scripts still follow
package-manager suffix filtering, but users must choose actions suitable for the
current environment. GitEngine is enabled in the current configuration.

### One merged category tree

Physical folders such as:

```text
Linux-Control-Panel/
├── headless/
│   ├── OS Patching/
│   │   └── Set Default Editor to Nano.sh
│   └── Manage Packages/
│       └── Professional/
└── gui/
    ├── OS Patching/
    │   ├── Flatpak - XFCE - Dark Mode.sh
    │   └── MX Linux Lockscreen Fix - XFCE.sh
    └── Manage Packages/
        └── Professional/
```

appear on a desktop as one combined menu:

```text
Linux Control Panel
├── Manage Packages
│   └── Professional
└── OS Patching
    ├── Flatpak - XFCE - Dark Mode.sh
    ├── MX Linux Lockscreen Fix - XFCE.sh
    └── Set Default Editor to Nano.sh
```

Headless sessions use the same category structure but read only the headless
collection. The physical `gui` and `headless` names are not extra menu levels.

- Matching relative category paths merge recursively.
- Categories unique to an accessible collection are included.
- Names are case-sensitive: `OS Patching` and `os patching` remain separate.
- Identical relative script filenames appear once. On desktops the GUI copy wins;
  headless sessions use only the headless copy.
- Directories appear before scripts, with names sorted within each group.
- Each menu entry retains the real script path for execution and source viewing.

Scripts are classified by placing them under `Linux-Control-Panel/headless/` or
`Linux-Control-Panel/gui/` by hand. The browser does not inspect script contents to
infer graphical requirements. Populate these folders before building the AppImage;
changing a separate source tree does not update an existing built image.

### SSH, display detection, and raw consoles

SSH is detected through `SSH_CONNECTION`, `SSH_TTY`, or `SSH_CLIENT` and always uses
the headless profile, even when DISPLAY/X11 forwarding is present. A desktop running
elsewhere on the host does not make it accessible to the current SSH user.

Local graphical detection uses an accessible Wayland socket or existing bounded
X11 query tools, with a conservative local-socket/session-evidence fallback. It
is session detection, not a guarantee that every graphical application will run.
Noninteractive headless use is rejected; request a PTY when launching an SSH command.

Raw console behavior is controlled in AppRun by:

```bash
allow_raw_tty="0"
```

`0` blocks raw Linux consoles by default. `1` permits them with the headless profile.
This is a persistent source setting, not a command-line flag; it does not repair
raw-console ASCII/emoji rendering. SSH and desktop pseudoterminals are not raw
Linux console sessions. WSL remains rejected by the existing probe policy.

### Startup dependency profiles

The headless probe checks `tput` and `nano`, adds `curl`/`jq` while the update
extension is enabled, and adds `git` while GitEngine is enabled. With both extensions
enabled in the current configuration, the list is `tput`, `nano`, `curl`, `jq`, and
`git`.

Headless startup skips Zenity, Flatpak, Gear Lever, Flatseal, `xdg-open`, `whiptail`,
and `chsh`. The desktop profile retains its desktop toolchain and user-Flatpak
checks. Startup installation uses the existing install-then-restart workflow;
script-specific dependencies remain the script author's responsibility.

### Navigation

GUI browser dialogs use their Back/Cancel button without a duplicate inline
`<- Back` row. Terminal menus retain the inline Back option. The terminal source
viewer follows the merged collection rules and opens bundled scripts read-only in
Nano; third-party source retains its existing editable behavior.

## Getting started

Run JS-Forge from inside its source/extracted AppDir:

```bash
chmod +x AppRun
./AppRun
```

Or, from the repository root:

```bash
chmod +x JS-Forge.AppDir/AppRun
./JS-Forge.AppDir/AppRun
```

For an AppImage, make the downloaded file executable and launch it through your
file manager or an interactive terminal. A graphical launch uses Zenity when
usable graphical access is detected. If Zenity is missing, use the existing
terminal workflow to install the required packages. AppImage runtime/FUSE
requirements still apply.

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
```

Keep every dependency after its matching marker: `--native` for native commands and `--flatpak` for Flatpak application IDs.

### When to use jsf_require_all

Use `jsf_require_all` for dependencies specific to the script you are writing.

xProbe already verifies the startup toolchain for the current session profile. A script launched through normal startup does not need to repeat checks for tools that its profile guarantees, but headless startup deliberately guarantees fewer tools. Explicitly requesting dependencies remains valid when a script needs to run outside the normal JS-Forge startup flow.

Flatpak-oriented scripts need Flatpak itself available before the Flatpak helpers can be used. Place desktop integration scripts in the GUI collection rather than making a minimal/headless startup install desktop tools merely to satisfy them.

## GitHub AppImage installation

Introduced in JS-Forge 1.2.0, `jsf_install_github_appimage` is a shared runtime helper for AppImages published through GitHub Releases.

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
| --- | --- |
| `"AppName"` | Readable application identifier used in status messages and the JS-Forge state filename. Use letters, numbers, hyphens, or underscores. |
| `"github-owner/repository"` | GitHub repository queried for the latest release. |
| `"release-asset-pattern"` | Case-insensitive regular expression used to choose the correct release asset. |
| `--launch` | Optional. Launches the app after a successful install or when a managed copy already exists. |

Do not add a separate dependency request for Gear Lever, `curl`, or `jq` to every AppImage script when the desktop xProbe profile already provides them. Scripts using Gear Lever integration belong in the bundled GUI collection: headless startup intentionally does not provision Gear Lever or Flatpak. A separately invoked script must arrange its own required dependencies.

The examples above illustrate helper usage; repository release assets and naming patterns must be checked when maintaining the script. The helper does not guarantee that a particular upstream release still offers a matching AppImage.

### Gear Lever confirmation handling

The shared runtime integration call now passes `--yes` to Gear Lever so its nested
terminal confirmation does not interrupt or stall the installation workflow.
This change belongs in `runtime-core.lib`; individual scripts keep using the same
`jsf_install_github_appimage` interface shown above. It does not change the helper's
state tracking or optional `--launch` behavior.

The Installed Software Search removal beta separately passes `--yes` to Gear
Lever only after the user accepts JS-Forge's single-item removal confirmation.
This is not a global automatic-yes setting for native packages or Flatpak
uninstall transactions, and it does not request Gear Lever's permanent-delete mode.

When maintaining the runtime, update the source copy used by AppRun and rebuild
the AppImage as needed. AppRun deploys a runtime copy to the application data
location; editing only that deployed copy may be overwritten on a later launch.

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

A script with one of these suffixes is shown only when the matching package manager is active. This lets one script vault contain distro-targeted actions without showing users irrelevant choices. The rule applies to both bundled and GitEngine scripts; desktop capability does not bypass it.

Compatible scripts are executed through Bash without attempting chmod on bundled files. Scripts must be Bash-compatible and must use writable user-data/state/temp locations instead of writing into their read-only bundled directory. The launcher preserves the script path but does not automatically change into the script's directory.

## Recent Linux Control Panel scripts

The current iteration adds or refines the following collection scripts. Keep the
actual files in the appropriate collection before building; documenting a script
does not add it to an existing AppImage. These terminal workflows belong in the
headless collection where appropriate, with desktop-only actions guarded rather
than forcing a desktop dependency profile onto SSH sessions.

### Installed Software Search and removal beta

Installed Software Search builds a snapshot of:

- Installed native packages, including libraries and dependencies rather than only desktop applications.
- Installed Flatpak applications in their recorded installation scopes, not Flatpak runtimes.
- AppImage files found recursively under `~/AppImages`, using case-insensitive filename matching.

Flatpak is queried only when it is already available; inventory collection does
not install it. AppImage discovery does not imply that every file is integrated
with Gear Lever.

| Control | Action |
| --- | --- |
| Type | Live fuzzy filtering; an empty query shows the full inventory |
| Arrows / Page Up / Page Down | Navigate results |
| Ctrl+U | Clear the query |
| Ctrl+E | Export the entire snapshot, regardless of the current filter |
| Ctrl+D or double-click | Request removal of one highlighted item |
| Ctrl+R | Refresh the inventory |
| Enter | No action |
| Esc | Close the browser |

Exports are unique timestamped text reports under `~/JS-Forge-Exports/`, including
collection/export timestamps and the inventory count. Export is explicit; opening
or filtering the inventory does not automatically create a report.

Removal remains a beta workflow:

- The confirmation identifies the selected item and its source and defaults to Cancel.
- Hidden snapshot-specific identifiers map to structured metadata; formatted display rows are not parsed into uninstall arguments. Stale selections are rejected.
- Native removal uses the detected package manager and retains its transaction prompt. No automatic yes, purge, or explicit autoremove is requested; DNF/YUM orphan cleanup is disabled for the removal command.
- A single selected native package can still cause the manager to propose removing other dependent packages. Review that transaction and decline if unsure.
- Flatpak removal uses the exact application ref and installation scope, without `--delete-data`.
- AppImage removal requires an exact reported path match in Gear Lever and delegates to Gear Lever without sudo. No manual file-deletion fallback or `--remove-all` is used.
- Gear Lever removal is unavailable in SSH/headless sessions and does not install desktop tools merely to enable it.
- The currently running JS-Forge AppImage is protected using its `APPIMAGE` path, including resolved-path comparison.
- Immediate inventory/runtime dependencies and apt essential/protected packages receive additional guards. These are not a complete operating-system safety policy.
- After a removal command returns, the inventory is refreshed. Canceling the confirmation leaves the inventory unchanged.

Start removal testing with disposable applications or a VM snapshot. Package-manager
support and mocked tests do not guarantee that every proposed removal is safe.

### LF file manager

The LF launcher offers user or root mode, with user mode selected by default.
User mode opens the user's home directory; root mode uses `sudo -H` and opens `/`.
Cancel exits without launching LF.

The entire root-mode file manager session, including shell actions, runs with
administrative privileges. Use user mode for ordinary file management. LF's delete
action is not a substitute for the inventory tool's package-aware removal flow.

### lnav log viewer

The log-viewer workflow uses an explicit `/var/log` target instead of relying on
lnav to discover default log files. Administrative access is used when needed to
read protected logs. Recursive viewing and mouse support depend on the installed
lnav version and the launcher options; older distribution packages may differ.

### OpenSSH server installer

The OpenSSH installer requests the appropriate native package through the shared
runtime. It is an installation-only wrapper: it adds no explicit service-management
commands and does not edit SSH configuration or firewall rules. Distribution
package scripts may start or enable the service during installation; review the
host's resulting service and access settings.

### Lynis security audit

The Lynis script requests the native `lynis` package, runs `lynis audit system`
with administrative access, and displays the audit on screen. It uses quick mode
to avoid normal section-by-section pauses and captures plain-text output.

After the audit:

| Control | Action |
| --- | --- |
| V | View the findings summary |
| C | Review the captured screen output |
| E | Export the current audit |
| R | Run a fresh audit |
| Q | Quit |

Each requested export creates a unique timestamped `Lynis-...` folder under
`~/JS-Forge-Exports/` containing:

| File | Contents |
| --- | --- |
| `summary.txt` | Audit/capture status, warning and suggestion counts, and findings |
| `console.txt` | Captured terminal output |
| `lynis.log` | Detailed Lynis log, when produced and copied successfully |
| `lynis-report.dat` | Native Lynis report data, when produced and copied successfully |

The script does not apply hardening fixes, configure a firewall, add scheduled
jobs, or request report upload. Findings require review in the context of the
host; a hardening index is not proof of security. Errors or missing reports are
identified rather than treated as a clean audit result.

Root-generated logs are collected in a private workspace and copied into the
script's user-side temporary workspace before optional export. Export before
quitting or rerunning if you want to retain the current audit; normal exit removes
the temporary copies. A report-copy failure can retain the private workspace and
print its location for recovery rather than deleting the remaining source files.
Reports may contain sensitive account, host, and network information. Export
folders and files use restrictive permissions; review and redact them before
sharing.

## Exports and saved reports

The current inventory and Lynis scripts use:

```text
~/JS-Forge-Exports/
```

This is a user-facing export directory, separate from the runtime library,
GitEngine repositories, temporary workspaces, and managed-AppImage state. It is
created when an export is requested, not merely because JS-Forge starts. These
scripts do not require the application bundle to be writable.

Examples of the resulting layout:

```text
~/JS-Forge-Exports/
├── JS-Forge-Installed-Software-<timestamp>.<unique>.txt
└── Lynis-<timestamp>.<unique>/
    ├── summary.txt
    ├── console.txt
    ├── lynis.log
    └── lynis-report.dat
```

Unique names avoid overwriting previous exports. Inventory export always uses the
full collected snapshot, not only visible search matches. Lynis exports preserve
the latest completed or partial audit available in that script session; files
that were not produced cannot be included.

The location is currently set by the individual scripts; it is not a new global
runtime setting or an XDG data/state directory. `~` refers to the home directory
used by the script. Running the entire script as root can therefore use root's
home, whereas elevating only the audit/package commands keeps the normal user's
export location.

Existing xProbe reports, AppImage path records, and downloaded applications are
not automatically relocated into this directory. Export files are saved reports,
not disposable runtime cache, and should not be removed as part of routine
application reset without user approval.

## Pause and no-pause modes

Installer and repair scripts use the default paused launch behavior so users can read their output.

Launcher-style scripts can return immediately by placing this near the top:

```bash
#!/bin/bash
jsf_no_pause="1"
```

Use no-pause for quick app launchers, Flatpak handoffs, AppImage launchers, and short background actions. Leave it out for installers, repair tools, and workflows that rely on the launcher's final pause.

An interactive script may also use `jsf_no_pause="1"` when it manages its own menu,
viewer, or closing prompt. Installed Software Search, the OpenSSH installer, and
the Lynis workflow handle their own interaction rather than needing a duplicate
launcher pause. This setting does not require a script to run in the background
or hide its terminal output.

## Extension system

Extensions are regular `.ext` Bash files sourced at startup from the resolved extension directories. They can register menu labels and callbacks through the global extension arrays without requiring edits to the main launcher.

This lets contributors ship a focused report, repair path, automation workflow, policy warning, or integration as a feature module.

A file named `<name>.ext.disabled` is not loaded. Rename it back to `.ext` to re-enable it. GitEngine is enabled as `02-gitengine.ext` in the current configuration; `.disabled` is an optional off switch, not its default state. If GitEngine is absent or disabled, both its management options and GitEngine Scripts root disappear.

User extensions are disabled unless `allow_user_extensions="1"` is set in AppRun. Their directory is `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge`. Extensions are sourced shell code; only enable trusted modules.

## Included extension examples

### xProbe

xProbe checks the environment, enforces the configured raw-console/WSL policy, validates the current session's dependencies, and records system information in a report users can open later. Headless startup skips desktop Flatpak checks; its native tools include `git` while GitEngine is enabled and `curl`/`jq` while updates are enabled.

### GitEngine

GitEngine is enabled as `02-gitengine.ext`. It manages additional script repositories,
separate from the Linux Control Panel scripts bundled in this repository/AppImage.
Its menu supports editing the repository list, cloning repositories, updating them
with `git pull`, and bulk-deleting cloned repositories.

Repositories are stored under `~/.JS-Forge/` and browsed through GitEngine Scripts.
The repository list is stored at:

```text
${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/gitengine-repositories.txt
```

Use Edit Repository List to configure the repositories you want. The existing list
format supports one repository URL per line, blank lines, and `#` comments. This
README does not prescribe a seed repository list.

When customizing defaults in the extension, remember that the existing list is
created only if missing; editing seed entries does not rewrite an already-created
user list. Review repositories and local changes before pull or bulk-delete actions.
GitEngine scripts are not automatically classified as GUI/headless, and trusted
sources still need review before execution.

### Updates

The updates extension queries the configured JS-Forge GitHub release endpoint, compares the latest release version, and can notify automatically or manually. Automatic checks use the existing 30-day interval. It reports updates rather than automatically replacing the running AppImage.

### Emoji support

The emoji extension can detect missing fontconfig support or missing `Noto Color Emoji`, install needed packages, refresh font caches, and write a fallback fontconfig file. It is skipped for headless/SSH startup; font rendering in an SSH client belongs to the client's terminal environment.

## Workflow automation

JS-Forge can wrap desktop actions, package installs, Flatpak onboarding, AppImage installation, repository sync jobs, repair flows, bootstrap routines, maintenance tasks, security audits, inventory exports, and curated multi-step utilities in one consistent menu-driven environment.

## Forking and customizing

- Rebrand `AppRun` metadata, versioning, command name, and credits.
- Adjust xProbe dependencies and Flatpak requirements for the fork's own toolchain.
- Keep shared behavior in `runtime-core.lib` and build features as `.ext` modules.
- Enable user extensions with `allow_user_extensions="1"` when appropriate.
- Maintain the bundled Linux Control Panel categories in this repository and curate GitEngine's additional repository list separately.
- Set `allow_raw_tty="1"` only if opting into raw-console operation is appropriate for the fork.
- Use package-manager-specific script suffixes for distro-targeted actions.
- Choose paused or no-pause behavior per script.
- Use `jsf_install_github_appimage` instead of duplicating GitHub release, download, Gear Lever, and state-tracking code.
- Keep user-facing report exports separate from caches and application state; use the current `~/JS-Forge-Exports/` convention where appropriate.

## Building new scripts

1. Start from the base script template.
2. Source `runtime-core.lib` and call `jsf_init_runtime_core`.
3. Use `jsf_require_all` for script-specific native packages, Flatpaks, or both.
4. Use runtime UI helpers such as `center`, `divider`, `print_red`, `text_delay`, and terminal-launch helpers for a consistent experience.
5. Put bundled scripts under `Linux-Control-Panel/headless/` or `gui/` according to their requirements; GitEngine scripts and extensions use their separate discovered locations.
6. Use package-manager suffixes for distro-specific scripts.
7. Use `jsf_no_pause="1"` for quick launchers or scripts that handle their own interaction when appropriate.
8. Use `jsf_install_github_appimage` for GitHub-hosted AppImages.
9. Offer explicit export for reports that users may want to retain, using unique names under `~/JS-Forge-Exports/` and appropriate permissions for sensitive content.
10. Preserve exact targets and scope for destructive actions, default confirmations to Cancel, and retain native transaction review where applicable.

## Current Linux assumptions

JS-Forge is Linux-focused. It detects apt, dnf, yum, pacman, and zypper and maps
common command names to distribution packages through the runtime helpers.
Package-manager support does not guarantee every script fits every distribution.

Desktop sessions use the desktop toolchain; SSH/headless sessions use the minimal
profile described above. Raw Linux consoles are blocked unless explicitly enabled;
WSL rejection remains unchanged. The existing systemd/Wayland warning modules are
separate from package-manager support checks.

Local testing of the current build has been reported successful. Additional
SSH/headless validation is planned; this is not a claim of completed testing on
Proxmox, DietPi, or every distribution. Probe/network/package work still depends on
the host environment.

Recent collection scripts have a mixture of reported live use and syntax/mocked
checks. Those checks do not establish successful real package installation,
removal, or complete audit coverage on every supported distribution. The software
removal workflow remains beta, and the new Lynis script still needs host-level
validation. Preserve these distinctions when updating this living document.

## Startup timing and AppImage behavior

The current configuration uses the shortened core/probe delays:

- `text_delay`: 0.05 seconds, previously 0.1.
- xProbe success pauses: 0.15 seconds each, previously 0.3.
- Non-apt bridge progress notice: 1 second, previously 2.
- Post-probe GUI report timeout: 2 seconds, previously 3.

The update, systemd-warning, and Wayland-warning extensions retain their original
timings: 3-second update message pauses, 10-second GUI warning timeouts, 5-second
terminal warning pauses, and 1-second non-warning pauses. Checks and warning text
are unchanged; total startup time is not guaranteed to halve.

The GUI probe uses a dynamically allocated file descriptor and waits for its
progress process. It does not overwrite inherited descriptor 3, addressing the
premature AppImage mount loss observed during GUI startup. Keep runtime mounts
intact while the application is running.

AppRun resolves its actual launcher location and keeps runtime, extension, and
bundled-script discovery aligned. Missing/empty category notices display searched
directories and bundle/APPDIR information. If scripts are absent, check exact path
case, package-manager suffixes, image contents, and whether the desktop launcher is
opening the intended newly built AppImage.

## Suggested repository shape

```text
JS-Forge/
├── JS-Forge.AppDir/
│   ├── AppRun
│   ├── runtime-core.lib
│   ├── JS-Forge.desktop
│   ├── 01-xprobe.ext
│   ├── 02-gitengine.ext
│   ├── 03-updates.ext
│   ├── 04-emoji-support.ext
│   ├── 05-systemd-warning.ext
│   ├── 06-wayland-warning.ext
│   └── Linux-Control-Panel/
│       ├── gui/
│       └── headless/
├── LICENSE
└── README.md
```

This abbreviated view omits icons and other existing resources, which should be
retained. Use the project's existing AppImage build process after populating the
bundled script folders. Do not treat a source-update overlay as a complete AppDir.

## Runtime data

| Location | Purpose |
| --- | --- |
| `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge` | Copied runtime, license/update state, repository list, and optional user extensions |
| `~/.JS-Forge` | Additional GitEngine repositories/scripts |
| `/tmp/JS-Forge` | Application temporary workspace |
| `${XDG_STATE_HOME:-$HOME/.local/state}/JS-Forge/appimages` | Managed-AppImage path records |
| `~/JS-Forge-Exports` | Explicitly saved inventory reports and exported Lynis audit folders; not runtime cache |

Individual collection scripts may also create private, uniquely named temporary
workspaces. The inventory and Lynis wrappers clean their own temporary files on
normal exit; this is separate from deleting saved exports or resetting JS-Forge.
See the Lynis section for its report-copy failure recovery behavior.

Not all of these files are disposable cache: repository-list edits, user extensions,
cloned repositories, and exported reports may contain user-authored or sensitive
data. Removing AppImage path records is not the same as uninstalling the
applications they reference.

Cleanup & Reset is deferred. The inventory script's explicit single-item removal
beta is not a general cleanup/reset tool; no broad automatic removal of saved
reports, application data, or system data is introduced by this update.

## Philosophy

JS-Forge is best treated as a Bash toolbox platform rather than one large script. The launcher, runtime core, and extensions provide lightweight shared infrastructure for interactive Linux utilities, AppImage installers, workflow automation, and curated script packs.

## Credits

JCore Studios & jcore92 maintain JS-Forge and the bundled Linux Control Panel scripts in this repository.

The launcher credits acknowledge Perplexity for AI assistance and dedicate the project to Maya. Preserve the project's existing MIT license and notices.
