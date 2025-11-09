#!/usr/bin/env bash
# ableton_setup.sh – Ableton Live + Wine + Professional Audio Setup for Ubuntu

set -Eeuo pipefail

# Error handling with line number
trap 'log "ERROR: Command failed on line $LINENO"' ERR

# Logging functions
log() {
    echo -e "\e[36m[INFO]\e[0m $*"
    echo "[INFO] $*" >> "$LOG"
}

warn() {
    echo -e "\e[33m[WARNING]\e[0m $*"
    echo "[WARNING] $*" >> "$LOG"
}

die() {
    echo -e "\e[31m[ERROR]\e[0m $*" >&2
    echo "[ERROR] $*" >> "$LOG"
    exit 1
}

########## 0 – Globals & defaults ################################
LOG="$HOME/ableton_setup_$(date +%F_%H-%M-%S).log"
export DEBIAN_FRONTEND=noninteractive

# Ableton Live installer URL (trial version - user can provide their own)
ABLETON_TRIAL_URL="https://cdn-downloads.ableton.com/channels/12.2.6/ableton_live_trial_12.2.6_64.zip"
ABLETON_LATEST_VERSION="12.2.6"
: "${INSTALLER_PATH:=${ABLETON_TRIAL_URL}}"
: "${WINE_BRANCH:=staging}"

# Installation paths and versions
PREFIX="${PREFIX:-$HOME/.wine-ableton}"
WINEASIO_VERSION="v1.3.0"
ABLETON_VERSION="12"

# Feature toggles (all enabled by default)
ENABLE_YABRIDGE=1
ENABLE_LOOPMIDI=1
ENABLE_SYSTEMD=0
TWEAK_PIPEWIRE=0
DO_UNINSTALL=0
MINIMAL_MODE=0
PATCHBAY=0

# Audio configuration
AUDIO_SAMPLE_RATE=48000
AUDIO_BUFFER_SIZE=512
AUDIO_INTERFACE=""

# Timeouts and environment
export CURL_TIMEOUT=60
export WINE_TIMEOUT=30
export WINE_DISABLE_MEMORY_MANAGER=1
export WINE_LARGE_ADDRESS_AWARE=1

# Show help
show_help() {
    cat <<'EOF'
Usage: ./ableton_setup.sh [OPTIONS]

Ableton Live Linux Setup - One-command installer for Ableton Live with Wine,
professional audio setup, and low-latency configuration.

OPTIONS:
  --installer <file|URL>    Path or URL to Ableton Live installer
  --wine <stable|staging>   Choose Wine branch (default: staging)
  --sample-rate <rate>      Audio sample rate (default: 48000)
  --buffer-size <size>      Audio buffer size (default: 512)
  --audio-interface <name>  Specific audio interface name
  --no-yabridge            Skip Yabridge installation
  --no-loopmidi            Skip a2jmidid bridge installation
  --no-features            MINIMAL MODE: Only Ableton + WineASIO
  --systemd                Create user-level systemd services
  --tweak-pipewire         Apply low-latency PipeWire preset
  --patchbay               Write QJackCtl/Carla patchbay XML
  --uninstall              Remove all installed components
  --help, -h               Show this help

ENVIRONMENT VARIABLES:
  INSTALLER_PATH           Override installer source
  WINE_BRANCH              Override Wine branch
  PREFIX                   Override Wine prefix location

EXAMPLES:
  # Minimal installation (just Ableton + WineASIO)
  ./ableton_setup.sh --no-features
  
  # Install with custom audio settings
  ./ableton_setup.sh --sample-rate 44100 --buffer-size 256
  
  # Install from local installer
  ./ableton_setup.sh --installer /path/to/ableton_installer.zip

WARNING: Ubuntu 24.04+ uses PipeWire by default, which has known compatibility
         issues with WineASIO. For best results:
         1. Use JACK2: sudo apt install jackd2 qjackctl
         2. Or run with --tweak-pipewire (experimental)

EOF
    exit 0
}

