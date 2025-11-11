# Ableton Live Ubuntu Setup

A comprehensive installation script for running Ableton Live on Ubuntu Linux with professional audio performance and low-latency configuration.

## Overview

This script provides a complete solution for installing and configuring Ableton Live on Ubuntu using Wine, including:

- **WineHQ Installation**: Latest Wine staging for optimal Windows application compatibility
- **WineASIO Setup**: Professional low-latency audio driver for Windows applications
- **JACK Audio**: Professional audio server for real-time audio processing
- **MIDI Integration**: Full MIDI support with ALSA-to-JACK bridging
- **Desktop Integration**: Application menu shortcuts and icons
- **Performance Optimization**: System tuning for audio production

## Features

### Core Installation

- ✅ Automated WineHQ repository setup and installation
- ✅ WineASIO compilation and installation from source
- ✅ Ableton Live installer download and installation
- ✅ Windows runtime libraries (Visual C++, DirectX, fonts)
- ✅ Professional audio driver configuration

### Audio System

- ✅ JACK Audio Connection Kit for low-latency audio
- ✅ WineASIO driver for Windows applications
- ✅ ALSA to JACK MIDI bridge (a2jmidid)
- ✅ Configurable sample rates and buffer sizes
- ✅ PipeWire compatibility mode (experimental)

### Additional Tools

- ✅ Yabridge for VST plugin support
- ✅ Desktop application integration
- ✅ System service management (optional)
- ✅ Audio patchbay templates
- ✅ Comprehensive logging and error handling

## Quick Start

### 1. One‑liner (`curl | bash`)

```bash
# Installs latest Ableton Live trial (license inside of Ableton to Unlock the Full Version - the .exe binary is the same between Live Trial and Live Full)

curl -fsSL https://raw.githubusercontent.com/BenevolenceMessiah/ableton_setup/main/ableton_setup.sh   | bash -- --no-features --no-timeout
```

### -Or- Point to Your local .exe file for the Full version

```bash
# installs Ableton Live from a local file

curl -fsSL https://raw.githubusercontent.com/BenevolenceMessiah/ableton_setup/main/ableton_setup.sh   | bash -- --no-features --installer /path/to/ableton_installer.zip
```

### -Or- Clone, Download, and Run

```bash
# Git Clone the repo
git clone https://github.com/BenevolenceMessiah/ableton_setup.git
# Change directory to the cloned directory
cd ableton_setup
# Make the script executable
chmod +x ableton_setup.sh
# Run with default settings (installs Ableton Live trial)
./ableton_setup.sh
```

```bash
# Or install from your own Ableton installer
./ableton_setup.sh --installer /path/to/ableton_installer.zip
```

### 3. Complete Installation

The script will:

1. Install WineHQ and required dependencies
2. Build and install WineASIO from source
3. Download/install Ableton Live
4. Configure audio settings
5. Create desktop integration

### 4. Configure Audio in Ableton

After installation:

1. Launch Ableton Live from your applications menu
2. Go to **Preferences > Audio**
3. Select **WINEASIO** as the driver
4. Set your preferred sample rate and buffer size
5. Test audio playback

## Installation Options

### Minimal Installation

```bash
./ableton_setup.sh --no-features
```

Installs only Ableton Live and WineASIO (no additional tools).

### Custom Audio Settings

```bash
./ableton_setup.sh --sample-rate 44100 --buffer-size 256
```

### Professional Setup with All Features

```bash
./ableton_setup.sh --systemd --tweak-pipewire --patchbay
```

### Using Your Own Installer

```bash
./ableton_setup.sh --installer /path/to/ableton_live_suite_12.zip
```

## System Requirements

### Minimum Requirements

- **OS**: Ubuntu 20.04 LTS or newer
- **CPU**: 5th generation Intel Core i5 or AMD Ryzen (AVX2 support)
- **RAM**: 8 GB minimum, 16 GB recommended
- **Storage**: 5 GB for basic installation, up to 76 GB for additional content
- **Audio**: ASIO compatible audio interface recommended

### Recommended Setup

- **OS**: Ubuntu 22.04 LTS or Ubuntu Studio
- **CPU**: Intel Core i7 or AMD Ryzen 7
- **RAM**: 16 GB or more
- **Audio**: Professional audio interface with JACK support
- **Kernel**: Low-latency or real-time kernel for best performance

## Audio Configuration

### Sample Rates

- **44.1 kHz**: Standard CD quality
- **48 kHz**: Professional video standard (default)
- **88.2 kHz**: High resolution
- **96 kHz**: Professional high resolution

### Buffer Sizes

- **128 samples**: Very low latency (~3ms at 48kHz)
- **256 samples**: Low latency (~5ms at 48kHz)
- **512 samples**: Balanced performance (~11ms at 48kHz) (default)
- **1024 samples**: Stable performance (~21ms at 48kHz)

### Audio Interfaces

The script automatically detects available audio interfaces. To specify a particular interface:

