#!/bin/bash
# v4l-saver.sh: Save and load V4L2 device controls
#
# Copyright (c) 2025 v4l-saver contributors
# Licensed under the MIT License. See LICENSE file for details.

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/v4l-saver"
mkdir -p "$CONFIG_DIR"

# Check for required dependencies
check_dependencies() {
    local missing_deps=()
    local all_deps=("v4l2-ctl" "find" "grep" "awk" "sed" "sort" "cut" "printf" "date")
    
    for dep in "${all_deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo "Error: Missing required dependencies: ${missing_deps[*]}" >&2
        echo "" >&2
        echo "Installation instructions:" >&2
        echo "" >&2
        echo "Debian/Ubuntu:" >&2
        echo "  sudo apt update" >&2
        echo "  sudo apt install v4l-utils coreutils findutils grep gawk sed" >&2
        echo "" >&2
        echo "Arch Linux:" >&2
        echo "  sudo pacman -S v4l-utils coreutils findutils grep gawk sed" >&2
        echo "" >&2
        echo "Fedora/RHEL/CentOS:" >&2
        echo "  sudo dnf install v4l-utils coreutils findutils grep gawk sed" >&2
        echo "  # or on older versions:" >&2
        echo "  sudo yum install v4l-utils coreutils findutils grep gawk sed" >&2
        echo "" >&2
        echo "Alpine Linux:" >&2
        echo "  sudo apk add v4l-utils coreutils findutils grep gawk sed" >&2
        echo "" >&2
        echo "Note: Most core utilities (grep, awk, sed, etc.) are typically pre-installed." >&2
        echo "The main dependency you likely need is 'v4l-utils' for v4l2-ctl." >&2
        return 1
    fi
    
    # Check if /dev/video* devices exist
    if ! ls /dev/video* >/dev/null 2>&1; then
        echo "Warning: No video devices found in /dev/" >&2
        echo "Make sure your camera/video devices are connected and detected by the kernel." >&2
        echo "You can check with: lsusb | grep -i camera" >&2
        echo "Or check kernel messages: dmesg | grep -i video" >&2
    fi
    
    return 0
}

usage() {
    echo "Usage: $0 [--save|--load|--list|--json|--help] [device]"
    echo "  --save [device]   Save controls for all or specific /dev/video* device to $CONFIG_DIR (JSON format)"
    echo "  --load [device]   Load controls for all or specific /dev/video* device from $CONFIG_DIR (JSON format)"
    echo "  --list            List available video devices in table format"
    echo "  --json            List available video devices in JSON format"
    echo "  --help            Show this help message"
    echo ""
    echo "Device can be specified as:"
    echo "  - Device path: /dev/video0, /dev/video2, etc."
    echo "  - Serial number: 1234ABCD, 5678EFGH, etc."
    echo ""
    echo "Examples:"
    echo "  $0 --save                 # Save all usable devices"
    echo "  $0 --save /dev/video0     # Save specific device"
    echo "  $0 --load 1234ABCD        # Load device with serial 1234ABCD"
}

# Check if device is usable (has formats and resolutions)
is_device_usable() {
    local dev="$1"
    local formats_output=$(v4l2-ctl --device="$dev" --list-formats-ext 2>/dev/null)
    
    if [ -z "$formats_output" ]; then
        return 1
    fi
    
    local basic_formats=$(echo "$formats_output" | grep -E "^\s*\[[0-9]+\]:" | sed "s/.*'\([^']*\)'.*/\1/" 2>/dev/null)
    if [ -z "$basic_formats" ]; then
        return 1
    fi
    
    # Check if at least one format has resolutions
    local first_format=$(echo "$basic_formats" | head -1)
    local highest_res=$(echo "$formats_output" | grep -A 100 "Format.*$first_format\|^\s*\[[0-9]*\]:.*$first_format" | \
                      grep "Size: Discrete" | grep -o '[0-9]\+x[0-9]\+' | head -1)
    
    if [ -n "$highest_res" ]; then
        return 0
    else
        return 1
    fi
}