########## 1 – Flag parser ###############################################
while [[ $# -gt 0 ]]; do
    case $1 in
        --installer)
            INSTALLER_PATH="$2"
            shift 2
            ;;
        --wine)
            WINE_BRANCH="$2"
            shift 2
            ;;
        --sample-rate)
            AUDIO_SAMPLE_RATE="$2"
            shift 2
            ;;
        --buffer-size)
            AUDIO_BUFFER_SIZE="$2"
            shift 2
            ;;
        --audio-interface)
            AUDIO_INTERFACE="$2"
            shift 2
            ;;
        --no-yabridge)
            ENABLE_YABRIDGE=0
            shift
            ;;
        --no-loopmidi)
            ENABLE_LOOPMIDI=0
            shift
            ;;
        --no-features)
            MINIMAL_MODE=1
            ENABLE_YABRIDGE=0
            ENABLE_LOOPMIDI=0
            ENABLE_SYSTEMD=0
            TWEAK_PIPEWIRE=0
            PATCHBAY=0
            shift
            ;;
        --systemd)
            ENABLE_SYSTEMD=1
            shift
            ;;
        --tweak-pipewire)
            TWEAK_PIPEWIRE=1
            warn "PipeWire mode enabled - WineASIO compatibility issues are possible"
            shift
            ;;
        --patchbay)
            PATCHBAY=1
            shift
            ;;
        --uninstall)
            DO_UNINSTALL=1
            shift
            ;;
        --help|-h)
            show_help
            ;;
        *)
            die "Unknown flag: $1"
            ;;
    esac
done

########## 2 – Uninstall #################################################
if [[ $DO_UNINSTALL == 1 ]]; then
    log "=== UNINSTALLING ABLETON LIVE SETUP ==="
    
    # Kill any running Wine processes first
    log "Stopping Wine processes..."
    wineserver -k 2>/dev/null || true
    pkill -f "wine.*ableton" 2>/dev/null || true
    sleep 2
    
    # Stop and remove user services
    log "Removing systemd services..."
    for service in a2jmidid; do
        systemctl --user disable --now "${service}.service" 2>/dev/null || true
        rm -f ~/.config/systemd/user/"${service}.service"
    done
    systemctl --user daemon-reload
    
    # Remove packages
    log "Removing packages..."
    sudo apt -y remove winehq-* wine-staging wine-stable winetricks 2>/dev/null || true
    sudo apt -y remove a2jmidid 2>/dev/null || true
    sudo apt -y autoremove 2>/dev/null || true
    
    # Remove WineASIO
    log "Removing WineASIO..."
    sudo rm -f /usr/local/lib/wine/x86_64-windows/wineasio.dll
    sudo rm -f /usr/local/lib64/wine/wineasio64.dll.so
    sudo rm -f /usr/local/bin/wineasio-register
    
    # Remove Ableton data
    log "Removing Ableton Live data..."
    rm -rf "$PREFIX"
    rm -rf ~/.local/{bin,share}/ableton-*
    rm -rf ~/.local/share/yabridge
    rm -f ~/.local/bin/yabridge
    rm -f ~/.local/bin/yabridgectl
    
    # Remove desktop files
    rm -f ~/.local/share/applications/ableton.desktop
    rm -f ~/.local/share/icons/ableton.png
    
    # Remove PipeWire tweaks
    rm -f ~/.config/pipewire/pipewire.conf.d/90-lowlatency.conf
    
    # Remove patchbay
    rm -f ~/.config/rncbc.org/QjackCtl/patches/ableton.xml
    
    log "Uninstall complete!"
    exit 0
fi

########## 3 – System update & Wine repo #################################
log "=== STEP 1: Updating system and adding WineHQ repository ==="
sudo apt update && sudo apt upgrade -y

# Enable i386 architecture
sudo dpkg --add-architecture i386 2>/dev/null || true

# Add WineHQ key
sudo mkdir -p /etc/apt/keyrings
wget -qO /tmp/winehq.key https://dl.winehq.org/wine-builds/winehq.key   
sudo install -m644 /tmp/winehq.key /etc/apt/keyrings/

