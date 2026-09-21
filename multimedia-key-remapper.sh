set -e

if [ "$EUID" -ne 0 ]; then
    if [ -t 0 ]; then
        exec sudo bash "$0" "$@"
    fi

    script_file=$(mktemp)
    cat > "$script_file"
    chmod +x "$script_file"

    exec sudo bash "$script_file" "$@"
fi

if [ -t 0 ]; then
    input="/dev/stdin"
else
    input="/dev/tty"
fi

if command -v keyd >/dev/null 2>&1; then
    echo "keyd is already installed."
else
    echo "Installing keyd..."
    echo

    if command -v pacman >/dev/null 2>&1; then
        pacman -S --needed keyd
    elif command -v apt-get >/dev/null 2>&1; then
        apt-get update
        apt-get install -y keyd
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y keyd
    elif command -v zypper >/dev/null 2>&1; then
        zypper install -y keyd
    else
        echo "Couldn't find keyd or a supported package manager."
        echo "Install keyd manually, then run this script again."
        exit 1
    fi

    echo
    echo "keyd is installed."
fi

echo

systemctl enable keyd >/dev/null 2>&1 || true

echo "What should keyd apply to?"
echo
echo "  1) Built-in / Chromebook keyboard only"
echo "  2) All keyboards"
echo

while true; do
    read -rp "Choose [1/2]: " choice <"$input"

    case "$choice" in
        1)
            device_id=""
            break
            ;;
        2)
            device_id="*"
            break
            ;;
        *)
            echo "Please enter 1 or 2."
            ;;
    esac
done

