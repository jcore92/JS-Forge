#!/bin/bash
appimageappname="JS-Forge"
appdir="./$appimageappname.AppDir"
apprun="$appdir/AppRun"
rawloc="./Raw/AppRun"
desktopfile="$appdir/$appimageappname.desktop"

chmod +x ./appimagetool-x86_64.AppImage
chmod -R +x "$appdir"

# Extract version values from AppRun
app_ver_major=$(sed -n 's/^[[:space:]]*app_ver_major="\([^"]*\)".*/\1/p' "$apprun" | head -n1)
app_ver_minor=$(sed -n 's/^[[:space:]]*app_ver_minor="\([^"]*\)".*/\1/p' "$apprun" | head -n1)
app_ver_build=$(sed -n 's/^[[:space:]]*app_ver_build="\([^"]*\)".*/\1/p' "$apprun" | head -n1)
app_ver_stage=$(sed -n 's/^[[:space:]]*app_ver_stage="\([^"]*\)".*/\1/p' "$apprun" | head -n1)

if [[ -z "$app_ver_major" || -z "$app_ver_minor" || -z "$app_ver_build" ]]; then
    echo "Failed to extract version from $apprun"
    exit 1
fi

VERSION="${app_ver_major}.${app_ver_minor}.${app_ver_build}"
if [[ -n "$app_ver_stage" ]]; then
    VERSION="${VERSION}-${app_ver_stage}"
fi

export VERSION

echo "Building $appimageappname version $VERSION"

# Patch .desktop metadata before AppImage generation
if [[ -f "$desktopfile" ]]; then
    if grep -q '^X-AppImage-Version=' "$desktopfile"; then
        sed -i "s/^X-AppImage-Version=.*/X-AppImage-Version=$VERSION/" "$desktopfile"
    else
        printf '\nX-AppImage-Version=%s\n' "$VERSION" >> "$desktopfile"
    fi

    if grep -q '^X-AppImage-Name=' "$desktopfile"; then
        sed -i "s/^X-AppImage-Name=.*/X-AppImage-Name=$appimageappname/" "$desktopfile"
    else
        printf 'X-AppImage-Name=%s\n' "$appimageappname" >> "$desktopfile"
    fi

    if grep -q '^X-AppImage-Arch=' "$desktopfile"; then
        sed -i "s/^X-AppImage-Arch=.*/X-AppImage-Arch=x86_64/" "$desktopfile"
    else
        printf 'X-AppImage-Arch=%s\n' "x86_64" >> "$desktopfile"
    fi
else
    echo "Warning: desktop file not found at $desktopfile"
fi

if x-terminal-emulator -e bash -c "export VERSION='$VERSION'; ARCH=x86_64 ./appimagetool-x86_64.AppImage '$appdir' ; read -p ''"; then
    sleep .1
else
    # List of terminal emulators with their -e syntax
    terminals=(
    "xfce4-terminal -x"           # XFCE
    "konsole --execute"           # KDE
    "mate-terminal -x"            # MATE
    "kitty --execute"             # Kitty
    "gnome-terminal --"           # GNOME
    "lxterminal -e"               # LXDE
    "tilix -e"                    # Tilix (VTE-based)
    "alacritty --command"         # Alacritty
    "urxvt -e"                    # RXVT
    "terminator -e"               # Terminator
    "deepin-terminal -e"          # Deepin
    "wezterm start --"            # WezTerm
    "xterm -e"                    # XTerm
    )

    terminal_found=0

    for term in "${terminals[@]}"; do
        cmd=($term)  # Split into command and args
        if command -v "${cmd[0]}" &>/dev/null; then
            terminal_found=1
            "${cmd[@]}" bash -c "export VERSION='$VERSION'; ARCH=x86_64 ./appimagetool-x86_64.AppImage '$appdir' ; read -p ''"
            break # Exit the loop after the first successful command
        fi
    done

    if [[ $terminal_found -eq 0 ]]; then
        echo "No terminal emulator found. Please install xterm, gnome-terminal, or similar."
        #exit 1
    fi
fi

# Move generated AppImage into versioned build folder
builddir="./Builds/${appimageappname}-${VERSION}"
mkdir -p "$builddir"

latest_appimage=$(ls -t ./"$appimageappname"*.AppImage 2>/dev/null | head -n1)

sleep 1

if [[ -n "$latest_appimage" ]]; then
    echo "Moving $(basename "$latest_appimage") to $builddir/"
    mv "$latest_appimage" "$builddir/"
else
    echo "No generated AppImage found to move."
fi

# exec bash
exit