# Add repository
UBUNTU_CODENAME=$(lsb_release -cs)
cat <<EOF | sudo tee /etc/apt/sources.list.d/winehq.sources
Types: deb
URIs: https://dl.winehq.org/wine-builds/ubuntu   
Suites: $UBUNTU_CODENAME
Components: main
Architectures: amd64 i386
Signed-By: /etc/apt/keyrings/winehq.key
EOF

sudo apt update

########## 4 – Install packages ##########################################
log "=== STEP 2: Installing packages ==="

# Install winehq-staging first to ensure we get the right version
sudo apt install -y --install-recommends "winehq-$WINE_BRANCH" winetricks

# Install dependencies including Wine development headers
sudo apt install -y \
    pipewire-jack \
    qjackctl \
    a2jmidid \
    curl \
    git \
    jq \
    imagemagick \
    build-essential \
    libasound2-dev \
    libjack-jackd2-dev \
    libwine-dev \
    unzip

# For minimal mode, stop here with core packages
if [[ $MINIMAL_MODE == 1 ]]; then
    log "MINIMAL MODE: Skipping optional audio packages..."
else
    # Additional audio tools for full installation
    sudo apt install -y \
        jackd2 \
        carla \
        catia \
        ladish
fi

########## 5 – Build WineASIO ############################################
log "=== STEP 3: Building WineASIO $WINEASIO_VERSION ==="
warn "WineASIO $WINEASIO_VERSION will be built from source using Makefiles"

# Create build directory
WINEASIO_BUILD_DIR=$(mktemp -d)
cd "$WINEASIO_BUILD_DIR" || die "Failed to create build directory"

# Clone repository
log "Cloning WineASIO repository..."
if ! git clone https://github.com/wineasio/wineasio.git .; then
    cd "$HOME"
    rm -rf "$WINEASIO_BUILD_DIR"
    die "Failed to clone WineASIO repository"
fi

# Check out version
log "Checking out WineASIO $WINEASIO_VERSION..."
if ! git checkout "$WINEASIO_VERSION" 2>/dev/null; then
    warn "Tag $WINEASIO_VERSION not found, building from master"
fi

# Verify Makefile exists
if [[ ! -f "Makefile" ]]; then
    cd "$HOME"
    rm -rf "$WINEASIO_BUILD_DIR"
    die "Makefile not found! Repository structure may have changed."
fi

# Find and verify Wine headers location
log "Locating Wine headers..."
WINE_INCLUDE_PATH=""

# Check common locations for objbase.h
for path in \
    "/usr/include/wine/windows" \
    "/usr/include/wine/wine/windows" \
    "/usr/include/wine-development/wine/windows" \
    "/opt/wine-stable/include/wine/windows" \
    "/opt/wine-staging/include/wine/windows"; do
    if [[ -f "$path/objbase.h" ]]; then
        WINE_INCLUDE_PATH="$path"
        log "✓ Found Wine headers at: $WINE_INCLUDE_PATH"
        break
    fi
done

if [[ -z "$WINE_INCLUDE_PATH" ]]; then
    warn "Could not locate objbase.h in standard paths"
    warn "Searching entire system for objbase.h..."
    WINE_INCLUDE_PATH=$(find /usr/include /opt -name "objbase.h" 2>/dev/null | head -1 | xargs dirname)
    
    if [[ -n "$WINE_INCLUDE_PATH" ]]; then
        log "✓ Found objbase.h at: $WINE_INCLUDE_PATH"
    else
        cd "$HOME"
        rm -rf "$WINEASIO_BUILD_DIR"
        die "objbase.h not found! Please ensure libwine-dev is installed correctly."
    fi
fi

# Build with explicit include path and better error handling
log "Building WineASIO 64-bit..."
if [[ -n "$WINE_INCLUDE_PATH" && "$WINE_INCLUDE_PATH" != "/usr/include/wine/windows" ]]; then
    # Add the correct include path to the build
    log "Adding include path: $WINE_INCLUDE_PATH"
    export CFLAGS="-I$WINE_INCLUDE_PATH"
fi