# Find device by serial number
find_device_by_serial() {
    local target_serial="$1"
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            local info=$(v4l2-ctl --device="$dev" --info 2>/dev/null)
            local serial=$(echo "$info" | grep -i 'Serial' | awk -F': ' '{print $2}')
            if [ "$serial" = "$target_serial" ]; then
                echo "$dev"
                return 0
            fi
        fi
    done
    return 1
}

list_devices() {
    printf "%-12s %-8s %-15s %-35s %s\n" "Device" "SN" "Vendor" "Card Type" "Format Info"
    printf "%-12s %-8s %-15s %-35s %s\n" "------" "--" "------" "---------" "-----------"
    
    # Collect device information first
    usable_devices=""
    unusable_devices=""
    
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            info=$(v4l2-ctl --device="$dev" --info)
            card=$(echo "$info" | grep -i 'Card type' | awk -F': ' '{print $2}')
            vendor=$(echo "$info" | grep -i 'Bus info\|Vendor' | awk -F': ' '{print $2}' | head -1)
            serial=$(echo "$info" | grep -i 'Serial' | awk -F': ' '{print $2}')
            
            # Try to get more detailed vendor info from by-id links
            by_id_info=""
            if [ -d "/dev/v4l/by-id" ]; then
                by_id_link=$(find /dev/v4l/by-id -lname "*$(basename "$dev")" 2>/dev/null | head -1)
                if [ -n "$by_id_link" ]; then
                    by_id_name=$(basename "$by_id_link")
                    # Extract vendor from the by-id name (usually first part before underscore)
                    by_id_vendor=$(echo "$by_id_name" | sed 's/usb-\([^_]*\).*/\1/' | sed 's/-/ /g')
                    if [ -n "$by_id_vendor" ] && [ "$by_id_vendor" != "$by_id_name" ]; then
                        by_id_info="$by_id_vendor"
                    fi
                fi
            fi
            
            # Get format information
            formats_output=$(v4l2-ctl --device="$dev" --list-formats-ext 2>/dev/null)
            device_status=""
            format_info=""
            is_usable="1"
            
            if [ -n "$formats_output" ]; then
                # Try to extract just basic format info if detailed parsing fails
                basic_formats=$(echo "$formats_output" | grep -E "^\s*\[[0-9]+\]:" | sed "s/.*'\([^']*\)'.*/\1/" 2>/dev/null)
                if [ -n "$basic_formats" ]; then
                    format_count=$(echo "$basic_formats" | wc -l)
                    first_format=$(echo "$basic_formats" | head -1)
                    
                    # Get highest resolution for first format
                    highest_res=$(echo "$formats_output" | grep -A 100 "Format.*$first_format\|^\s*\[[0-9]*\]:.*$first_format" | \
                                 grep "Size: Discrete" | grep -o '[0-9]\+x[0-9]\+' | \
                                 sort -t'x' -k1,1n -k2,2n | tail -1)
                    
                    if [ -n "$highest_res" ]; then
                        # Get max fps for highest resolution
                        max_fps=$(echo "$formats_output" | grep -A 20 "Size: Discrete $highest_res" | \
                                 grep "fps)" | grep -o '[0-9.]\+ fps' | sed 's/ fps//' | sort -n | tail -1)
                        if [ -n "$max_fps" ]; then
                            format_info="$first_format up to ${highest_res}@${max_fps}fps"
                        else
                            format_info="$first_format up to $highest_res"
                        fi
                        if [ "$format_count" -gt 1 ]; then
                            format_info="$format_info (+$((format_count-1)) more formats)"
                        fi
                    else
                        format_info="$first_format (no resolutions found)"
                        device_status=" [PROBABLY NOT USABLE]"
                        is_usable="0"
                    fi
                else
                    device_status=" [PROBABLY NOT USABLE - cannot parse formats]"
                    is_usable="0"
                fi
            else
                device_status=" [PROBABLY NOT USABLE - no capture formats]"
                is_usable="0"
            fi
            
            # Extract device number for proper sorting
            dev_num=$(echo "$dev" | sed 's/.*video//')
            sort_key=$(printf "%03d" "$dev_num" 2>/dev/null || echo "$dev_num")
            
            # Format output line
            vendor_display=""
            [ -n "$by_id_info" ] && vendor_display="$by_id_info" || [ -n "$vendor" ] && vendor_display="$(echo "$vendor" | cut -c1-15)"
            
            serial_display=""
            [ -n "$serial" ] && serial_display="$(echo "$serial" | cut -c1-8)"
            
            card_display=""
            [ -n "$card" ] && card_display="$(echo "$card" | cut -c1-35)"
            
            output_line=$(printf "%-12s %-8s %-15s %-35s %s%s" "$dev" "$serial_display" "$vendor_display" "$card_display" "$format_info" "$device_status")
            
            # Add to appropriate list with sort key
            if [ "$is_usable" = "1" ]; then
                usable_devices="$usable_devices$sort_key|$output_line\n"
            else
                unusable_devices="$unusable_devices$sort_key|$output_line\n"
            fi
        fi
    done
    
    # Sort and display usable devices first
    if [ -n "$usable_devices" ]; then
        printf "$usable_devices" | sort -t'|' -k1,1n | cut -d'|' -f2-
    fi
    
    # Then sort and display unusable devices
    if [ -n "$unusable_devices" ]; then
        printf "$unusable_devices" | sort -t'|' -k1,1n | cut -d'|' -f2-
    fi
}

