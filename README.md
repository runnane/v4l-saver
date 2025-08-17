# v4l-saver

A comprehensive bash script for managing V4L2 (Video4Linux2) device controls. Save and restore camera/video device settings, and list available devices with detailed information.

## Features

- **Save/Load Controls**: Save camera settings to JSON configuration files and restore them later
- **Device Listing**: Display all video devices in table or JSON format with detailed information
- **Serial-based Identification**: Uses device serial numbers for reliable device matching across reboots
- **Smart Filtering**: Only processes usable capture devices (skips unusable ones)
- **Multiple Input Methods**: Accept device paths (`/dev/video0`) or serial numbers (`1234ABCD`)
- **Dependency Checking**: Automatically checks for required system dependencies
- **Legacy Compatibility**: Supports loading old configuration file formats

## Installation

1. Clone or download the script:
   ```bash
   git clone <repo-url>
   cd v4l-saver
   chmod +x v4l-saver.sh
   ```

2. Install dependencies (if not already present):

   **Debian/Ubuntu:**
   ```bash
   sudo apt update
   sudo apt install v4l-utils coreutils findutils grep gawk sed
   ```

   **Arch Linux:**
   ```bash
   sudo pacman -S v4l-utils coreutils findutils grep gawk sed
   ```

   **Fedora/RHEL/CentOS:**
   ```bash
   sudo dnf install v4l-utils coreutils findutils grep gawk sed
   # or on older versions:
   sudo yum install v4l-utils coreutils findutils grep gawk sed
   ```

   **Alpine Linux:**
   ```bash
   sudo apk add v4l-utils coreutils findutils grep gawk sed
   ```

   > **Note:** Most core utilities (grep, awk, sed, etc.) are typically pre-installed. The main dependency you'll need is `v4l-utils` for the `v4l2-ctl` command.

## Usage

```
./v4l-saver.sh [--save|--load|--list|--json|--help] [device]
```

### Command Line Options

| Option | Description |
|--------|-------------|
| `--save [device]` | Save controls for all or specific /dev/video* device to config directory (JSON format) |
| `--load [device]` | Load controls for all or specific /dev/video* device from config directory (JSON format) |
| `--list` | List available video devices in table format |
| `--json` | List available video devices in JSON format |
| `--help` | Show help message |

### Device Specification

Devices can be specified in two ways:

- **Device path**: `/dev/video0`, `/dev/video2`, etc.
- **Serial number**: `1234ABCD`, `5678EFGH`, etc.

Using serial numbers is recommended as they remain consistent across reboots and device reconnections.

### Examples

```bash
# List all video devices in table format
./v4l-saver.sh --list

# List all video devices in JSON format
./v4l-saver.sh --json

# Save controls for all usable devices
./v4l-saver.sh --save

# Save controls for a specific device by path
./v4l-saver.sh --save /dev/video0

# Save controls for a specific device by serial number
./v4l-saver.sh --save 1234ABCD

# Load controls for all devices
./v4l-saver.sh --load

# Load controls for a specific device by serial number
./v4l-saver.sh --load 1234ABCD

# Load controls for a specific device by path
./v4l-saver.sh --load /dev/video0
```

## Output Examples

### Device Listing (Table Format)

```
Device       SN       Vendor          Card Type                           Format Info
------       --       ------          ---------                           -----------
/dev/video0  1234ABCD Logitech        C922 Pro Stream Webcam              YUYV up to 1920x1080@30fps (+2 more formats)
/dev/video2  5678EFGH Microsoft       Microsoft LifeCam HD-3000           YUYV up to 1280x720@30fps
/dev/video4  ABCD1234 Generic         USB Camera                          [PROBABLY NOT USABLE - no resolutions found]
```

### Device Listing (JSON Format)

```json
{
  "devices": [
    {
      "device": "/dev/video0",
      "serial": "1234ABCD",
      "vendor": "Logitech",
      "card_type": "C922 Pro Stream Webcam",
      "usable": true,
      "formats": [
        {"format": "YUYV", "max_resolution": "1920x1080", "max_fps": 30},
        {"format": "MJPG", "max_resolution": "1920x1080", "max_fps": 30}
      ]
    }
  ]
}
```

## Configuration Files

Configuration files are stored in `${XDG_CONFIG_HOME:-$HOME/.config}/v4l-saver/` and are named using the device serial number (e.g., `1234ABCD.json`).

### Supported Controls

The script manages these common V4L2 controls:

- `brightness` - Image brightness adjustment
- `contrast` - Image contrast adjustment  
- `saturation` - Color saturation level
- `white_balance_automatic` - Automatic white balance on/off
- `gain` - Image gain/amplification
- `power_line_frequency` - Anti-flicker setting (50/60Hz)
- `white_balance_temperature` - Manual white balance temperature
- `sharpness` - Image sharpness adjustment
- `backlight_compensation` - Backlight compensation on/off
- `auto_exposure` - Auto exposure mode
- `exposure_time_absolute` - Manual exposure time
- `exposure_dynamic_framerate` - Dynamic framerate for exposure
- `pan_absolute` - Pan position (PTZ cameras)
- `tilt_absolute` - Tilt position (PTZ cameras)
- `focus_absolute` - Manual focus position
- `focus_automatic_continuous` - Continuous autofocus on/off
- `zoom_absolute` - Zoom level (PTZ cameras)

### Sample Configuration File

```json
{
  "device": "/dev/video0",
  "serial": "1234ABCD",
  "timestamp": "2025-08-17T10:30:00-07:00",
  "card_type": "C922 Pro Stream Webcam",
  "vendor": "usb-046d:085b-12345678",
  "controls": {
    "brightness": {"value": 128, "type": "int"},
    "contrast": {"value": 128, "type": "int"},
    "saturation": {"value": 128, "type": "int"},
    "white_balance_automatic": {"value": 1, "type": "bool"},
    "gain": {"value": 64, "type": "int"}
  }
}
```

## Device Compatibility

- **Usable Devices**: Cameras/devices that support capture formats with resolutions
- **Unusable Devices**: Non-capture devices (e.g., metadata devices, broken devices)

The script automatically filters out unusable devices and focuses on actual cameras that can capture video.

## Troubleshooting

### No devices found
```bash
# Check if any video devices exist
ls /dev/video*

# Check for USB cameras
lsusb | grep -i camera

# Check kernel messages
dmesg | grep -i video
```

### Permission denied
```bash
# Add your user to the video group
sudo usermod -a -G video $USER
# Then log out and back in
```

### Missing dependencies
The script will automatically detect missing dependencies and show installation instructions for your distribution.

## Technical Details

- **Config Directory**: `${XDG_CONFIG_HOME:-$HOME/.config}/v4l-saver/`
- **File Format**: JSON with device metadata and control values
- **Device Identification**: Uses V4L2 device serial numbers for reliable matching
- **Vendor Detection**: Extracts vendor information from `/dev/v4l/by-id` symlinks when available
- **Format Detection**: Analyzes supported capture formats and resolutions
- **Error Handling**: Comprehensive error checking with informative messages

## Requirements

- **bash** (POSIX-compatible shell scripting)
- **v4l2-ctl** from v4l-utils package (main requirement)
- Standard UNIX utilities: find, grep, awk, sed, sort, cut, printf, date

## License

This script is provided as-is. Feel free to modify and distribute according to your needs.