# Use proper make command with timeout
if ! timeout "$WINE_TIMEOUT" make 64 2>/dev/null; then
    # Try alternative make command
    log "Trying alternative build method..."
    if ! timeout "$WINE_TIMEOUT" make build ARCH=x86_64 M=64; then
        cd "$HOME"
        rm -rf "$WINEASIO_BUILD_DIR"
        die "Build failed"
    fi
fi

# Manually install files (no make install target)
log "Installing WineASIO files..."

# Create directories
sudo mkdir -p /usr/local/lib/wine/x86_64-windows/
sudo mkdir -p /usr/local/lib64/wine/

# Install DLL
if [[ -f "build64/wineasio64.dll" ]]; then
    sudo cp build64/wineasio64.dll /usr/local/lib/wine/x86_64-windows/wineasio.dll
    log "✓ Installed 64-bit DLL"
else
    warn "✗ 64-bit DLL not found at build64/wineasio64.dll"
fi

# Install .so
if [[ -f "build64/wineasio64.dll.so" ]]; then
    sudo cp build64/wineasio64.dll.so /usr/local/lib64/wine/
    log "✓ Installed 64-bit .so"
else
    warn "✗ 64-bit .so not found at build64/wineasio64.dll.so"
fi

# Install wineasio-register script if it exists
if [[ -f "wineasio-register" ]]; then
    sudo cp wineasio-register /usr/local/bin/
    sudo chmod +x /usr/local/bin/wineasio-register
    log "✓ Installed wineasio-register script"
fi

# Cleanup
cd "$HOME"
rm -rf "$WINEASIO_BUILD_DIR"

########## 6 – Setup Wine prefix #########################################
log "=== STEP 4: Setting up Wine prefix ==="
export WINEARCH=win64
export WINEPREFIX="$PREFIX"

# Kill any existing Wine processes before creating prefix
wineserver -k 2>/dev/null || true
pkill -f "wineserver" 2>/dev/null || true
sleep 2

if [[ ! -d "$PREFIX" ]]; then
    log "Creating new Wine prefix..."
    # Use wineboot with timeout and wait for completion
    timeout "$WINE_TIMEOUT" wineboot --init || warn "wineboot timed out or failed"
    
    # Wait for prefix to be ready with timeout
    for i in {1..60}; do
        if [[ -f "$PREFIX/system.reg" ]]; then
            log "✓ Wine prefix created successfully"
            break
        fi
        sleep 1
    done
    
    if [[ ! -f "$PREFIX/system.reg" ]]; then
        warn "Wine prefix may not be fully initialized"
    fi
fi

# Configure Wine - use win10 for better compatibility
winecfg -v win10 2>/dev/null || true

# Disable Wine crash dialogs for better stability
log "Disabling Wine crash dialogs..."
cat > /tmp/disable_wine_dlg.reg <<'EOF'
REGEDIT4

[HKEY_CURRENT_USER\Software\Wine\WineDbg]
"ShowCrashDialog"=dword:00000000
EOF
wine regedit /tmp/disable_wine_dlg.reg 2>/dev/null || true
rm -f /tmp/disable_wine_dlg.reg

########## 7 – Install Windows libraries #################################
log "=== STEP 5: Installing Windows runtime libraries ==="

# Update winetricks first to minimize SHA256 mismatches
log "Updating winetricks..."
sudo winetricks --self-update 2>/dev/null || warn "Failed to update winetricks"

# Use --force to bypass SHA256 mismatches for known-good files
WINETRICKS_OPTS="-q --force"
WINEPREFIX="$PREFIX" winetricks $WINETRICKS_OPTS vcrun2019 vcrun2022 corefonts dxvk

########## 8 – Register WineASIO in Wine prefix ##########################
log "=== STEP 6: Registering WineASIO ==="

# Copy WineASIO to the Wine prefix's system32 directory first
# This is REQUIRED for regsvr32 to find the DLL
WINEASIO_SYSTEM_DLL="$PREFIX/drive_c/windows/system32/wineasio.dll"
WINEASIO_SYSTEM_DLL_SO="$PREFIX/drive_c/windows/system32/wineasio.dll.so"