list_devices_json() {
    echo "{"
    echo "  \"devices\": ["
    first_device=true
    
    for dev in /dev/video*; do
        if [ -c "$dev" ]; then
            if [ "$first_device" = false ]; then
                echo "    },"
            fi
            first_device=false
            
            info=$(v4l2-ctl --device="$dev" --info)
            card=$(echo "$info" | grep -i 'Card type' | awk -F': ' '{print $2}')
            vendor=$(echo "$info" | grep -i 'Bus info\|Vendor' | awk -F': ' '{print $2}' | head -1)
            serial=$(echo "$info" | grep -i 'Serial' | awk -F': ' '{print $2}')
            
            # Try to get more detailed vendor info from by-id links
            by_id_info=""
            if [ -d "/dev/v4l/by-id" ]; then
                by_id_link=$(find /dev/v4l/by-id -lname "*$(basename "$dev")" 2>/dev/null | head -1)
                if [ -n "$by_id_link" ]; then
                    by_id_name=$(basename "$by_id_link")
                    by_id_vendor=$(echo "$by_id_name" | sed 's/usb-\([^_]*\).*/\1/' | sed 's/-/ /g')
                    if [ -n "$by_id_vendor" ] && [ "$by_id_vendor" != "$by_id_name" ]; then
                        by_id_info="$by_id_vendor"
                    fi
                fi
            fi
            
            # Get format information
            formats_output=$(v4l2-ctl --device="$dev" --list-formats-ext 2>/dev/null)
            is_usable="true"
            formats_json=""
            
            if [ -n "$formats_output" ]; then
                basic_formats=$(echo "$formats_output" | grep -E "^\s*\[[0-9]+\]:" | sed "s/.*'\([^']*\)'.*/\1/" 2>/dev/null)
                if [ -n "$basic_formats" ]; then
                    formats_json="["
                    format_first=true
                    echo "$basic_formats" | while read format; do
                        if [ "$format_first" = false ]; then
                            formats_json="$formats_json,"
                        fi
                        format_first=false
                        
                        highest_res=$(echo "$formats_output" | grep -A 100 "Format.*$format\|^\s*\[[0-9]*\]:.*$format" | \
                                     grep "Size: Discrete" | grep -o '[0-9]\+x[0-9]\+' | \
                                     sort -t'x' -k1,1n -k2,2n | tail -1)
                        
                        if [ -n "$highest_res" ]; then
                            max_fps=$(echo "$formats_output" | grep -A 20 "Size: Discrete $highest_res" | \
                                     grep "fps)" | grep -o '[0-9.]\+ fps' | sed 's/ fps//' | sort -n | tail -1)
                            formats_json="$formats_json{\"format\":\"$format\",\"max_resolution\":\"$highest_res\""
                            [ -n "$max_fps" ] && formats_json="$formats_json,\"max_fps\":$max_fps"
                            formats_json="$formats_json}"
                        else
                            is_usable="false"
                            formats_json="$formats_json{\"format\":\"$format\",\"max_resolution\":null,\"max_fps\":null}"
                        fi
                    done
                    formats_json="$formats_json]"
                else
                    is_usable="false"
                    formats_json="[]"
                fi
            else
                is_usable="false"
                formats_json="[]"
            fi
            
            # JSON escape function for strings
            escape_json() {
                echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
            }
            
            echo "    {"
            echo "      \"device\": \"$dev\","
            [ -n "$serial" ] && echo "      \"serial\": \"$(escape_json "$serial")\"," || echo "      \"serial\": null,"
            [ -n "$by_id_info" ] && echo "      \"vendor\": \"$(escape_json "$by_id_info")\"," || [ -n "$vendor" ] && echo "      \"vendor\": \"$(escape_json "$vendor")\"," || echo "      \"vendor\": null,"
            [ -n "$card" ] && echo "      \"card_type\": \"$(escape_json "$card")\"," || echo "      \"card_type\": null,"
            echo "      \"usable\": $is_usable,"
            echo "      \"formats\": $formats_json"
        fi
    done
    
    if [ "$first_device" = false ]; then
        echo "    }"
    fi
    echo "  ]"
    echo "}"
}