```bash
./ableton_setup.sh --audio-interface "Focusrite Scarlett 2i2"
```

## Troubleshooting

### WineASIO Not Appearing in Ableton

1. **Manual Registration**:

   ```bash
   WINEPREFIX="$HOME/.wine-ableton" wine regsvr32 C:\windows\system32\wineasio.dll
   ```

2. **Check WineASIO Installation**:

   ```bash
   # Check if files exist
   ls -la /usr/local/lib/wine/x86_64-windows/wineasio.dll
   ls -la /usr/local/lib64/wine/wineasio64.dll.so
   ```

3. **Restart Wine Services**:

   ```bash
   wineserver -k
   ```

### Audio Crackling or Dropouts

1. **Increase Buffer Size**: Try 1024 or 2048 samples
2. **Use JACK2 Instead of PipeWire**:

   ```bash
   sudo apt install jackd2
   ```

3. **Disable CPU Frequency Scaling**:

   ```bash
   sudo cpupower frequency-set -g performance
   ```

### MIDI Issues

1. **Start MIDI Bridge**:

   ```bash
   a2jmidid -e
   ```

2. **Check MIDI Connections in QJackCtl**:
   - Open QJackCtl
   - Go to Connections tab
   - Check ALSA MIDI tab for available devices

### PipeWire Compatibility

Ubuntu 24.04+ uses PipeWire by default, which may have compatibility issues:

1. **Use JACK2 Instead**:

   ```bash
   sudo apt install jackd2 qjackctl
   ```

2. **Apply PipeWire Tweaks**:

   ```bash
   ./ableton_setup.sh --tweak-pipewire
   ```

### Performance Issues

1. **Use Low-Latency Kernel**:

   ```bash
   sudo apt install linux-lowlatency
   ```

2. **Optimize System for Audio**:

   ```bash
   # Add user to audio group
   sudo usermod -a -G audio $USER
   
   # Configure real-time priorities
   echo "@audio - rtprio 95" | sudo tee -a /etc/security/limits.conf
   echo "@audio - memlock unlimited" | sudo tee -a /etc/security/limits.conf
   ```

## Advanced Configuration

### Custom Wine Prefix

```bash
export PREFIX="$HOME/custom-wine-prefix"
./ableton_setup.sh
```

### Multiple Ableton Versions

Create separate Wine prefixes for different Ableton versions:

```bash
# Install Ableton Live 11
PREFIX="$HOME/.wine-ableton11" ./ableton_setup.sh --installer ableton11.zip

# Install Ableton Live 12
PREFIX="$HOME/.wine-ableton12" ./ableton_setup.sh --installer ableton12.zip
```

### VST Plugin Support

Yabridge is automatically installed for VST plugin support:

1. Install Windows VST plugins to your Wine prefix
2. Run: `yabridgectl sync`
3. VST plugins will be available in Ableton Live

## File Structure

After installation:

```treefile
~/.wine-ableton/              # Wine prefix for Ableton
├── drive_c/
│   ├── ProgramData/
│   │   └── Ableton/         # Ableton Live installation
│   └── windows/
│       └── system32/
│           └── wineasio.dll # WineASIO driver
└── system.reg               # Wine registry

~/.local/share/applications/ # Desktop entries
└── ableton.desktop

~/.local/share/icons/        # Application icons
└── ableton.png
```

## Uninstallation

To completely remove Ableton Live and all associated components:

```bash
./ableton_setup.sh --uninstall
```

This will:

- Remove the Wine prefix
- Uninstall WineASIO
- Remove desktop entries
- Clean up configuration files

## Support and Contributing

### Issues and Bug Reports

If you encounter issues:

1. Check the installation log: `~/ableton_setup_*.log`
2. Verify system requirements
3. Check [Wine AppDB](https://appdb.winehq.org/) for Ableton Live compatibility
4. Search existing [WineASIO issues](https://github.com/wineasio/wineasio/issues)

### Testing

The script has been tested on:

- Ubuntu 20.04 LTS
- Ubuntu 22.04 LTS
- Ubuntu Studio 22.04
- Ubuntu 24.04 (with JACK2)

### Contributing

Contributions welcome! Please:

1. Test changes on multiple Ubuntu versions
2. Update documentation
3. Follow the existing code style
4. Submit pull requests with detailed descriptions

## License

This script is provided as-is for educational and personal use. Ableton Live is commercial software that requires a valid license. Wine and WineASIO are open-source projects.

## Acknowledgments

- [Wine Project](https://www.winehq.org/) for Windows compatibility layer
- [WineASIO Project](https://github.com/wineasio/wineasio) for professional audio support
- [JACK Audio Connection Kit](https://jackaudio.org/) for low-latency audio
- [Ableton](https://www.ableton.com/) for creating Live

## Disclaimer

This script is not affiliated with or endorsed by Ableton. Users must have a valid license for Ableton Live. The script is provided for convenience in installing Ableton Live on Linux systems for users who own legitimate licenses.
