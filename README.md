# JS-Forge

JS-Forge is a Bash application framework, launcher, and workflow automation tool for Linux that blends a terminal UI, optional Zenity dialogs, environment probing, extension loading, and dependency/bootstrap helpers into one portable runtime.

It is designed for two kinds of people: users who just want to run curated scripts, and tinkerers who want a starting point for building their own Bash tools, automation flows, and utility packs without rewriting the same setup code every time.

## What it does

JS-Forge provides a branded shell application shell with a startup pipeline, dependency helpers, extension menus, and a script browser rooted in the user's script folder.

At launch, the app initializes its variables, detects whether it is in TUI or GUI mode, gathers system details, can show a version-gated MIT license prompt, runs the environment probe, loads `.ext` extensions, and then opens its main browser/menu flow.

The result is a lightweight framework for launching tools, automating repetitive desktop or system tasks, curating script packs, and building modular Bash workflows that still feel like one cohesive application.

## Core features

- Hybrid interface: the project can run as a terminal-first application or switch to Zenity-backed dialogs when launched outside a terminal.
- Portable runtime core: `AppRun` copies `runtime-core.lib` into `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/` so scripts can source the same helper library consistently from `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib`.
- Dependency bootstrap: the runtime detects `apt`, `dnf`, `yum`, `pacman`, or `zypper`, builds install/refresh commands, and exposes `jsf_require_all` for native packages and Flatpaks.
- Package-manager-specific script filtering: scripts can be named with package-manager-specific extensions such as `.apt`, `.dnf`, `.yum`, `.pacman`, or `.zypper`, and JS-Forge only shows those scripts on systems where that package manager is actually active.
- Extension loading: `.ext` files are discovered from portable, AppImage, and optional user paths and can register their own menu entries and actions.
- Environment reporting: xProbe records OS, host, LAN IP, package-manager status, desktop environment, display server, init system, dependencies, and Flatpak state in a viewable report.
- Script launching helpers: the runtime can open terminal commands or temporary helper scripts in common terminal emulators, which is especially useful for GUI mode workflows that still need a shell session.
- Pause and no-pause launch behavior: installer-style scripts can keep the default pause behavior, while launcher-style scripts can be marked to return immediately without forcing the same post-run wait.
- Git-backed script intake: GitEngine can maintain a repository list, clone repositories into the script folder, pull updates, and delete cloned repos in bulk.
- Update checks: the updates extension can query the latest GitHub release, compare versions, and notify the user automatically or manually.
- Emoji/font repair path: the emoji extension can detect missing fontconfig or emoji fonts, install packages, refresh the font cache, and write a fallback fontconfig file for terminal emoji rendering.
- Optional diagnostic opinion modules: the attached Wayland and systemd warning extensions show how JS-Forge can be extended with custom policy or opinionated environment checks.

## Project layout

The attached files show a split between the main application entry point, the shared runtime, and optional extensions.

| File | Purpose |
|---|---|
| `AppRun` | Main launcher, app metadata, UI mode detection, branding, EULA flow, extension loading, menu flow, package-manager-specific script visibility, and runtime bootstrapping. |
| `runtime-core.lib` | Shared helper library for terminal UI helpers, package-manager detection, dependency installation, extension-dir resolution, and terminal launching helpers. |
| `01-xprobe.ext` | Environment and dependency report extension with dependency and Flatpak checks. |
| `02-gitengine.ext` | Repository-list driven Git clone/pull/delete workflow for collecting script packs. |
| `03-updates.ext` | GitHub release checker and update notifier. |
| `04-emoji-support.ext` | Emoji/fontconfig repair helper for terminals. |
| `05-systemd-warning.ext` | Example policy warning extension for systemd detection. |
| `06-wayland-warning.ext` | Example policy warning extension for Wayland detection. |

## Runtime model

The runtime core is the part most worth understanding if the goal is to fork JS-Forge or build on top of it.

`jsf_init_runtime_core` prepares the application data directory, temp directory, extension search paths, privilege model, and package-manager helpers so later code can stay focused on the actual tool being built instead of bootstrap plumbing.

`jsf_require_all` then gives scripts a compact interface for ensuring both native packages and Flatpaks are present before continuing.

### Minimal script bootstrap

This pattern is the big quality-of-life win for people building with a fork:

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core

jsf_require_all \
  --native flatpak zenity curl \
  --flatpak it.mijorus.gearlever