save_controls() {
    local target_device="$1"
    
    # Define the controls we want to save
    local allowed_controls=(
        "brightness"
        "contrast"
        "saturation"
        "white_balance_automatic"
        "gain"
        "power_line_frequency"
        "white_balance_temperature"
        "sharpness"
        "backlight_compensation"
        "auto_exposure"
        "exposure_time_absolute"
        "exposure_dynamic_framerate"
        "pan_absolute"
        "tilt_absolute"
        "focus_absolute"
        "focus_automatic_continuous"
        "zoom_absolute"
    )
    
    # Determine devices to process
    local devices_to_process=""
    
    if [ -n "$target_device" ]; then
        # Check if target_device is a device path or serial number
        if [[ "$target_device" =~ ^/dev/video[0-9]+$ ]]; then
            # It's a device path
            if [ -c "$target_device" ]; then
                devices_to_process="$target_device"
            else
                echo "Error: Device $target_device not found"
                return 1
            fi
        else
            # It's probably a serial number
            local found_device
            found_device=$(find_device_by_serial "$target_device")
            if [ -n "$found_device" ]; then
                devices_to_process="$found_device"
                echo "Found device $found_device for serial number $target_device"
            else
                echo "Error: No device found with serial number $target_device"
                return 1
            fi
        fi
    else
        # Process all devices
        devices_to_process=$(ls /dev/video* 2>/dev/null | tr '\n' ' ')
    fi
    
    for dev in $devices_to_process; do
        if [ -c "$dev" ]; then
            # Skip unusable devices
            if ! is_device_usable "$dev"; then
                echo "Skipping $dev (device is not usable for capture)"
                continue
            fi
            
            # Get device info
            info=$(v4l2-ctl --device="$dev" --info)
            card=$(echo "$info" | grep -i 'Card type' | awk -F': ' '{print $2}')
            vendor=$(echo "$info" | grep -i 'Bus info\|Vendor' | awk -F': ' '{print $2}' | head -1)
            serial=$(echo "$info" | grep -i 'Serial' | awk -F': ' '{print $2}')
            
            # Skip devices without serial numbers
            if [ -z "$serial" ]; then
                echo "Skipping $dev (no serial number found)"
                continue
            fi
            
            # Use serial number as filename (sanitize it first)
            safe_serial=$(echo "$serial" | sed 's/[^a-zA-Z0-9_-]/_/g')
            fname="$CONFIG_DIR/${safe_serial}.json"
            echo "Saving $dev (SN: $serial) to $fname"
            
            # Get controls
            controls_output=$(v4l2-ctl --device="$dev" --all 2>/dev/null)
            
            # JSON escape function
            escape_json() {
                echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
            }
            
            # Start JSON file
            {
                echo "{"
                echo "  \"device\": \"$dev\","
                echo "  \"serial\": \"$(escape_json "$serial")\","
                echo "  \"timestamp\": \"$(date -Iseconds)\","
                [ -n "$card" ] && echo "  \"card_type\": \"$(escape_json "$card")\"," || echo "  \"card_type\": null,"
                [ -n "$vendor" ] && echo "  \"vendor\": \"$(escape_json "$vendor")\"," || echo "  \"vendor\": null,"
                echo "  \"controls\": {"
                
                # Parse controls and convert to JSON, but only for allowed controls
                first_ctrl=true
                for ctrl in "${allowed_controls[@]}"; do
                    # Look for this specific control in the output
                    ctrl_line=$(echo "$controls_output" | grep -E "^\s+${ctrl}\s+")
                    if [ -n "$ctrl_line" ]; then
                        val=$(echo "$ctrl_line" | awk '{print $3}')
                        ctrl_type=$(echo "$ctrl_line" | awk '{print $2}' | tr -d '()')
                        
                        if [ -n "$val" ]; then
                            if [ "$first_ctrl" = false ]; then
                                echo ","
                            fi
                            first_ctrl=false
                            
                            # Determine if value is numeric
                            if echo "$val" | grep -qE '^-?[0-9]+$'; then
                                printf "    \"$ctrl\": {\"value\": $val, \"type\": \"$ctrl_type\"}"
                            else
                                printf "    \"$ctrl\": {\"value\": \"$(escape_json "$val")\", \"type\": \"$ctrl_type\"}"
                            fi
                        fi
                    fi
                done
                echo ""
                echo "  }"
                echo "}"
            } > "$fname"
            
            # Count how many controls were saved
            ctrl_count=$(grep -c '"value":' "$fname" 2>/dev/null || echo "0")
            echo "  Saved $ctrl_count supported controls"
        fi
    done
}