log "Copying WineASIO to Wine prefix..."
if [[ -f "/usr/local/lib/wine/x86_64-windows/wineasio.dll" ]]; then
    cp "/usr/local/lib/wine/x86_64-windows/wineasio.dll" "$WINEASIO_SYSTEM_DLL"
    log "✓ Copied DLL to prefix"
else
    die "Source WineASIO DLL not found!"
fi

if [[ -f "/usr/local/lib64/wine/wineasio64.dll.so" ]]; then
    cp "/usr/local/lib64/wine/wineasio64.dll.so" "$WINEASIO_SYSTEM_DLL_SO"
    log "✓ Copied .so to prefix"
else
    warn "Source WineASIO .so not found, continuing anyway..."
fi

# Use the wineasio-register script properly
log "Registering WineASIO in Wine prefix..."
WINEPREFIX="$PREFIX" wine regsvr32 "C:\windows\system32\wineasio.dll" 2>/dev/null || {
    warn "Initial registration failed, trying alternative method..."
    WINEPREFIX="$PREFIX" wine64 regsvr32 "C:\windows\system32\wineasio.dll" 2>/dev/null || true
}

# Alternative registration method using wineasio-register if available
if command -v wineasio-register &>/dev/null; then
    log "Using wineasio-register script..."
    WINEPREFIX="$PREFIX" WINEDLLPATH="$PREFIX/drive_c/windows/system32" wineasio-register 2>/dev/null || true
fi

# Verify registration
log "Verifying WineASIO registration..."
if WINEPREFIX="$PREFIX" wine reg query "HKCU\Software\Wine\Drivers" /v Audio 2>/dev/null | grep -q "asio"; then
    log "✓ WineASIO appears to be registered in Wine"
else
    warn "✗ WineASIO may not be registered properly in Wine"
fi

########## 9 – Install Ableton Live ######################################
log "=== STEP 7: Installing Ableton Live ==="
INSTALLER_FILE="/tmp/ableton_installer.zip"
EXTRACTED_DIR="/tmp/ableton_installer"