```

That small block gives a script a shared dependency model, package-manager abstraction, privilege awareness, extension-dir awareness, temporary workspace setup, and terminal-launch helpers without having to copy all of that into each new script.

In practice, this means a fork can focus on the real feature immediately: media tools, system helpers, installers, repair utilities, repo launchers, automation steps, or guided desktop actions.

## Why this makes Bash scripting easier

A lot of Bash projects stall out because every script has to re-solve the same boring infrastructure problems: where to store data, how to detect the distro, how to install dependencies, how to ask for elevation, how to launch a terminal from a GUI session, and how to stay usable across different Linux setups.

JS-Forge already centralizes those problems. Instead of writing a one-off installer in every project, a fork can use the runtime library as a shared foundation and keep feature scripts much shorter and more readable.

That is especially helpful when building script packs with multiple entry points. One runtime can back many small tools, and those tools can all inherit the same UX rules, dependency behavior, and launch behavior.

## Workflow automation angle

JS-Forge is not just a launcher for single-purpose scripts. It is also a workflow automation shell for Linux tasks that need repeatable setup, dependency checking, and a predictable user-facing wrapper.

That means it can be used to automate desktop actions, package installs, Flatpak onboarding, repository sync jobs, repair flows, bootstrap routines, scripted maintenance, and curated multi-step utilities without each script having to reinvent its own UX layer.

For users, that makes automation feel approachable. For builders, it means automation can be shipped as a clean menu action instead of as a loose pile of shell snippets.

## Extension system

Extensions are regular `.ext` Bash files that get sourced at startup from the resolved extension directories.

An extension can register menu keys, labels, and callbacks by writing into the global extension arrays, which lets the main app expose extra actions without hardcoding them into the central menu logic.

This is the main hook for community involvement. A contributor does not need to rewrite the launcher; they can ship one focused extension that adds a workflow, report, fix, automation path, or integration.

## Script visibility by package manager

One of the more useful but easy-to-miss features is that JS-Forge can filter runnable scripts by package-manager-specific filename extensions.

The launcher recognizes regular `.sh` scripts, but it can also recognize scripts named for a specific package manager such as `.apt`, `.dnf`, `.yum`, `.pacman`, or `.zypper`. A script with one of those suffixes only appears on systems where the matching package manager is detected.

This makes it possible to keep distro-targeted actions in the same script vault without confusing the user with actions that do not apply to their machine.

For example:

```text
install-docker.apt
install-docker.dnf
install-docker.pacman
```

With a setup like that, an Ubuntu-based system can show the `.apt` variant while hiding the Fedora or Arch variants, and a Fedora-based system can show the `.dnf` variant instead.

That is useful both for project maintainers and end users. It gives builders a simple way to ship package-manager-aware automation without having to build a second filtering system into each script by hand.

## Pause and no-pause launch modes

JS-Forge now supports two useful launch styles for scripts.

The default paused mode is ideal for installers, repair tools, and larger workflows where the user should be able to read the output before the terminal session ends.

A no-pause path is also available for launcher-style scripts that are only meant to start an app, hand off to a Flatpak, or trigger a short background action and then return immediately.

This matters most in GUI mode, where some scripts benefit from returning fast instead of leaving a helper terminal waiting on a prompt. At the same time, heavier installer flows still keep the older, safer pause behavior.

That split makes JS-Forge easier to tweak because a contributor can decide per script whether the action should behave like an installer or like a fast launcher.

### Example: no-pause launcher script

Put this near the top of a launcher-style script:

```bash
#!/bin/bash
jsf_no_pause="1"

app_name="JS-Forge"
runtime_core_path="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
```

That marker tells JS-Forge the script should launch and return without the normal post-run pause.

### Example: default paused script

If a script should keep the normal installer-style behavior, do not add the no-pause marker:

```bash
#!/bin/bash

app_name="JS-Forge"
runtime_core_path="${XDG_DATA_HOME:-$HOME/.local/share}/$app_name/runtime-core.lib"

source "$runtime_core_path" || {
    echo "Fatal: failed to source JS-Forge runtime: $runtime_core_path" >&2
    exit 1
}

