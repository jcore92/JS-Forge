#!/bin/bash

echo "Warning!: This script was only designed for apt usage and needs to be updated for full support of other package managers."

entertocontinue

tool_to_pkg_name() {
case "$1" in
"nextcloud") echo "nextcloud-desktop" ;;
*)     echo "$1" ;;
esac
}

loop="1"
choices=("Vivaldi" "Brave" "Librewolf" "Exit")
while [ $loop -eq 1 ]; do
clear ; echo "Pick a Web Browser to install:"
cursor_menu " " selected "${choices[@]}"

if [ "$selected" == "Vivaldi" ]; then

check_programs() {
#ksystemlog calibre
local missing=()
local programs=("vivaldi")  # Add more here

for prog in "${programs[@]}"; do
if ! command -v "$prog" &>/dev/null; then
echo -e " ✕ $prog is not installed" | print_red
missing+=("$(tool_to_pkg_name "$prog")")
#missing+=("$prog")
else
echo -e " ✓ $prog is installed"
fi
done

if [ ${#missing[@]} -ne 0 ]; then
xdg-open https://vivaldi.com/download/ &> /dev/null
echo "Download the latest .deb version of Vivaldi." ; entertocontinue
selected_file=$(zenity --file-selection --title="Choose the Vivaldi .deb you downloaded.")

echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; sudo apt install "$selected_file"
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Brave" ]; then
check_programs() {
#ksystemlog calibre
local missing=()
local programs=("brave-browser")  # Add more here

for prog in "${programs[@]}"; do
if ! command -v "$prog" &>/dev/null; then
echo -e " ✕ $prog is not installed" | print_red
missing+=("$(tool_to_pkg_name "$prog")")
#missing+=("$prog")
else
echo -e " ✓ $prog is installed"
fi
done

if [ ${#missing[@]} -ne 0 ]; then
echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; curl -fsS https://dl.brave.com/install.sh | sh
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Librewolf" ]; then
check_programs() {
#ksystemlog calibre
local missing=()
local programs=("librewolf")  # Add more here

for prog in "${programs[@]}"; do
if ! command -v "$prog" &>/dev/null; then
echo -e " ✕ $prog is not installed" | print_red
missing+=("$(tool_to_pkg_name "$prog")")
#missing+=("$prog")
else
echo -e " ✓ $prog is installed"
fi
done

if [ ${#missing[@]} -ne 0 ]; then
echo "Attempting to install package(s): '${missing[*]}'" ; printf " 🔐 " ; sudo apt update && sudo apt install extrepo -y ; sudo extrepo enable librewolf ; sudo apt update && sudo apt install librewolf -y
fi
}


if check_programs; then
sleep 1
else
exit
fi
fi

if [ "$selected" == "Exit" ]; then
loop="0"
fi

done