# Better download handling with retry logic
if [[ "$INSTALLER_PATH" =~ ^https?:// ]]; then
    log "Downloading Ableton Live installer from: $INSTALLER_PATH"
    
    # Check internet connectivity first
    if ! curl -fsSL --max-time 10 https://www.ableton.com > /dev/null 2>&1; then
        warn "Cannot reach Ableton website. Please check your internet connection."
        warn "You can manually download the installer and use --installer /path/to/file"
    fi
    
    # Download with retry logic
    for i in {1..3}; do
        if curl -fsSL --connect-timeout 30 --max-time 600 "$INSTALLER_PATH" -o "$INSTALLER_FILE"; then
            # Verify file is not empty
            if [[ -s "$INSTALLER_FILE" ]]; then
                log "✓ Download successful"
                break
            fi
        fi
        
        warn "Download attempt $i failed, retrying..."
        sleep 5
    done
    
    if [[ ! -f "$INSTALLER_FILE" || ! -s "$INSTALLER_FILE" ]]; then
        die "Failed to download Ableton Live installer after 3 attempts. \
             \nPlease download manually from: https://www.ableton.com/en/trial/ \
             \nThen run: ./$(basename "$0") --installer /path/to/downloaded/installer.zip"
    fi
else
    if [[ -f "$INSTALLER_PATH" ]]; then
        INSTALLER_FILE="$INSTALLER_PATH"
        log "Using local installer: $INSTALLER_FILE"
    else
        die "Installer not found: $INSTALLER_PATH"
    fi
fi

# Extract the installer
log "Extracting Ableton Live installer..."
mkdir -p "$EXTRACTED_DIR"
if ! unzip -q "$INSTALLER_FILE" -d "$EXTRACTED_DIR"; then
    die "Failed to extract Ableton Live installer"
fi

# Find the installer executable
INSTALLER_EXE=""
for file in "$EXTRACTED_DIR"/*.exe; do
    if [[ -f "$file" ]] && [[ "$file" =~ [Ii]nstaller ]]; then
        INSTALLER_EXE="$file"
        break
    fi
done

if [[ -z "$INSTALLER_EXE" ]]; then
    die "Could not find installer executable in extracted files"
fi

log "Found installer: $INSTALLER_EXE"

# Run installer in background and wait for it
WINEPREFIX="$PREFIX" wine "$INSTALLER_EXE" &
INSTALLER_PID=$!

# Wait for installer to start
sleep 10

# Monitor the process and show progress
log "Waiting for installation to complete..."
log "If the installer GUI doesn't appear, check for error messages above."
log "Please complete the installation wizard manually."

# Better wait logic with timeout
for i in {1..180}; do
    if ! ps -p $INSTALLER_PID > /dev/null 2>&1; then
        log "Installer process finished"
        break
    fi
    
    # Check if Ableton is installed
    if [[ -f "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" ]]; then
        log "✓ Ableton Live installation detected"
        break
    fi
    
    sleep 10
done

# Kill installer if still running after timeout
if ps -p $INSTALLER_PID > /dev/null 2>&1; then
    warn "Installer is still running after 30 minutes. Killing it..."
    kill $INSTALLER_PID 2>/dev/null || true
    sleep 5
    kill -9 $INSTALLER_PID 2>/dev/null || true
fi

########## 10 – Desktop integration ######################################
log "=== STEP 8: Creating desktop integration ==="
ICON_DIR="$HOME/.local/share/icons"
mkdir -p "$ICON_DIR"

# Try multiple paths for Ableton icon
ABLETON_ICON_FOUND=false
ABLETON_EXE_PATH="$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe"

for icon_path in \
    "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" \
    "$PREFIX/drive_c/Program Files/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe"; do
    if [[ -f "$icon_path" ]]; then
        log "Found Ableton Live executable at: $icon_path"
        # Extract icon from executable (if possible)
        if command -v wrestool &>/dev/null; then
            wrestool -x -t 14 "$icon_path" | convert - -resize 512x512 "$ICON_DIR/ableton.png" 2>/dev/null && ABLETON_ICON_FOUND=true
        fi
        break
    fi
done

if [[ "$ABLETON_ICON_FOUND" != "true" ]]; then
    warn "Could not find Ableton Live icon, using generic icon"
    # Create a simple placeholder icon
    convert -size 512x512 xc:blue -fill white -pointsize 48 -gravity center -annotate 0 "Ableton" "$ICON_DIR/ableton.png" 2>/dev/null || true
fi

# Create desktop entry
DESKTOP_DIR="$HOME/.local/share/applications"
mkdir -p "$DESKTOP_DIR"
cat > "$DESKTOP_DIR/ableton.desktop" <<EOF
[Desktop Entry]
Name=Ableton Live $ABLETON_VERSION
Exec=env WINEPREFIX="$PREFIX" wine "C:\\ProgramData\\Ableton\\Live $ABLETON_VERSION Suite\\Program\\Ableton Live $ABLETON_VERSION Suite.exe"
Icon=ableton
Type=Application
Categories=AudioVideo;Audio;Music;
StartupNotify=true
Terminal=false
StartupWMClass=ableton live
EOF

update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

# Skip optional features in minimal mode
if [[ $MINIMAL_MODE == 1 ]]; then
    log "MINIMAL MODE: Skipping optional post-installation steps..."
    log "Ableton Live installation complete!"
    log "Next steps: Configure audio settings in Ableton Live to use WineASIO"
    exit 0
fi

########## 11 – Install Yabridge #########################################
if [[ $ENABLE_YABRIDGE == 1 ]]; then
    log "=== STEP 9: Installing Yabridge ==="
    
    YABRIDGE_INFO=$(curl -s https://api.github.com/repos/robbert-vdh/yabridge/releases/latest  )
    YABRIDGE_URL=$(echo "$YABRIDGE_INFO" | jq -r '.assets[] | select(.name | test("tar\\.gz$")) | .browser_download_url' | head -1)
    
    if [[ -n "$YABRIDGE_URL" && "$YABRIDGE_URL" != "null" ]]; then
        YABRIDGE_TMP=$(mktemp -d)
        curl -fsSL "$YABRIDGE_URL" -o "$YABRIDGE_TMP/yabridge.tar.gz"
        tar -xzf "$YABRIDGE_TMP/yabridge.tar.gz" -C "$YABRIDGE_TMP"
        
        mkdir -p ~/.local/bin
        cp "$YABRIDGE_TMP"/yabridge-*/{yabridge,yabridgectl} ~/.local/bin/
        chmod +x ~/.local/bin/{yabridge,yabridgectl}
        
        rm -rf "$YABRIDGE_TMP"
        
        # Setup and sync
        yabridgectl add "$PREFIX"
        yabridgectl sync
        
        log "Yabridge installed and synced"
    else
        warn "Could not find Yabridge download URL"
    fi
fi

########## 12 – Setup a2jmidid ###########################################
if [[ $ENABLE_LOOPMIDI == 1 ]]; then
    log "=== STEP 10: Setting up a2jmidid MIDI bridge ==="
    
    if [[ $ENABLE_SYSTEMD == 1 ]]; then
        mkdir -p ~/.config/systemd/user
        cat > ~/.config/systemd/user/a2jmidid.service <<EOF
[Unit]
Description=ALSA to JACK MIDI bridge
After=pipewire-pulse.service

[Service]
Type=simple
ExecStart=/usr/bin/a2jmidid -e
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
        log "a2jmidid service created"
    fi
fi

########## 13 – PipeWire tweaks ##########################################
if [[ $TWEAK_PIPEWIRE == 1 ]]; then
    log "=== STEP 11: Applying PipeWire low-latency tweaks ==="
    
    warn "PipeWire mode enabled - WineASIO compatibility issues are possible"
    warn "For professional audio work, consider using JACK2 instead"
    
    mkdir -p ~/.config/pipewire/pipewire.conf.d
    cat > ~/.config/pipewire/pipewire.conf.d/90-lowlatency.conf <<EOF
# Low latency configuration for Ableton Live
stream.properties = {
    node.latency = $AUDIO_BUFFER_SIZE/$AUDIO_SAMPLE_RATE
    node.rate = $AUDIO_SAMPLE_RATE
}
EOF
    
    systemctl --user restart pipewire pipewire-pulse 2>/dev/null || true
fi

########## 14 – Patchbay template ########################################
if [[ $PATCHBAY == 1 ]]; then
    log "=== STEP 12: Creating patchbay template ==="
    
    mkdir -p ~/.config/rncbc.org/QjackCtl/patches
    cat > ~/.config/rncbc.org/QjackCtl/patches/ableton.xml <<EOF
<?xml version='1.0' encoding='UTF-8'?>
<jack-patchbay>
  <patch name="Ableton Live Main">
    <output>Ableton Live:out_1</output>
    <input>system:playback_1</input>
  </patch>
  <patch name="Ableton Live Main">
    <output>Ableton Live:out_2</output>
    <input>system:playback_2</input>
  </patch>
</jack-patchbay>
EOF
fi

########## 15 – Setup systemd services ###################################
if [[ $ENABLE_SYSTEMD == 1 ]]; then
    log "=== STEP 13: Setting up systemd services ==="
    
    loginctl enable-linger "$USER"
    
    UDIR=~/.config/systemd/user
    mkdir -p "$UDIR"
    
    # a2jmidid service
    if [[ $ENABLE_LOOPMIDI == 1 ]]; then
        cat > "$UDIR/a2jmidid.service" <<EOF
[Unit]
Description=ALSA to JACK MIDI bridge
After=pipewire-pulse.service

[Service]
Type=simple
ExecStart=/usr/bin/a2jmidid -e
Restart=on-failure
RestartSec=5

[Install]
WantedBy=default.target
EOF
    fi
    
    # Enable and start services
    systemctl --user daemon-reload
    
    for service in a2jmidid; do
        if [[ -f "$UDIR/${service}.service" ]]; then
            log "Enabling service: $service"
            systemctl --user enable --now "${service}.service" 2>/dev/null || warn "Failed to start $service"
        fi
    done
fi

########## 16 – Cleanup Wine processes ###################################
# Kill any remaining wine processes to prevent hanging
log "Cleaning up Wine processes..."
wineserver -k 2>/dev/null || true

########## 17 – Verification #############################################
log "=== STEP 14: Running verification ==="

# Check WineASIO installation
WINEASIO_DLL_INSTALLED=false
WINEASIO_SO_INSTALLED=false

if [[ -f "/usr/local/lib/wine/x86_64-windows/wineasio.dll" ]]; then
    log "✓ WineASIO 64-bit DLL installed"
    WINEASIO_DLL_INSTALLED=true
else
    warn "✗ WineASIO 64-bit DLL NOT found!"
fi

if [[ -f "/usr/local/lib64/wine/wineasio64.dll.so" ]]; then
    log "✓ WineASIO 64-bit .so installed"
    WINEASIO_SO_INSTALLED=true
else
    warn "✗ WineASIO 64-bit .so NOT found!"
fi

# Check WineASIO registration
log "Checking WineASIO registration..."
if WINEPREFIX="$PREFIX" wine reg query "HKCU\Software\Wine\Drivers" /v Audio 2>/dev/null | grep -i asio; then
    log "✓ WineASIO appears to be registered in Wine"
else
    warn "✗ WineASIO may not be registered properly in Wine"
    log "To manually register, run:"
    log "WINEPREFIX=\"$PREFIX\" wine regsvr32 C:\windows\system32\wineasio.dll"
fi

# Check Ableton installation
ABLETON_EXE="$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe"
if [[ -f "$ABLETON_EXE" ]]; then
    log "✓ Ableton Live executable found"
else
    warn "✗ Ableton Live executable not found (may need to complete installation manually)"
fi

########## 18 – Final instructions #######################################
log "=== INSTALLATION COMPLETE ==="
log ""
log "================ IMPORTANT CONFIGURATION STEPS ================"
log ""

if [[ "$WINEASIO_DLL_INSTALLED" == "true" && "$WINEASIO_SO_INSTALLED" == "true" ]]; then
    log "✅ WineASIO installed successfully!"
else
    log "⚠️  WineASIO installation may have issues - see warnings above"
fi

log "1. Ableton Live should now be available in your applications menu"
log "2. Wine prefix location: $PREFIX"
log ""

if [[ $ENABLE_SYSTEMD == 1 ]]; then
    log "3. User services enabled and will start on login"
    log "   Check status: systemctl --user status a2jmidid"
    log ""
fi

log "4. AUDIO SETUP IN ABLETON LIVE (CRITICAL):"
log "   - Open Ableton Live"
log "   - Go to Preferences > Audio"
log "   - Select 'WINEASIO' as the driver"
log "   - Set sample rate to $AUDIO_SAMPLE_RATE Hz"
log "   - Set buffer size to $AUDIO_BUFFER_SIZE samples for low latency"
log "   - If WineASIO doesn't appear, restart Ableton Live or run step 5"
log ""

log "5. If WineASIO doesn't appear in Ableton Live:"
log "   Run: WINEPREFIX=\"$PREFIX\" wine regsvr32 C:\windows\system32\wineasio.dll"
log ""

log "6. For PipeWire users (Ubuntu 24.04+):"
log "   - WineASIO may crash due to PipeWire sandboxing"
log "   - Solution: Use JACK2 instead:"
log "     sudo apt install jackd2"
log "     Start JACK with: qjackctl"
log "     Then start Ableton Live"
log ""

log "7. To run Ableton Live manually:"
log "   WINEPREFIX=\"$PREFIX\" wine \"C:\\ProgramData\\Ableton\\Live $ABLETON_VERSION Suite\\Program\\Ableton Live $ABLETON_VERSION Suite.exe\""
log ""

log "8. Troubleshooting audio crackling:"
log "   - Increase buffer size in Ableton Live Audio Preferences"
log "   - Or use: WINEDEBUG=-all wine ... (to silence debug output)"
log ""

log "9. MIDI Setup:"
log "   - For external MIDI devices, use a2jmidid to bridge ALSA MIDI to JACK"
log "   - Run: a2jmidid -e"
log ""

# Final cleanup to prevent hanging
wineserver -k 2>/dev/null || true

exit 0