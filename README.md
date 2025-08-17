# v4l-saver

A simple bash utility to save and restore V4L2 (Video4Linux2) device controls using `v4l2-ctl`. Designed for Linux systems (Debian, Arch, etc.), no root required—just access to video devices.

## Features
- Save all controls for each `/dev/video*` device to user config directory
- Restore controls for each device from saved files
- List available video devices
- Simple command-line flags

## Requirements
- Bash
- [v4l2-ctl](https://manpages.debian.org/testing/v4l-utils/v4l2-ctl.1.en.html) (from `v4l-utils`)

## Installation
Clone this repository and make the script executable:

```sh
git clone <repo-url>
cd v4l-saver
chmod +x v4l-saver.sh
```

## Usage

```sh
./v4l-saver.sh --save   # Save controls for all video devices
./v4l-saver.sh --load   # Load controls for all video devices
./v4l-saver.sh --list   # List available video devices
./v4l-saver.sh --help   # Show help message
```

Settings are saved per device in `${XDG_CONFIG_HOME:-$HOME/.config}/v4l-saver/`.

## Notes
- No root required, but you must have permission to access `/dev/video*` devices.
- Only standard V4L2 controls are saved/restored. Custom controls may require manual handling.
- Tested on Debian and Arch Linux.

## License
MIT (add your license details here)
