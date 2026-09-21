set -e

CONFIG_FILE="/etc/keyd/multimedia.conf"

if [ "$EUID" -ne 0 ]; then
    if [ -t 0 ]; then
        exec sudo bash "$0" "$@"
    else
        script_file=$(mktemp)
        cat > "$script_file"
        exec sudo bash "$script_file" "$@"
    fi
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
    read -rp "Choose [1/2]: " choice

    case "$choice" in
        1)
            DEVICE_ID=""
            break
            ;;
        2)
            DEVICE_ID="*"
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

    DEVICE_LIST=$(mktemp)

    cleanup() {
        rm -f "$DEVICE_LIST"
    }

    trap cleanup EXIT

    stdbuf -oL keyd monitor >"$DEVICE_LIST" 2>&1 &
    MONITOR_PID=$!

    sleep 1

    kill -KILL "$MONITOR_PID" >/dev/null 2>&1 || true
    wait "$MONITOR_PID" >/dev/null 2>&1 || true

    mapfile -t DEVICES < <(
        sed -n 's/^device added: \([^ ]*\) \(.*\) (\/dev\/input\/.*)$/\1|\2/p' "$DEVICE_LIST" |
        sort -u
    )

    mapfile -t CHROMEBOOK_KEYBOARDS < <(
        printf '%s\n' "${DEVICES[@]}" |
        grep -Ei '\|.*(at translated set 2 keyboard|at-translated-set-2-keyboard|chromebook.*keyboard|chromeos.*keyboard|keyboard.*chromebook|keyboard.*chromeos)' |
        sort -u
    )

    if [ "${#CHROMEBOOK_KEYBOARDS[@]}" -eq 1 ]; then
        DETECTED_ID="${CHROMEBOOK_KEYBOARDS[0]%%|*}"
        DETECTED_NAME="${CHROMEBOOK_KEYBOARDS[0]#*|}"

        echo
        echo "Found a likely built-in Chromebook keyboard:"
        echo
        echo "  $DETECTED_NAME"
        echo "  ID: $DETECTED_ID"
        echo

        read -rp "Use this keyboard? [Y/n]: " use_detected

        if [[ ! "$use_detected" =~ ^[Nn]$ ]]; then
            DEVICE_ID="$DETECTED_ID"
            DEVICE_NAME="$DETECTED_NAME"
        fi
    elif [ "${#CHROMEBOOK_KEYBOARDS[@]}" -gt 1 ]; then
        echo
        echo "Found multiple likely built-in Chromebook keyboards:"
        echo

        for i in "${!CHROMEBOOK_KEYBOARDS[@]}"; do
            id="${CHROMEBOOK_KEYBOARDS[$i]%%|*}"
            name="${CHROMEBOOK_KEYBOARDS[$i]#*|}"

            echo "  $((i + 1))) $name"
            echo "     $id"
        done

        echo

        while true; do
            read -rp "Which one is the built-in keyboard? [1-${#CHROMEBOOK_KEYBOARDS[@]}]: " keyboard_choice

            if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
               [ "$keyboard_choice" -ge 1 ] &&
               [ "$keyboard_choice" -le "${#CHROMEBOOK_KEYBOARDS[@]}" ]; then

                selected="${CHROMEBOOK_KEYBOARDS[$((keyboard_choice - 1))]}"
                DEVICE_ID="${selected%%|*}"
                DEVICE_NAME="${selected#*|}"
                break
            fi

            echo "Please choose one of the listed numbers."
        done
    fi

    if [ -z "${DEVICE_ID:-}" ]; then
        mapfile -t KEYBOARDS < <(
            printf '%s\n' "${DEVICES[@]}" |
            grep -Ei '\|.*keyboard' |
            sort -u
        )

        if [ "${#KEYBOARDS[@]}" -gt 0 ]; then
            echo
            echo "Keyboard devices found:"
            echo

            for i in "${!KEYBOARDS[@]}"; do
                id="${KEYBOARDS[$i]%%|*}"
                name="${KEYBOARDS[$i]#*|}"

                echo "  $((i + 1))) $name"
                echo "     $id"
            done

            SHOW_ALL_INDEX=$((${#KEYBOARDS[@]} + 1))

            echo
            echo "  $SHOW_ALL_INDEX) Show all detected devices"
            echo

            while true; do
                read -rp "Choose [1-$SHOW_ALL_INDEX]: " keyboard_choice

                if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
                   [ "$keyboard_choice" -ge 1 ] &&
                   [ "$keyboard_choice" -le "$SHOW_ALL_INDEX" ]; then

                    if [ "$keyboard_choice" -eq "$SHOW_ALL_INDEX" ]; then
                        KEYBOARDS=("${DEVICES[@]}")
                        break
                    fi

                    selected="${KEYBOARDS[$((keyboard_choice - 1))]}"
                    DEVICE_ID="${selected%%|*}"
                    DEVICE_NAME="${selected#*|}"
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

            KEYBOARDS=("${DEVICES[@]}")

            if [ "${#KEYBOARDS[@]}" -eq 0 ]; then
                echo "Couldn't find any input devices."
                echo
                read -rp "Enter the keyboard ID manually: " DEVICE_ID

                if [ -z "$DEVICE_ID" ]; then
                    echo "No device ID entered."
                    exit 1
                fi
            else
                for i in "${!KEYBOARDS[@]}"; do
                    id="${KEYBOARDS[$i]%%|*}"
                    name="${KEYBOARDS[$i]#*|}"

                    echo "  $((i + 1))) $name"
                    echo "     $id"
                done

                echo

                while true; do
                    read -rp "Which device is the built-in keyboard? [1-${#KEYBOARDS[@]}]: " keyboard_choice

                    if [[ "$keyboard_choice" =~ ^[0-9]+$ ]] &&
                       [ "$keyboard_choice" -ge 1 ] &&
                       [ "$keyboard_choice" -le "${#KEYBOARDS[@]}" ]; then

                        selected="${KEYBOARDS[$((keyboard_choice - 1))]}"
                        DEVICE_ID="${selected%%|*}"
                        DEVICE_NAME="${selected#*|}"
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

read -rp "Use these defaults? [Y/n]: " customize

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

if [[ "$customize" =~ ^[Nn]$ ]]; then
    echo
    echo "Enter a keyd binding for each key."
    echo "Press Enter to keep the default."
    echo

    read -rp "F1 [$F1]: " value
    [ -n "$value" ] && F1="$value"

    read -rp "F2 [$F2]: " value
    [ -n "$value" ] && F2="$value"

    read -rp "F3 [$F3]: " value
    [ -n "$value" ] && F3="$value"

    read -rp "F4 [$F4]: " value
    [ -n "$value" ] && F4="$value"

    read -rp "F5 [$F5]: " value
    [ -n "$value" ] && F5="$value"

    read -rp "F6 [$F6]: " value
    [ -n "$value" ] && F6="$value"

    read -rp "F7 [$F7]: " value
    [ -n "$value" ] && F7="$value"

    read -rp "F8 [$F8]: " value
    [ -n "$value" ] && F8="$value"

    read -rp "F9 [$F9]: " value
    [ -n "$value" ] && F9="$value"

    read -rp "F10 [$F10]: " value
    [ -n "$value" ] && F10="$value"
fi

mkdir -p /etc/keyd

cat > "$CONFIG_FILE" <<EOF
[ids]

$DEVICE_ID

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

if ! keyd check "$CONFIG_FILE"; then
    echo
    echo "The config failed validation."
    echo "Removing $CONFIG_FILE."
    rm -f "$CONFIG_FILE"
    exit 1
fi

systemctl restart keyd

echo
echo "Done."
echo
echo "Config:"
echo "  $CONFIG_FILE"
echo
echo "Device:"
echo "  $DEVICE_ID"
echo
echo "keyd is enabled and running."