if [ "$choice" = "1" ]; then
    echo
    echo "Looking for keyboards..."

    device_list=$(mktemp)

    cleanup() {
        rm -f "$device_list"
    }

    trap cleanup EXIT

    stdbuf -oL keyd monitor >"$device_list" 2>&1 &
    monitor_pid=$!

    sleep 1

    kill -KILL "$monitor_pid" >/dev/null 2>&1 || true
    wait "$monitor_pid" >/dev/null 2>&1 || true

    mapfile -t devices < <(
        sed -n 's/^device added: \([^ ]*\) \(.*\) (\/dev\/input\/.*)$/\1|\2/p' "$device_list" |
        sort -u
    )

    mapfile -t chromebook_keyboards < <(
        printf '%s\n' "${devices[@]}" |
        grep -Ei '\|.*(at translated set 2 keyboard|at-translated-set-2-keyboard|chromebook.*keyboard|chromeos.*keyboard|keyboard.*chromebook|keyboard.*chromeos)' |
        sort -u
    )

    if [ "${#chromebook_keyboards[@]}" -eq 1 ]; then
        detected_id="${chromebook_keyboards[0]%%|*}"
        detected_name="${chromebook_keyboards[0]#*|}"

        echo
        echo "Found a likely built-in Chromebook keyboard:"
        echo
        echo "  $detected_name"
        echo "  ID: $detected_id"
        echo

        read -rp "Use this keyboard? [Y/n]: " use_detected <"$input"

        if [[ ! "$use_detected" =~ ^[Nn]$ ]]; then
            device_id="$detected_id"
            device_name="$detected_name"
        fi

    elif [ "${#chromebook_keyboards[@]}" -gt 1 ]; then
        echo
        echo "Found multiple likely built-in Chromebook keyboards:"
        echo

        for i in "${!chromebook_keyboards[@]}"; do
            id="${chromebook_keyboards[$i]%%|*}"
            name="${chromebook_keyboards[$i]#*|}"

            echo "  $((i + 1))) $name"
            echo "     $id"
        done

        echo

        while true; do
            read -rp "Which one is the built-in keyboard? [1-${#chromebook_keyboards[@]}]: " keyboard_choice <"$input"

            if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
               [ "$keyboard_choice" -ge 1 ] &&
               [ "$keyboard_choice" -le "${#chromebook_keyboards[@]}" ]; then

                selected="${chromebook_keyboards[$((keyboard_choice - 1))]}"
                device_id="${selected%%|*}"
                device_name="${selected#*|}"
                break
            fi

            echo "Please choose one of the listed numbers."
        done
    fi

    if [ -z "$device_id" ]; then
        mapfile -t keyboards < <(
            printf '%s\n' "${devices[@]}" |
            grep -Ei '\|.*keyboard' |
            sort -u
        )

        if [ "${#keyboards[@]}" -gt 0 ]; then
            echo
            echo "Keyboard devices found:"
            echo

            for i in "${!keyboards[@]}"; do
                id="${keyboards[$i]%%|*}"
                name="${keyboards[$i]#*|}"

                echo "  $((i + 1))) $name"
                echo "     $id"
            done

            show_all_index=$((${#keyboards[@]} + 1))

            echo
            echo "  $show_all_index) Show all detected devices"
            echo

            while true; do
                read -rp "Choose [1-$show_all_index]: " keyboard_choice <"$input"

                if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
                   [ "$keyboard_choice" -ge 1 ] &&
                   [ "$keyboard_choice" -le "$show_all_index" ]; then

                    if [ "$keyboard_choice" -eq "$show_all_index" ]; then
                        keyboards=("${devices[@]}")
                        break
                    fi

                    selected="${keyboards[$((keyboard_choice - 1))]}"
                    device_id="${selected%%|*}"
                    device_name="${selected#*|}"
                    break
                fi

                echo "Please choose one of the listed numbers."
            done

        else
            echo
            echo "No devices with 'keyboard' in their name were found."
            echo
            echo "All detected devices:"
            echo

            keyboards=("${devices[@]}")

            if [ "${#keyboards[@]}" -eq 0 ]; then
                echo "Couldn't find any input devices."
                echo

                read -rp "Enter the keyboard ID manually: " device_id <"$input"

                if [ -z "$device_id" ]; then
                    echo "No device ID entered."
                    exit 1
                fi
            else
                for i in "${!keyboards[@]}"; do
                    id="${keyboards[$i]%%|*}"
                    name="${keyboards[$i]#*|}"

                    echo "  $((i + 1))) $name"
                    echo "     $id"
                done

                echo

                while true; do
                    read -rp "Which device is the built-in keyboard? [1-${#keyboards[@]}]: " keyboard_choice <"$input"

                    if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
                       [ "$keyboard_choice" -ge 1 ] &&
                       [ "$keyboard_choice" -le "${#keyboards[@]}" ]; then

                        selected="${keyboards[$((keyboard_choice - 1))]}"
                        device_id="${selected%%|*}"
                        device_name="${selected#*|}"
                        break
                    fi

                    echo "Please choose one of the listed numbers."
                done
            fi
        fi
    fi
fi

echo
echo "Keybinds:"
echo
echo "  F1  = Back"
echo "  F2  = Forward"
echo "  F3  = Refresh"
echo "  F4  = Fullscreen/F11"
echo "  F5  = Left Meta"
echo "  F6  = Brightness Down"
echo "  F7  = Brightness Up"
echo "  F8  = Mute"
echo "  F9  = Volume Down"
echo "  F10 = Volume Up"
echo

F1="back"
F2="forward"
F3="refresh"
F4="f11"
F5="layer(meta)"
F6="brightnessdown"
F7="brightnessup"
F8="mute"
F9="volumedown"
F10="volumeup"

read -rp "Use these defaults? [Y/n]: " customize <"$input"

if [[ "$customize" =~ ^[Nn]$ ]]; then
    echo
    echo "Enter a keyd binding for each key."
    echo "Press Enter to keep the default."
    echo

    read -rp "F1 [$F1]: " value <"$input"
    [ -n "$value" ] && F1="$value"

    read -rp "F2 [$F2]: " value <"$input"
    [ -n "$value" ] && F2="$value"

    read -rp "F3 [$F3]: " value <"$input"
    [ -n "$value" ] && F3="$value"

    read -rp "F4 [$F4]: " value <"$input"
    [ -n "$value" ] && F4="$value"

    read -rp "F5 [$F5]: " value <"$input"
    [ -n "$value" ] && F5="$value"

    read -rp "F6 [$F6]: " value <"$input"
    [ -n "$value" ] && F6="$value"

    read -rp "F7 [$F7]: " value <"$input"
    [ -n "$value" ] && F7="$value"

    read -rp "F8 [$F8]: " value <"$input"
    [ -n "$value" ] && F8="$value"

    read -rp "F9 [$F9]: " value <"$input"
    [ -n "$value" ] && F9="$value"

    read -rp "F10 [$F10]: " value <"$input"
    [ -n "$value" ] && F10="$value"
fi

mkdir -p /etc/keyd

cat > /etc/keyd/multimedia.conf <<EOF
[ids]

$device_id

[main]

f1 = $F1
f2 = $F2
f3 = $F3
f4 = $F4
f5 = $F5
f6 = $F6
f7 = $F7
f8 = $F8
f9 = $F9
f10 = $F10

[meta]

f1 = f1
f2 = f2
f3 = f3
f4 = f4
f5 = f5
f6 = f6
f7 = f7
f8 = f8
f9 = f9
f10 = f10
EOF

echo
echo "Checking configuration..."

if ! keyd check /etc/keyd/multimedia.conf; then
    echo
    echo "The config failed validation."
    echo "Removing /etc/keyd/multimedia.conf."
    rm -f /etc/keyd/multimedia.conf
    exit 1
fi

systemctl restart keyd

echo
echo "Done."
echo
echo "Config:"
echo "  /etc/keyd/multimedia.conf"
echo
echo "Device:"
echo "  $device_id"
echo
echo "keyd is enabled and running."
