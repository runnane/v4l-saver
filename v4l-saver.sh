#!/bin/bash
# v4l-saver.sh: Save and load V4L2 device controls

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/v4l-saver"
mkdir -p "$CONFIG_DIR"

usage() {
    echo "Usage: $0 [--save|--load|--list|--help]"
    echo "  --save   Save controls for all /dev/video* devices to $CONFIG_DIR"
    echo "  --load   Load controls for all /dev/video* devices from $CONFIG_DIR"
    echo "  --list   List available video devices"
    echo "  --help   Show this help message"
}

list_devices() {
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            echo "Device: $dev"
            v4l2-ctl --device="$dev" --info
            echo "Supported formats:"
            v4l2-ctl --device="$dev" --list-formats-ext | sed 's/^/    /'
            echo "-----------------------------"
        fi
    done
}

save_controls() {
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            fname="$CONFIG_DIR/$(basename $dev).ctrls"
            echo "Saving $dev to $fname"
            v4l2-ctl --device="$dev" --all > "$fname"
        fi
    done
}

load_controls() {
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            fname="$CONFIG_DIR/$(basename $dev).ctrls"
            if [ -f "$fname" ]; then
                echo "Loading $dev from $fname"
                # Extract controls and set them
                grep -E '^\s+[a-zA-Z0-9_]+\s+' "$fname" | while read -r line; do
                    ctrl=$(echo "$line" | awk '{print $1}')
                    val=$(echo "$line" | awk '{print $3}')
                    if [[ "$ctrl" != "" && "$val" != "" ]]; then
                        v4l2-ctl --device="$dev" --set-ctrl="$ctrl=$val"
                    fi
                done
            else
                echo "No saved controls for $dev"
            fi
        fi
    done
}

if ! command -v v4l2-ctl &>/dev/null; then
    echo "Error: v4l2-ctl not found. Please install v4l-utils." >&2
    exit 1
fi

case "$1" in
    --save)
        save_controls
        ;;
    --load)
        load_controls
        ;;
    --list)
        list_devices
        ;;
    --help|*)
        usage
        ;;
esac