load_controls() {
    local target_device="$1"
    
    # Define the controls we want to load
    local allowed_controls=(
        "brightness"
        "contrast"
        "saturation"
        "white_balance_automatic"
        "gain"
        "power_line_frequency"
        "white_balance_temperature"
        "sharpness"
        "backlight_compensation"
        "auto_exposure"
        "exposure_time_absolute"
        "exposure_dynamic_framerate"
        "pan_absolute"
        "tilt_absolute"
        "focus_absolute"
        "focus_automatic_continuous"
        "zoom_absolute"
    )
    
    # Determine devices to process
    local devices_to_process=""
    
    if [ -n "$target_device" ]; then
        # Check if target_device is a device path or serial number
        if [[ "$target_device" =~ ^/dev/video[0-9]+$ ]]; then
            # It's a device path
            if [ -c "$target_device" ]; then
                devices_to_process="$target_device"
            else
                echo "Error: Device $target_device not found"
                return 1
            fi
        else
            # It's probably a serial number
            local found_device
            found_device=$(find_device_by_serial "$target_device")
            if [ -n "$found_device" ]; then
                devices_to_process="$found_device"
                echo "Found device $found_device for serial number $target_device"
            else
                echo "Error: No device found with serial number $target_device"
                return 1
            fi
        fi
    else
        # Process all devices
        devices_to_process=$(ls /dev/video* 2>/dev/null | tr '\n' ' ')
    fi
    
    for dev in $devices_to_process; do
        if [ -c "$dev" ]; then
            # Skip unusable devices
            if ! is_device_usable "$dev"; then
                echo "Skipping $dev (device is not usable for capture)"
                continue
            fi
            
            # Get device info to find serial number
            info=$(v4l2-ctl --device="$dev" --info)
            serial=$(echo "$info" | grep -i 'Serial' | awk -F': ' '{print $2}')
            
            if [ -z "$serial" ]; then
                echo "Skipping $dev (no serial number found)"
                continue
            fi
            
            # Use serial number to find config file
            safe_serial=$(echo "$serial" | sed 's/[^a-zA-Z0-9_-]/_/g')
            fname="$CONFIG_DIR/${safe_serial}.json"
            
            if [ -f "$fname" ]; then
                echo "Loading $dev (SN: $serial) from $fname"
                
                # Verify this is the correct device by checking serial in file
                file_serial=$(grep '"serial"' "$fname" | sed 's/.*"serial":\s*"\([^"]*\)".*/\1/')
                if [ "$serial" != "$file_serial" ]; then
                    echo "  Warning: Serial number mismatch (file: $file_serial, device: $serial)"
                    echo "  Skipping load for safety"
                    continue
                fi
                
                # Parse JSON and extract controls, but only allowed ones
                loaded_count=0
                for ctrl in "${allowed_controls[@]}"; do
                    # Look for this specific control in the JSON file
                    if grep -q "\"$ctrl\"" "$fname"; then
                        value_line=$(grep -A 2 "\"$ctrl\"" "$fname" | grep '"value"' | head -1)
                        if [ -n "$value_line" ]; then
                            # Extract numeric value (remove quotes if string)
                            val=$(echo "$value_line" | sed 's/.*"value":\s*\([^,}]*\).*/\1/' | sed 's/"//g')
                            
                            if [ -n "$val" ]; then
                                echo "  Setting $ctrl=$val"
                                if v4l2-ctl --device="$dev" --set-ctrl="$ctrl=$val" 2>/dev/null; then
                                    ((loaded_count++))
                                else
                                    echo "    Warning: Failed to set $ctrl (control may not be supported)"
                                fi
                            fi
                        fi
                    fi
                done
                
                echo "  Loaded $loaded_count controls successfully"
                
            else
                # Try to find legacy files by device name for backward compatibility
                legacy_fname="$CONFIG_DIR/$(basename $dev).json"
                old_legacy_fname="$CONFIG_DIR/$(basename $dev).ctrls"
                
                if [ -f "$legacy_fname" ]; then
                    echo "Loading $dev from legacy device-based file: $legacy_fname"
                    echo "  Note: Consider re-saving to use serial-based naming"
                    loaded_count=0
                    for ctrl in "${allowed_controls[@]}"; do
                        if grep -q "\"$ctrl\"" "$legacy_fname"; then
                            value_line=$(grep -A 2 "\"$ctrl\"" "$legacy_fname" | grep '"value"' | head -1)
                            if [ -n "$value_line" ]; then
                                val=$(echo "$value_line" | sed 's/.*"value":\s*\([^,}]*\).*/\1/' | sed 's/"//g')
                                if [ -n "$val" ]; then
                                    echo "  Setting $ctrl=$val"
                                    if v4l2-ctl --device="$dev" --set-ctrl="$ctrl=$val" 2>/dev/null; then
                                        ((loaded_count++))
                                    else
                                        echo "    Warning: Failed to set $ctrl"
                                    fi
                                fi
                            fi
                        fi
                    done
                    echo "  Loaded $loaded_count controls from legacy format"
                    
                elif [ -f "$old_legacy_fname" ]; then
                    echo "Loading $dev from old legacy format: $old_legacy_fname"
                    echo "  Note: Consider re-saving to use serial-based naming"
                    loaded_count=0
                    for ctrl in "${allowed_controls[@]}"; do
                        ctrl_line=$(grep -E "^\s+${ctrl}\s+" "$old_legacy_fname")
                        if [ -n "$ctrl_line" ]; then
                            val=$(echo "$ctrl_line" | awk '{print $3}')
                            if [ -n "$val" ]; then
                                echo "  Setting $ctrl=$val"
                                if v4l2-ctl --device="$dev" --set-ctrl="$ctrl=$val" 2>/dev/null; then
                                    ((loaded_count++))
                                else
                                    echo "    Warning: Failed to set $ctrl"
                                fi
                            fi
                        fi
                    done
                    echo "  Loaded $loaded_count controls from old legacy format"
                else
                    echo "No saved controls for $dev (SN: $serial)"
                fi
            fi
        fi
    done
}

# Check dependencies before proceeding
if ! check_dependencies; then
    exit 1
fi

case "$1" in
    --save)
        save_controls "$2"
        ;;
    --load)
        load_controls "$2"
        ;;
    --list)
        list_devices
        ;;
    --json)
        list_devices_json
        ;;
    --help|*)
        usage
        ;;
esac