jsf_init_runtime_core
```

That keeps the standard paused flow, which is usually what you want for bigger installs, repair jobs, or anything with output the user may need to read.

## Included extension examples

### xProbe

xProbe is the environment audit layer. It checks for unsupported cases such as raw TTY launches, WSL, and unsupported package managers, then records system and dependency information into a report the user can open later.

It also demonstrates auto-remediation patterns by installing missing native tools and required Flatpaks when needed.

### GitEngine

GitEngine turns JS-Forge into a script-vault intake tool. It maintains a repository list file, clones listed repositories into the script folder, updates them with `git pull`, and can bulk-delete them when needed.

That makes it useful for teams or personal script collections where the launcher is meant to curate many small repos instead of one monolithic codebase.

### Updates

The updates extension queries the latest GitHub release from the configured repository, strips a leading `v` from tags, compares versions, and can notify automatically on an interval or manually from the menu.

This is a clean example of how to bolt network-aware maintenance features onto the main app without bloating the core launcher.

### Emoji support

The emoji extension shows a more repair-oriented use case. It can detect missing `fontconfig` support or missing `Noto Color Emoji`, install what is needed, refresh caches, and write a fallback config so terminals can render emoji more reliably.

It is also a good example of an extension that exists to improve presentation quality rather than add a whole new menu-driven app area.

## Forking and customizing

A fork can go in several directions without throwing away the existing structure.

- Rebrand the app metadata in `AppRun`, including app name, versioning, command name, and credits text.
- Swap the default dependency list and Flatpak requirements in xProbe to match the fork's actual toolchain.
- Keep the runtime core stable and build most new behavior as `.ext` files so the launcher stays simpler to maintain.
- Turn on user extensions with `allow_user_extensions="1"` if the fork should support per-user plug-ins from the data directory.
- Replace the repository seed list used by GitEngine with the fork's own curated script vault.
- Retune or remove opinionated warnings if the fork should be more neutral about init systems or display servers.
- Use package-manager-specific script suffixes when the fork should expose different implementations to different Linux families.
- Decide which scripts should keep the default pause behavior and which should return immediately as no-pause launcher actions.

A good rule of thumb is to treat `runtime-core.lib` as shared infrastructure, `AppRun` as the branded shell and top-level experience, and `.ext` files as feature modules.

## Building new scripts with the runtime

A simple workflow for contributors looks like this:

1. Start a new Bash script and source `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib`.
2. Call `jsf_init_runtime_core` to prepare paths, extension discovery, privilege state, and package-manager helpers.
3. Call `jsf_require_all` with any native packages and Flatpaks the script needs before doing real work.
4. Use the runtime's UI helpers such as `center`, `divider`, `print_red`, `text_delay`, and terminal-launch helpers to keep the script consistent with the rest of the project.
5. If the script should appear in the JS-Forge UI, package it or wrap it as a runnable script or extension inside the discovered script/extension locations.
6. If the script is package-manager-specific, give it the matching suffix so it only appears on the right systems.
7. If the script is a pure launcher, use the no-pause path; if it is an installer or repair flow, keep the default pause behavior.

## What contributors can build

Because the runtime already solves environment checks and installation flows, contributors can spend their time on actual tools.

Examples include:

- guided repair tools
- repo-based script installers
- package/Flatpak bootstrap tools
- menu-driven desktop utilities
- diagnostics and compatibility reports
- wrappers around existing command-line tools
- opinionated Linux onboarding kits
- distro-targeted actions using package-manager-specific script suffixes
- repeatable workflow automation packs for common Linux tasks

## Current Linux assumptions

The current code is Linux-focused and explicitly rejects unsupported raw TTY launches and WSL sessions in xProbe.

It expects a supported package manager family, and many workflows assume a desktop-oriented Linux environment where Zenity, terminal emulators, Flatpak, and common command-line tools are reasonable dependencies.

## Suggested repository shape

A practical repository for this project or a fork would include at minimum the launcher, runtime library, documented extensions, license, and a stronger README.

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

## Getting started

Example local launch:

```bash
chmod +x AppRun
./AppRun
```

If the runtime library has been bootstrapped into the data directory by `AppRun`, standalone scripts can source `${XDG_DATA_HOME:-$HOME/.local/share}/JS-Forge/runtime-core.lib` and reuse the same helper layer directly.

## Philosophy

JS-Forge is most useful when treated less like a single script and more like a Bash toolbox platform.

The launcher, runtime core, and extensions together form a lightweight framework for shipping interactive Linux utilities, automation flows, and curated script packs quickly, while still leaving enough room for a fork to become its own thing.
