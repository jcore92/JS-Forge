#!/bin/bash

run_classic() {

clear

# Interactive file search: type pattern, press Enter to search
# Supports wildcards: *, ?, [a-z], etc.

echo "📁 Interactive File Search (press Enter to search, 'quit' to exit)"
echo "💡 Examples: *.pdf, config*, data?.log, [abc]*.txt"
echo ""

while true; do
    # Prompt user for input
    read -r -p "🔍 Search for file (with wildcards): " search_term

    # Exit if user types 'quit', 'exit', or just presses Enter with no input
    [[ -z "$search_term" || "$search_term" =~ ^(quit|exit)$ ]] && echo "👋 Goodbye!" && exit 0

    # Run find with the search term (case-insensitive, only files)
    echo ""
    echo "🔎 Searching for: '$search_term'"
    echo "----------------------------------------"

    # Use eval to allow shell-style globbing (wildcards), but safely pass to find
    find . -iname "$search_term" -type f 2>/dev/null | sort

    # Show how many results were found
    count=$(find /home -iname "$search_term" -type f 2>/dev/null | wc -l)
    echo "----------------------------------------"
    echo "✅ Found $count file(s)."
    echo ""
done
}

run_modern() {

# Interactive file search with wildcard support
# Uses find -iname for case-insensitive matching

MINLEN=1          # Start searching after 1 char (useful for wildcard *)
search_string=""
clear

echo "🔍 Interactive File Search (type to search, Backspace to delete, Esc to quit)"
echo "💡 Use wildcards: * (any), ? (one char), [abc] (char class)"
echo "💡 Example: *.txt, config??, data[1-2].log"

# Read one character at a time
while read -n 1 -s key; do
    ascii=$(printf "%d" "'$key")

    case "$ascii" in
        127)  # Backspace
            search_string="${search_string%?}"
            ;;
        27)   # Escape key
            echo -e "\n👋 Exiting..."
            exit 0
            ;;
        10)   # Enter key - optional: open in file manager or list again
            if [[ -n "$search_string" ]]; then
                echo -e "\n\n🎯 Final results for: \"$search_string\""
                find /home -iname "$search_string" -type f 2>/dev/null
                echo -e "\nPress any key to continue searching..."
                read -n 1 -s
            fi
            ;;
        *)
            # Append printable character
            search_string+="$key"
            ;;
    esac

    # Redraw UI
    clear
    echo "🔍 Search: \"$search_string\""
    echo "💡 Use wildcards: * (any), ? (one char), [abc] (char class)"
    echo "💡 Press Enter to lock results, Esc to quit, Backspace to edit"

    # Perform search if non-empty (even 1 char like "*" is valid)
    if [[ -n "$search_string" ]]; then
        # Use eval to allow shell pattern expansion, but safely via find -iname
        # We quote the pattern to prevent unintended glob expansion by the shell
        find . -iname "$search_string" -type f 2>/dev/null | head -n 50
        count=$(find . -iname "$search_string" -type f 2>/dev/null | wc -l)
        echo -e "\n📁 $count file(s) found (showing first 50)"
    fi
done

}

echo "Select your preferred Find Tool:"

    choices=("Modern" "Classic")
    cursor_menu " " selected "${choices[@]}"

    if [ "$selected" == "Modern" ]; then run_modern
    fi

    if [ "$selected" == "Classic" ]; then run_classic
    fi
