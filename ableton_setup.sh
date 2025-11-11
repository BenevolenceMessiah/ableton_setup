#!/usr/bin/env bash
# ableton_setup.sh – Production-ready Ableton Live + WineASIO setup for Ubuntu
# Version: 2.1.1 (Fixed syntax error & duplicate logging)
# Tested on Ubuntu 24.04, Wine 10.x, WineASIO v1.3.0, Ableton Live 12

set -Eeuo pipefail

# --- MODULAR FLAG PARSING (MUST BE FIRST) --------------------------------
parse_flags() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --installer) INSTALLER_PATH="$2"; shift 2 ;;
            --wine) WINE_BRANCH="$2"; shift 2 ;;
            --sample-rate) AUDIO_SAMPLE_RATE="$2"; shift 2 ;;
            --buffer-size) AUDIO_BUFFER_SIZE="$2"; shift 2 ;;
            --audio-interface) AUDIO_INTERFACE="$2"; shift 2 ;;
            --no-yabridge) ENABLE_YABRIDGE=0; shift ;;
            --no-loopmidi) ENABLE_LOOPMIDI=0; shift ;;
            --no-features) MINIMAL_MODE=1; ENABLE_YABRIDGE=0; ENABLE_LOOPMIDI=0; ENABLE_SYSTEMD=0; TWEAK_PIPEWIRE=0; PATCHBAY=0; shift ;;
            --systemd) ENABLE_SYSTEMD=1; shift ;;
            --tweak-pipewire) TWEAK_PIPEWIRE=1; shift ;;
            --patchbay) PATCHBAY=1; shift ;;
            --uninstall) DO_UNINSTALL=1; shift ;;
            --uninstall-full) DO_UNINSTALL_FULL=1; shift ;;
            --force-reinstall) FORCE_REINSTALL=1; shift ;;
            --force-rebuild) FORCE_REBUILD=1; shift ;;
            --use-kxstudio) USE_KXSTUDIO=1; shift ;;
            --no-timeout) NO_TIMEOUT=1; shift ;;
            --verbose|-v) VERBOSE=1; shift ;;
            --help|-h) show_help ;;
            *) die "Unknown flag: $1 (use --help for usage)" ;;
        esac
    done
}

# --- Enhanced Logging & Globals -----------------------------------------
VERBOSE=${VERBOSE:-0}
LOG="$HOME/ableton_setup_$(date +%F_%H-%M-%S).log"
WINE_CMD=${WINE_CMD:-wine}

# FIX: Remove duplicate stdout output - tee already handles both
log() {
    echo -e "\e[36m[INFO]\e[0m $*" | tee -a "$LOG"
}

debug() {
    if [[ $VERBOSE == 1 ]]; then
        echo -e "\e[35m[DEBUG]\e[0m $*" | tee -a "$LOG"
    else
        echo "[DEBUG] $*" >> "$LOG"
    fi
}

warn() {
    echo -e "\e[33m[WARNING]\e[0m $*" | tee -a "$LOG"
}

die() {
    echo -e "\e[31m[ERROR]\e[0m $*" | tee -a "$LOG" >&2
    exit 1
}

# --- System Tuning for Wine ---------------------------------------
tune_system_for_wine() {
    debug "Applying system tuning for Wine..."
    
    if [[ -w /proc/sys/vm/legacy_va_layout ]] && [[ $(cat /proc/sys/vm/legacy_va_layout) != 0 ]]; then
        echo 0 | sudo tee /proc/sys/vm/legacy_va_layout >/dev/null 2>&1 || warn "Could not set legacy_va_layout"
    fi
    
    ulimit -s 8192 2>/dev/null || true
    ulimit -n 4096 2>/dev/null || true
    
    export WINE_DISABLE_MEMORY_MANAGER=1
    export WINE_LARGE_ADDRESS_AWARE=1
}

# --- Help Text -----------------------------------------------------------
show_help() {
    cat <<'EOF'
Usage: ./ableton_setup.sh [OPTIONS]

Ableton Live Linux Setup - Professional audio setup for Ubuntu

OPTIONS:
  --installer <file|URL>    Path or URL to Ableton Live installer
  --wine <stable|staging>   Wine branch (default: staging)
  --sample-rate <rate>      Audio sample rate (default: 48000)
  --buffer-size <size>      Audio buffer size (default: 512)
  --audio-interface <name>  Specific audio interface name
  --no-yabridge            Skip Yabridge installation
  --no-loopmidi            Skip MIDI bridge installation
  --no-features            MINIMAL MODE: Only Ableton + WineASIO
  --systemd                Create user systemd services
  --tweak-pipewire         Apply low-latency PipeWire preset
  --patchbay               Create QJackCtl patchbay template
  --uninstall              Remove installation (keep projects)
  --uninstall-full         Remove installation AND user data
  --force-reinstall        Force reinstall even if version matches
  --force-rebuild          Force rebuild WineASIO from source
  --use-kxstudio           Use KXStudio repositories for WineASIO
  --no-timeout             Disable installer timeout (prompt after GUI)
  --verbose|-v             Show detailed debug output
  --help|-h                Show this help

EXAMPLES:
  ./ableton_setup.sh --no-features --no-timeout
  ./ableton_setup.sh --sample-rate 44100 --buffer-size 256 --systemd
  ./ableton_setup.sh --installer /path/to/ableton.zip --force-reinstall
  ./ableton_setup.sh --verbose --force-rebuild --use-kxstudio
  ./ableton_setup.sh --no-timeout --force-reinstall

WARNING: Ubuntu 24.04+ uses PipeWire by default. For best results:
  1. Use JACK2: sudo apt install jackd2 qjackctl
  2. Or run with --tweak-pipewire (experimental)
  3. Consider --use-kxstudio for easier WineASIO installation
EOF
    exit 0
}

# --- Utility Functions -------------------------------------------------
run_with_timeout() {
    local timeout=$1; shift
    timeout "$timeout" "$@" || {
        local exit_code=$?
        [[ $exit_code == 124 ]] && warn "Command timed out after ${timeout}s: $*" || warn "Command failed with code $exit_code: $*"
        return $exit_code
    }
}

safe_kill() {
    local pid=$1
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        sleep 2
        kill -9 "$pid" 2>/dev/null || true
    fi
}

command_exists() { command -v "$1" &>/dev/null; }

install_packages() {
    local -a packages=("$@")
    for pkg in "${packages[@]}"; do
        debug "Installing: $pkg"
        if sudo apt install -y "$pkg" 2>/dev/null; then
            debug "✓ $pkg installed"
        else
            warn "✗ Failed to install $pkg (may not exist or be optional)"
        fi
    done
}

extract_installer_version() {
    local installer_path="$1"
    [[ "$installer_path" =~ [Aa]bleton[^0-9]*([0-9]+\.[0-9]+(\.[0-9]+)?) ]] && echo "${BASH_REMATCH[1]}" || echo "$ABLETON_LATEST_VERSION"
}

get_wine_info() {
    if [[ -z "${WINE_VERSION:-}" ]]; then
        WINE_VERSION=$(wine --version 2>/dev/null || echo "wine not found")
        WINE_CMD="wine"
        if command -v wine64 &>/dev/null; then
            WINE_CMD="wine64"
            debug "Using wine64 command (preferred for 64-bit)"
        else
            debug "Using wine command (wine64 not found)"
        fi
        debug "Wine: $WINE_VERSION, Command: $WINE_CMD"
    fi
}

wait_for_wine_prefix() {
    local prefix=$1 timeout=${2:-60}
    debug "Waiting for Wine prefix to be ready..."
    for i in $(seq 1 $timeout); do
        [[ -f "$prefix/system.reg" ]] && debug "✓ Wine prefix ready" && return 0
        sleep 1
    done
    warn "Wine prefix may not be fully ready"
    return 1
}

check_url() {
    curl -fsSL --max-time 10 --head "$1" &>/dev/null
}

# --- Constants -----------------------------------------------------------
parse_flags "$@"  # Parse flags immediately

export DEBIAN_FRONTEND=noninteractive
export WINEDEBUG=${WINEDEBUG:--all}
export WINE_TIMEOUT=${WINE_TIMEOUT:-600}
export CURL_TIMEOUT=${CURL_TIMEOUT:-600}

ABLETON_LATEST_VERSION="12.2.6"
ABLETON_TRIAL_URL="https://cdn-downloads.ableton.com/channels/${ABLETON_LATEST_VERSION}/ableton_live_trial_${ABLETON_LATEST_VERSION}_64.zip"

: "${INSTALLER_PATH:=${ABLETON_TRIAL_URL}}"
: "${WINE_BRANCH:=staging}"
: "${PREFIX:=$HOME/.wine-ableton}"

WINEASIO_VERSION="v1.3.0"
ABLETON_VERSION="12"

# Feature flags
ENABLE_YABRIDGE=${ENABLE_YABRIDGE:-1}
ENABLE_LOOPMIDI=${ENABLE_LOOPMIDI:-1}
ENABLE_SYSTEMD=${ENABLE_SYSTEMD:-0}
TWEAK_PIPEWIRE=${TWEAK_PIPEWIRE:-0}
DO_UNINSTALL=${DO_UNINSTALL:-0}
DO_UNINSTALL_FULL=${DO_UNINSTALL_FULL:-0}
FORCE_REINSTALL=${FORCE_REINSTALL:-0}
FORCE_REBUILD=${FORCE_REBUILD:-0}
MINIMAL_MODE=${MINIMAL_MODE:-0}
PATCHBAY=${PATCHBAY:-0}
USE_KXSTUDIO=${USE_KXSTUDIO:-0}
NO_TIMEOUT=${NO_TIMEOUT:-0}

AUDIO_SAMPLE_RATE=${AUDIO_SAMPLE_RATE:-48000}
AUDIO_BUFFER_SIZE=${AUDIO_BUFFER_SIZE:-512}

# --- Uninstaller ---------------------------------------------------------
if [[ $DO_UNINSTALL == 1 || $DO_UNINSTALL_FULL == 1 ]]; then
    log "=== UNINSTALLING ABLETON LIVE ==="
    
    log "Stopping Wine processes..."
    wineserver -k 2>/dev/null || true
    pkill -9 -f "wine.*ableton" 2>/dev/null || true
    sleep 2
    
    [[ $ENABLE_SYSTEMD == 1 ]] && systemctl --user disable --now a2jmidid.service 2>/dev/null || true
    rm -rf ~/.config/systemd/user
    systemctl --user daemon-reload 2>/dev/null || true
    
    read -p "Remove Wine packages too? (y/N): " -n 1 -r; echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Removing Wine packages..."
        sudo apt -y remove winehq-* wine-staging wine-stable winetricks 2>/dev/null || true
        sudo apt -y autoremove 2>/dev/null || true
    fi
    
    log "Removing WineASIO..."
    sudo rm -f /usr/local/lib/wine/x86_64-windows/wineasio.dll
    sudo rm -f /usr/local/lib64/wine/wineasio64.dll.so
    sudo rm -f /usr/local/bin/wineasio-register
    sudo rm -f /usr/lib/x86_64-linux-gnu/wine/x86_64-windows/wineasio.dll
    sudo rm -f /usr/lib/x86_64-linux-gnu/wine/x86_64-unix/wineasio64.dll.so
    
    log "Removing Ableton installation..."
    rm -rf "$PREFIX"
    rm -f ~/.local/bin/ableton-live-wrapper
    rm -f ~/.local/share/applications/ableton.desktop
    rm -f ~/.local/share/icons/ableton.png
    
    rm -f ~/.config/pipewire/pipewire.conf.d/90-lowlatency.conf
    rm -f ~/.config/rncbc.org/QjackCtl/patches/ableton.xml
    
    if [[ $DO_UNINSTALL_FULL == 1 ]]; then
        log "Removing user data..."
        rm -rf ~/Documents/Ableton ~/.Ableton ~/.config/Ableton
    else
        log "Preserving user projects in ~/Documents/Ableton"
    fi
    
    log "✓ Uninstall complete"
    exit 0
fi

# --- Main Installation ---------------------------------------------------
log "=== ABLETON LIVE SETUP STARTED ==="
log "Log file: $LOG"
log "Options: WINE_BRANCH=$WINE_BRANCH, PREFIX=$PREFIX, FORCE_REINSTALL=$FORCE_REINSTALL, FORCE_REBUILD=$FORCE_REBUILD, USE_KXSTUDIO=$USE_KXSTUDIO, NO_TIMEOUT=$NO_TIMEOUT"

# --- System Check & Tuning -----------------------------------------------
tune_system_for_wine

for cmd in curl git unzip make gcc wine; do
    command_exists "$cmd" || die "Required command not found: $cmd"
done

UBUNTU_VER=$(lsb_release -rs 2>/dev/null || echo "0")
if (( $(echo "$UBUNTU_VER >= 24.04" | bc -l) )); then
    warn "Ubuntu $UBUNTU_VER detected - PipeWire may cause WineASIO issues"
    warn "Recommended: sudo apt install jackd2 && use JACK instead of PipeWire"
fi

get_wine_info
[[ "$WINE_VERSION" == *"not found"* ]] && die "Wine not found! Install Wine first"

# --- Version Check -------------------------------------------------------
log "=== STEP 1: Version check ==="

get_installed_version() {
    local version_file="$PREFIX/ableton_version.txt"
    [[ -f "$version_file" ]] && cat "$version_file" || echo ""
}

INSTALLER_VERSION=$(extract_installer_version "$INSTALLER_PATH")
INSTALLED_VERSION=$(get_installed_version)

log "Installed: ${INSTALLED_VERSION:-None}"
log "Target: $INSTALLER_VERSION"

if [[ -n "$INSTALLED_VERSION" && "$INSTALLED_VERSION" == "$INSTALLER_VERSION" && $FORCE_REINSTALL == 0 ]]; then
    log "Already installed and up-to-date. Use --force-reinstall to override."
    read -p "Continue anyway? (y/N): " -n 1 -r; echo
    [[ $REPLY =~ ^[Yy]$ ]] || exit 0
fi

# --- Wine Repository Setup ----------------------------------------------
log "=== STEP 2: Configuring Wine repository ==="

if ! dpkg --print-foreign-architectures 2>/dev/null | grep -q i386; then
    log "Adding i386 architecture..."
    sudo dpkg --add-architecture i386
    sudo apt update
fi

if [[ ! -f /etc/apt/keyrings/winehq.key ]]; then
    log "Adding WineHQ key..."
    sudo mkdir -p /etc/apt/keyrings
    wget -qO- https://dl.winehq.org/wine-builds/winehq.key | sudo tee /etc/apt/keyrings/winehq.key >/dev/null
fi

REPO_FILE="/etc/apt/sources.list.d/winehq.sources"
if [[ ! -f "$REPO_FILE" ]]; then
    log "Adding WineHQ repository..."
    UBUNTU_CODENAME=$(lsb_release -cs)
    cat <<EOF | sudo tee "$REPO_FILE" >/dev/null
Types: deb
URIs: https://dl.winehq.org/wine-builds/ubuntu 
Suites: $UBUNTU_CODENAME
Components: main
Architectures: amd64 i386
Signed-By: /etc/apt/keyrings/winehq.key
EOF
    sudo apt update
fi

# --- Install Packages ---------------------------------------------------
log "=== STEP 3: Installing packages ==="

# Install WineHQ if not already present
if ! dpkg -l | grep -q "winehq-"; then
    log "Installing WineHQ $WINE_BRANCH..."
    sudo apt install -y --install-recommends "winehq-$WINE_BRANCH" winetricks
fi

get_wine_info  # Re-check after installation

# Core dependencies (CRITICAL)
CORE_PKGS=(
    pipewire-jack qjackctl a2jmidid curl git jq imagemagick
    build-essential libasound2-dev libjack-jackd2-dev libwine-dev unzip
)

# Development packages (match Wine version)
if [[ "$WINE_VERSION" == *"Staging"* ]]; then
    CORE_PKGS+=(wine-staging-dev wine-tools)
elif [[ "$WINE_VERSION" == *"Stable"* ]]; then
    CORE_PKGS+=(wine-stable-dev wine-tools)
else
    CORE_PKGS+=(wine-staging-dev wine-tools)
fi

install_packages "${CORE_PKGS[@]}"

# Optional packages for full features
if [[ $MINIMAL_MODE == 0 ]]; then
    OPTIONAL_PKGS=()
    (( $(echo "$UBUNTU_VER >= 24.04" | bc -l) )) || OPTIONAL_PKGS+=(catia ladish)
    OPTIONAL_PKGS+=(jackd2 carla)
    install_packages "${OPTIONAL_PKGS[@]}"
fi

# --- Build WineASIO ---------------------------------------------------
log "=== STEP 4: Installing WineASIO ==="

WINEASIO_DLL="/usr/local/lib/wine/x86_64-windows/wineasio.dll"
WINEASIO_SO="/usr/local/lib64/wine/wineasio64.dll.so"

# Option 1: KXStudio repositories (RECOMMENDED)
if [[ $USE_KXSTUDIO == 1 ]]; then
    log "Using KXStudio repositories for WineASIO..."
    
    if [[ ! -f /etc/apt/sources.list.d/kxstudio-debian.list ]]; then
        log "Adding KXStudio repository..."
        wget -q https://launchpad.net/~kxstudio-debian/+archive/kxstudio/+files/kxstudio-repos_9.5.1~kxstudio3_all.deb -O /tmp/kxstudio-repos.deb
        sudo dpkg -i /tmp/kxstudio-repos.deb || true
        sudo apt update
    fi
    
    if sudo apt install -y wineasio; then
        log "✓ WineASIO installed from KXStudio"
        WINEASIO_DLL="/usr/lib/x86_64-linux-gnu/wine/x86_64-windows/wineasio.dll"
        WINEASIO_SO="/usr/lib/x86_64-linux-gnu/wine/x86_64-unix/wineasio64.dll.so"
    else
        warn "KXStudio WineASIO failed, falling back to build method"
        USE_KXSTUDIO=0
    fi
fi

# Option 2: Build from source (FALLBACK)
if [[ $USE_KXSTUDIO == 0 ]]; then
    if [[ -f "$WINEASIO_SO" && $FORCE_REBUILD == 0 ]]; then
        log "WineASIO already built (use --force-rebuild to override)"
    else
        log "Building WineASIO from source..."
        BUILD_DIR=$(mktemp -d) || die "Failed to create build directory"
        debug "Build directory: $BUILD_DIR"
        
        if ! cd "$BUILD_DIR"; then
            rm -rf "$BUILD_DIR"
            die "Failed to change to build directory"
        fi
        
        # FIX: Separate git clone from logging to avoid syntax error
        log "Cloning WineASIO repository..."
        CLONE_SUCCESS=0
        
        # First attempt: try specific version
        if git clone --depth 1 --branch "$WINEASIO_VERSION" https://github.com/wineasio/wineasio.git . 2>&1; then
            if [[ -f "Makefile" && -f "wineasio-register" ]]; then
                debug "✓ Branch $WINEASIO_VERSION cloned successfully"
                CLONE_SUCCESS=1
            fi
        fi
        
        # Second attempt: fallback to master if first failed
        if [[ $CLONE_SUCCESS == 0 ]]; then
            warn "Branch $WINEASIO_VERSION not found, trying master..."
            rm -rf ./* .git 2>/dev/null || true
            
            if git clone --depth 1 https://github.com/wineasio/wineasio.git . 2>&1; then
                if [[ -f "Makefile" && -f "wineasio-register" ]]; then
                    debug "✓ Master branch cloned successfully"
                    CLONE_SUCCESS=1
                fi
            fi
        fi
        
        # Check if clone was successful
        if [[ $CLONE_SUCCESS == 0 ]]; then
            cd "$HOME" || true
            rm -rf "$BUILD_DIR"
            die "Failed to obtain WineASIO source code"
        fi
        
        # Find Wine headers
        WINE_INCLUDE=""
        for path in "/usr/include/wine/wine/windows" "/usr/include/wine-development/wine/windows" "/usr/include/wine/windows"; do
            if [[ -f "$path/objbase.h" ]]; then
                WINE_INCLUDE="$path"
                debug "✓ Found Wine headers at: $WINE_INCLUDE"
                break
            fi
        done
        
        [[ -z "$WINE_INCLUDE" ]] && die "Wine headers not found. Install wine-staging-dev"
        
        # Build
        export CFLAGS="-I$WINE_INCLUDE"
        debug "Building WineASIO with CFLAGS=$CFLAGS"
        if ! run_with_timeout "$WINE_TIMEOUT" make 64 2>&1 | tee -a "$LOG"; then
            cd "$HOME" || true
            rm -rf "$BUILD_DIR"
            die "WineASIO build failed"
        fi
        
        # Verify build
        [[ ! -f "build64/wineasio64.dll.so" || ! -f "build64/wineasio64.dll" ]] && \
            die "Build failed: output files not found"
        
        # Install
        log "Installing WineASIO files..."
        sudo mkdir -p /usr/local/lib/wine/x86_64-windows/ /usr/local/lib64/wine/
        sudo cp build64/wineasio64.dll.so "$WINEASIO_SO"
        sudo cp build64/wineasio64.dll "$WINEASIO_DLL"
        sudo cp wineasio-register /usr/local/bin/
        sudo chmod +x /usr/local/bin/wineasio-register
        
        # Cleanup
        cd "$HOME" || true
        rm -rf "$BUILD_DIR"
        log "✓ WineASIO built and installed"
    fi
fi

# Verify WineASIO files
[[ ! -f "$WINEASIO_DLL" || ! -f "$WINEASIO_SO" ]] && die "WineASIO files missing"

# --- Setup Wine Prefix -------------------------------------------------
log "=== STEP 5: Setting up Wine prefix ==="

export WINEARCH=win64
export WINEPREFIX="$PREFIX"

# Kill existing processes
wineserver -k 2>/dev/null || true
sleep 2

# Remove prefix if forcing reinstall
if [[ $FORCE_REINSTALL == 1 && -d "$PREFIX" ]]; then
    log "Removing existing prefix for clean install..."
    rm -rf "$PREFIX"
fi

# Create prefix
if [[ ! -d "$PREFIX" ]]; then
    log "Creating new Wine prefix at $PREFIX..."
    mkdir -p "$PREFIX"
    
    run_with_timeout "$WINE_TIMEOUT" wineboot --init || warn "wineboot had minor issues"
    wait_for_wine_prefix "$PREFIX" 60
    
    # Configure Wine
    winecfg -v win10 2>/dev/null || true
    
    # Disable crash dialogs
    cat > /tmp/disable_dlg.reg <<'EOF'
REGEDIT4
[HKEY_CURRENT_USER\Software\Wine\WineDbg]
"ShowCrashDialog"=dword:00000000
EOF
    wine regedit /tmp/disable_dlg.reg 2>/dev/null || true
    rm -f /tmp/disable_dlg.reg
    
    log "✓ Wine prefix created"
else
    log "Using existing Wine prefix"
fi

# --- Install Windows Runtimes ------------------------------------------
log "=== STEP 6: Installing Windows runtimes ==="

# Update winetricks if old
if [[ ! -f ~/.cache/winetricks/lastupdate ]] || [[ $(find ~/.cache/winetricks/lastupdate -mtime +7 2>/dev/null) ]]; then
    log "Updating winetricks..."
    sudo winetricks --self-update 2>/dev/null || warn "Could not update winetricks"
    touch ~/.cache/winetricks/lastupdate
fi

# Install runtimes
WINETRICKS_OPTS="-q --force"
for runtime in vcrun2019 vcrun2022 corefonts dxvk; do
    log "Installing $runtime..."
    if ! WINEPREFIX="$PREFIX" winetricks $WINETRICKS_OPTS "$runtime" 2>/dev/null; then
        warn "$runtime had minor issues (non-critical)"
    else
        debug "✓ $runtime installed"
    fi
done

# --- Register WineASIO -------------------------------------------------
log "=== STEP 7: Registering WineASIO ==="

WINEASIO_DST_DLL="$PREFIX/drive_c/windows/system32/wineasio.dll"
cp "$WINEASIO_DLL" "$WINEASIO_DST_DLL"
debug "DLL copied to: $WINEASIO_DST_DLL"

[[ ! -f "$WINEASIO_DST_DLL" ]] && die "Failed to copy WineASIO DLL to prefix"

# Register with multiple methods
log "Registering WineASIO..."
REG_SUCCESS=0

# Method 1: Direct registration
debug "Method 1: Direct registration..."
if WINEPREFIX="$PREFIX" $WINE_CMD regsvr32 "$WINEASIO_DST_DLL" 2>&1 | tee -a "$LOG"; then
    log "✓ WineASIO registered (Method 1)"
    REG_SUCCESS=1
fi

# Method 2: wineasio-register script
if [[ $REG_SUCCESS == 0 && -x /usr/local/bin/wineasio-register ]]; then
    debug "Method 2: wineasio-register..."
    if WINEPREFIX="$PREFIX" wineasio-register 2>&1 | tee -a "$LOG"; then
        log "✓ WineASIO registered (Method 2)"
        REG_SUCCESS=1
    fi
fi

[[ $REG_SUCCESS == 0 ]] && warn "⚠ WineASIO registration may have issues"

# --- Download & Install Ableton ----------------------------------------
log "=== STEP 8: Installing Ableton Live ==="

INSTALLER_ZIP="/tmp/ableton_installer.zip"
INSTALLER_DIR="/tmp/ableton_installer_$$"

if [[ "$INSTALLER_PATH" =~ ^https?:// ]]; then
    if [[ ! -f "$INSTALLER_ZIP" || $FORCE_REINSTALL == 1 ]]; then
        log "Downloading installer from URL (timeout: ${CURL_TIMEOUT}s)..."
        rm -f "$INSTALLER_ZIP"
        
        for i in {1..3}; do
            run_with_timeout "$CURL_TIMEOUT" curl -fSL "$INSTALLER_PATH" -o "$INSTALLER_ZIP" && break
            warn "Download attempt $i failed"
            sleep 5
        done
        
        [[ ! -f "$INSTALLER_ZIP" || ! -s "$INSTALLER_ZIP" ]] && die "Failed to download installer"
        
        file_size=$(stat -c%s "$INSTALLER_ZIP" 2>/dev/null || echo "0")
        [[ $file_size -lt 1000000 ]] && die "Downloaded file too small ($file_size bytes)"
        
        log "✓ Download complete ($(numfmt --to=iec-i --suffix=B "$file_size"))"
    else
        log "Using cached installer"
    fi
    INSTALLER_FILE="$INSTALLER_ZIP"
else
    [[ -f "$INSTALLER_PATH" ]] && INSTALLER_FILE="$INSTALLER_PATH" || die "Installer file not found: $INSTALLER_PATH"
fi

# Extract installer
log "Extracting installer..."
rm -rf "$INSTALLER_DIR"
mkdir -p "$INSTALLER_DIR"
unzip -q "$INSTALLER_FILE" -d "$INSTALLER_DIR" || die "Failed to extract installer"

INSTALLER_EXE=$(find "$INSTALLER_DIR" -type f -name "*.exe" | grep -i "installer" | head -1)
[[ -z "$INSTALLER_EXE" ]] && INSTALLER_EXE=$(find "$INSTALLER_DIR" -maxdepth 1 -type f -name "*.exe" | head -1)
[[ -z "$INSTALLER_EXE" ]] && die "No installer executable found"

log "Found installer: $(basename "$INSTALLER_EXE")"

# Run installer
log "Launching Ableton installer GUI..."
WINEPREFIX="$PREFIX" $WINE_CMD "$INSTALLER_EXE" &
INSTALLER_PID=$!
sleep 10

INSTALLATION_DETECTED=0

if [[ $NO_TIMEOUT == 1 ]]; then
    log "Please complete the installation wizard (no timeout - press Ctrl+C to abort)..."
    while kill -0 "$INSTALLER_PID" 2>/dev/null; do
        if [[ $INSTALLATION_DETECTED == 0 ]]; then
            for path in "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" \
                         "$PREFIX/drive_c/Program Files/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" \
                         "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Trial/Program/Ableton Live $ABLETON_VERSION Trial.exe"; do
                [[ -f "$path" ]] && log "✓ Ableton installation detected (waiting for completion)..." && INSTALLATION_DETECTED=1
            done
        fi
        sleep 10
    done
    log "Installer process finished naturally"
else
    max_iterations=1440
    log "Please complete installation wizard (timeout: 240 minutes)..."
    for i in $(seq 1 $max_iterations); do
        kill -0 "$INSTALLER_PID" 2>/dev/null || break
        
        if [[ $INSTALLATION_DETECTED == 0 ]]; then
            for path in "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" \
                         "$PREFIX/drive_c/Program Files/Ableton/Live $ABLETON_VERSION Suite/Program/Ableton Live $ABLETON_VERSION Suite.exe" \
                         "$PREFIX/drive_c/ProgramData/Ableton/Live $ABLETON_VERSION Trial/Program/Ableton Live $ABLETON_VERSION Trial.exe"; do
                [[ -f "$path" ]] && log "✓ Ableton installation detected (waiting for completion)..." && INSTALLATION_DETECTED=1
            done
        fi
        
        sleep 10
    done
    
    if kill -0 "$INSTALLER_PID" 2>/dev/null; then
        warn "Timeout reached, killing installer..."
        safe_kill "$INSTALLER_PID"
    fi
fi

# FIXED: CRITICAL - Wait for ALL Wine processes to finish
log "Installer GUI closed. Waiting for background Wine processes to complete..."
POST_INSTALL_WAIT=300  # 5 minutes
for i in $(seq 1 $POST_INSTALL_WAIT); do
    # Check if any Wine processes are still running for this prefix
    if pgrep -f "WINEPREFIX=$PREFIX" >/dev/null 2>&1 || pgrep -f "$PREFIX" >/dev/null 2>&1; then
        [[ $((i % 30)) == 0 ]] && debug "Background processes still running... $i/$POST_INSTALL_WAIT seconds"
    else
        log "✓ All background processes finished after $i seconds"
        break
    fi
    sleep 1
done

# Additional grace period for file system
sleep 5

# Save version
echo "$INSTALLER_VERSION" > "$PREFIX/ableton_version.txt"
rm -rf "$INSTALLER_DIR"

# --- Find Ableton Executable -------------------------------------------
log "Searching for Ableton executable..."
ABLETON_EXE=""
for path in "$PREFIX/drive_c/ProgramData/Ableton/Live ${ABLETON_VERSION} Suite/Program/Ableton Live ${ABLETON_VERSION} Suite.exe" \
             "$PREFIX/drive_c/Program Files/Ableton/Live ${ABLETON_VERSION} Suite/Program/Ableton Live ${ABLETON_VERSION} Suite.exe" \
             "$PREFIX/drive_c/ProgramData/Ableton/Live ${ABLETON_VERSION} Trial/Program/Ableton Live ${ABLETON_VERSION} Trial.exe" \
             "$PREFIX/drive_c/Program Files/Ableton/Live ${ABLETON_VERSION} Trial/Program/Ableton Live ${ABLETON_VERSION} Trial.exe"; do
    [[ -f "$path" ]] && ABLETON_EXE="$path" && log "✓ Found Ableton executable: $path" && break
done

if [[ -z "$ABLETON_EXE" ]]; then
    warn "Initial search failed, performing deep search..."
    ABLETON_EXE=$(find "$PREFIX/drive_c" -type f -name "Ableton Live ${ABLETON_VERSION} *.exe" -path "*/Program/*" 2>/dev/null | head -1)
    [[ -n "$ABLETON_EXE" ]] && log "✓ Found via deep search: $ABLETON_EXE"
fi

[[ -z "$ABLETON_EXE" ]] && warn "⚠ Could not find Ableton Live executable" && warn "Check $PREFIX/drive_c/ProgramData/Ableton/"

# --- CRITICAL: Determine Correct WM_CLASS -------------------------------
# Wine generates WM_CLASS as lowercase with underscores
WM_CLASS="ableton_live_${ABLETON_VERSION}_trial.exe"
if [[ "$ABLETON_EXE" == *"Suite"* ]]; then
    WM_CLASS="ableton_live_${ABLETON_VERSION}_suite.exe"
fi
debug "Detected WM_CLASS for desktop entry: $WM_CLASS"

# --- Create Launcher & Desktop Integration (FIXED) -----------------------
log "=== STEP 9: Creating desktop integration ==="

WRAPPER_SCRIPT="$HOME/.local/bin/ableton-live-wrapper"
ICON_PATH="$HOME/.local/share/icons/ableton.png"
DESKTOP_PATH="$HOME/.local/share/applications/ableton.desktop"

log "Removing old launcher files..."
rm -f "$WRAPPER_SCRIPT" "$ICON_PATH" "$DESKTOP_PATH"
update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || true
xdg-desktop-menu forceupdate 2>/dev/null || true

# Create wrapper script with PURE Windows paths
log "Creating launcher script..."
mkdir -p "$(dirname "$WRAPPER_SCRIPT")"

cat > "$WRAPPER_SCRIPT" <<'EOWRAPPER'
#!/bin/bash
# Ableton Live Launcher

export WINEPREFIX="__PREFIX_PLACEHOLDER__"
export WINEDEBUG=${WINEDEBUG:--all}
export BROWSER=${BROWSER:-xdg-open}
export WINE_DISABLE_MEMORY_MANAGER=1
export WINE_LARGE_ADDRESS_AWARE=1

# Find Ableton executable using PURE Windows paths
ABLETON_WIN_PATH=""
for win_path in \
    "C:\\ProgramData\\Ableton\\Live __VERSION_PLACEHOLDER__ Suite\\Program\\Ableton Live __VERSION_PLACEHOLDER__ Suite.exe" \
    "C:\\Program Files\\Ableton\\Live __VERSION_PLACEHOLDER__ Suite\\Program\\Ableton Live __VERSION_PLACEHOLDER__ Suite.exe" \
    "C:\\ProgramData\\Ableton\\Live __VERSION_PLACEHOLDER__ Trial\\Program\\Ableton Live __VERSION_PLACEHOLDER__ Trial.exe" \
    "C:\\Program Files\\Ableton\\Live __VERSION_PLACEHOLDER__ Trial\\Program\\Ableton Live __VERSION_PLACEHOLDER__ Trial.exe"; do
    # Convert to Unix path for existence check
    unix_path="${win_path//\\//}"
    unix_path="${unix_path/C:/$WINEPREFIX/drive_c}"
    if [[ -f "$unix_path" ]]; then
        ABLETON_WIN_PATH="$win_path"
        break
    fi
done

if [[ -z "$ABLETON_WIN_PATH" ]]; then
    echo "ERROR: Could not find Ableton Live executable"
    echo "Check installation in: $WINEPREFIX/drive_c/ProgramData/Ableton/"
    exit 1
fi

# Launch Ableton
exec __WINE_CMD_PLACEHOLDER__ "$ABLETON_WIN_PATH" "$@"
EOWRAPPER

sed -i "s|__PREFIX_PLACEHOLDER__|$PREFIX|g" "$WRAPPER_SCRIPT"
sed -i "s/__VERSION_PLACEHOLDER__/$ABLETON_VERSION/g" "$WRAPPER_SCRIPT"
sed -i "s|__WINE_CMD_PLACEHOLDER__|$WINE_CMD|g" "$WRAPPER_SCRIPT"
chmod +x "$WRAPPER_SCRIPT"
[[ -x "$WRAPPER_SCRIPT" ]] && debug "✓ Launcher script created: $WRAPPER_SCRIPT" || warn "✗ Failed to create executable launcher"

# Extract icon
log "Extracting Ableton icon..."
mkdir -p "$(dirname "$ICON_PATH")"

ICON_EXTRACTED=0
if [[ -n "$ABLETON_EXE" && -f "$ABLETON_EXE" ]]; then
    if command_exists wrestool && command_exists convert; then
        if wrestool -x -t 14 "$ABLETON_EXE" 2>/dev/null | convert - -resize 256x256 "$ICON_PATH" 2>/dev/null; then
            debug "✓ Icon extracted from executable"
            ICON_EXTRACTED=1
        fi
    fi
fi

if [[ $ICON_EXTRACTED == 0 ]]; then
    log "Creating generic icon (fallback)..."
    convert -size 256x256 xc:"#0000ff" -fill white -gravity center -pointsize 96 -annotate 0 "A" "$ICON_PATH" 2>/dev/null || \
        warn "✗ Failed to create icon"
fi

[[ -f "$ICON_PATH" ]] && debug "✓ Icon created: $ICON_PATH" || warn "✗ Icon file not found"

# Create desktop entry with CORRECT WM_CLASS
log "Creating desktop entry..."
mkdir -p "$(dirname "$DESKTOP_PATH")"

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
cat > "$DESKTOP_PATH" <<EODESKTOP
[Desktop Entry]
Version=1.0
Type=Application
Name=Ableton Live $ABLETON_VERSION
Comment=Digital Audio Workstation (Installed: $TIMESTAMP)
Exec=$WRAPPER_SCRIPT %U
Icon=$ICON_PATH
Terminal=false
Categories=AudioVideo;Audio;Music;Midi;
Keywords=music;audio;production;daw;ableton;
StartupNotify=true
StartupWMClass=$WM_CLASS
MimeType=x-scheme-handler/ableton;

[Desktop Action Configure]
Name=Configure Wine Audio
Exec=env WINEPREFIX="$PREFIX" winecfg

[Desktop Action KillWine]
Name=Kill Wine Processes
Exec=wineserver -k
EODESKTOP

chmod +x "$DESKTOP_PATH"
[[ -f "$DESKTOP_PATH" ]] && debug "✓ Desktop entry created: $DESKTOP_PATH" || warn "✗ Desktop entry not created"

# Update desktop database
log "Updating desktop database..."
update-desktop-database -q "$HOME/.local/share/applications" 2>/dev/null || debug "Desktop update returned non-zero"
xdg-desktop-menu forceupdate 2>/dev/null || debug "xdg-desktop-menu not available"

# Validate desktop entry
if command_exists desktop-file-validate; then
    debug "Validating desktop entry..."
    desktop-file-validate "$DESKTOP_PATH" 2>&1 || warn "⚠ Desktop entry validation warnings"
fi

# --- CRITICAL: Fix Browser Integration for Licensing --------------------
log "=== STEP 10: Configuring browser integration ==="

# COMPREHENSIVE FIX: Register winebrowser as the default handler
# This includes both URL protocols AND file associations
cat > /tmp/winebrowser_fix.reg <<'EOF'
REGEDIT4

; HTTP/HTTPS URL handlers
[HKEY_CLASSES_ROOT\http]
@="URL:HyperText Transfer Protocol"
"URL Protocol"=""
[HKEY_CLASSES_ROOT\http\shell]
[HKEY_CLASSES_ROOT\http\shell\open]
[HKEY_CLASSES_ROOT\http\shell\open\command]
@="winebrowser \"%1\""

[HKEY_CLASSES_ROOT\https]
@="URL:HyperText Transfer Protocol Secure"
"URL Protocol"=""
[HKEY_CLASSES_ROOT\https\shell]
[HKEY_CLASSES_ROOT\https\shell\open]
[HKEY_CLASSES_ROOT\https\shell\open\command]
@="winebrowser \"%1\""

; Ableton-specific handler
[HKEY_CLASSES_ROOT\ableton]
@="URL:Ableton Authorization"
"URL Protocol"=""
[HKEY_CLASSES_ROOT\ableton\shell]
[HKEY_CLASSES_ROOT\ableton\shell\open]
[HKEY_CLASSES_ROOT\ableton\shell\open\command]
@="winebrowser \"%1\""

; File associations for HTML
[HKEY_CLASSES_ROOT\.htm]
@="htmlfile"
[HKEY_CLASSES_ROOT\.html]
@="htmlfile"

[HKEY_CLASSES_ROOT\htmlfile]
@="HTML Document"
[HKEY_CLASSES_ROOT\htmlfile\shell]
[HKEY_CLASSES_ROOT\htmlfile\shell\open]
[HKEY_CLASSES_ROOT\htmlfile\shell\open\command]
@="winebrowser \"%1\""

; Default browser setting
[HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\http\UserChoice]
"ProgId"="https"

[HKEY_CURRENT_USER\Software\Microsoft\Windows\Shell\Associations\UrlAssociations\https\UserChoice]
"ProgId"="https"

; Ensure winebrowser is executable
[HKEY_LOCAL_MACHINE\Software\Wine\Browser]
"BROWSER"="winebrowser"
EOF

# Import registry settings
log "Registering URL handlers for browser integration..."
WINEPREFIX="$PREFIX" regedit /tmp/winebrowser_fix.reg 2>&1 | tee -a "$LOG" || warn "Registry import had issues"
rm -f /tmp/winebrowser_fix.reg

# Verify winebrowser exists and is executable
WINE_BROWSER="$PREFIX/drive_c/windows/syswow64/winebrowser.exe"
[[ ! -f "$WINE_BROWSER" ]] && WINE_BROWSER="$PREFIX/drive_c/windows/system32/winebrowser.exe"

if [[ -f "$WINE_BROWSER" ]]; then
    debug "✓ winebrowser.exe found at: $WINE_BROWSER"
else
    warn "⚠ winebrowser.exe not found in expected location"
fi

# --- Optional Features -------------------------------------------------
if [[ $MINIMAL_MODE == 0 ]]; then
    # Yabridge
    if [[ $ENABLE_YABRIDGE == 1 ]]; then
        log "=== STEP 11: Installing Yabridge ==="
        if command_exists yabridgectl && [[ $FORCE_REINSTALL == 0 ]]; then
            log "Yabridge already installed"
        else
            YABRIDGE_JSON=$(curl -s https://api.github.com/repos/robbert-vdh/yabridge/releases/latest )
            YABRIDGE_URL=$(echo "$YABRIDGE_JSON" | jq -r '.assets[] | select(.name | test("tar\\.gz$")) | .browser_download_url' | head -1)
            
            if [[ -z "$YABRIDGE_URL" || "$YABRIDGE_URL" == "null" ]]; then
                warn "Could not find Yabridge download URL"
            else
                debug "Yabridge URL: $YABRIDGE_URL"
                TMPDIR=$(mktemp -d)
                
                if curl -fsSL "$YABRIDGE_URL" -o "$TMPDIR/yabridge.tar.gz"; then
                    if tar -xzf "$TMPDIR/yabridge.tar.gz" -C "$TMPDIR"; then
                        YABRIDGE_BIN=$(find "$TMPDIR" -name "yabridge" -type f -executable | head -1)
                        YABRIDGECTL_BIN=$(find "$TMPDIR" -name "yabridgectl" -type f -executable | head -1)
                        
                        if [[ -n "$YABRIDGE_BIN" && -n "$YABRIDGECTL_BIN" ]]; then
                            mkdir -p ~/.local/bin
                            cp "$YABRIDGE_BIN" "$YABRIDGECTL_BIN" ~/.local/bin/
                            chmod +x ~/.local/bin/yabridge ~/.local/bin/yabridgectl
                            ~/.local/bin/yabridgectl add "$PREFIX" 2>/dev/null
                            ~/.local/bin/yabridgectl sync 2>/dev/null
                            log "✓ Yabridge installed and synced"
                        else
                            warn "Yabridge binaries not found after extraction"
                        fi
                    else
                        warn "Failed to extract Yabridge"
                    fi
                else
                    warn "Failed to download Yabridge"
                fi
                rm -rf "$TMPDIR"
            fi
        fi
    fi
    
    # MIDI bridge
    if [[ $ENABLE_LOOPMIDI == 1 ]]; then
        log "=== STEP 12: Setting up MIDI bridge ==="
        if [[ $ENABLE_SYSTEMD == 1 ]]; then
            mkdir -p ~/.config/systemd/user
            cat > ~/.config/systemd/user/a2jmidid.service <<EOSERVICE
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
EOSERVICE
            systemctl --user daemon-reload
            systemctl --user enable --now a2jmidid.service 2>/dev/null || \
                warn "Could not start MIDI service (may need manual start: systemctl --user start a2jmidid)"
            log "✓ MIDI service configured"
        else
            log "MIDI bridge installed (run 'a2jmidid -e' manually before using Ableton)"
        fi
    fi
    
    # PipeWire tweaks
    if [[ $TWEAK_PIPEWIRE == 1 ]]; then
        log "=== STEP 13: Applying PipeWire low-latency tweaks ==="
        warn "PipeWire mode is experimental - JACK2 is strongly recommended for production"
        mkdir -p ~/.config/pipewire/pipewire.conf.d
        cat > ~/.config/pipewire/pipewire.conf.d/90-lowlatency.conf <<EOPW
stream.properties = {
    node.latency = $AUDIO_BUFFER_SIZE/$AUDIO_SAMPLE_RATE
    node.rate = $AUDIO_SAMPLE_RATE
}
EOPW
        systemctl --user restart pipewire pipewire-pulse 2>/dev/null || \
            warn "PipeWire restart failed (changes will apply after reboot)"
        log "✓ PipeWire tweaks applied"
    fi
    
    # Patchbay
    if [[ $PATCHBAY == 1 ]]; then
        log "=== STEP 14: Creating QJackCtl patchbay ==="
        mkdir -p ~/.config/rncbc.org/QjackCtl/patches
        cat > ~/.config/rncbc.org/QjackCtl/patches/ableton.xml <<EOXML
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
EOXML
        log "✓ Patchbay template created"
    fi
else
    log "MINIMAL MODE: Skipping optional features"
fi

# --- Final Cleanup ------------------------------------------------------
log "=== STEP 15: Final cleanup ==="
wineserver -k 2>/dev/null || true
sleep 2

# --- Summary ------------------------------------------------------------
log "=== INSTALLATION SUMMARY ==="

[[ -f "$WINEASIO_DLL" && -f "$WINEASIO_SO" ]] && log "✓ WineASIO installed" || warn "✗ WineASIO files missing"
[[ -n "$ABLETON_EXE" ]] && log "✓ Ableton Live installed" && debug "  Executable: $ABLETON_EXE" || warn "✗ Ableton executable not found"
[[ -x "$WRAPPER_SCRIPT" ]] && log "✓ Desktop launcher created" && log "  Run manually: $WRAPPER_SCRIPT" || warn "✗ Launcher not executable"
[[ -f "$ICON_PATH" ]] && log "✓ Icon created" || warn "✗ Icon not found"
[[ -f "$DESKTOP_PATH" ]] && log "✓ Desktop entry created" && debug "  Entry: $DESKTOP_PATH" || warn "✗ Desktop entry not created"

# User prompt for --no-timeout mode
if [[ $NO_TIMEOUT == 1 ]]; then
    log ""
    read -p "Installation complete. Press 'y' to continue... " -n 1 -r
    echo
fi

# Final instructions
log ""
log "🎵 NEXT STEPS:"
log "1. Launch Ableton from applications menu (search 'Ableton')"
log "2. Go to Preferences → Audio"
log "3. Select 'ASIO' as Driver Type"
log "4. Select 'WINEASIO' as Audio Device"
log "5. Set Sample Rate: $AUDIO_SAMPLE_RATE Hz"
log "6. Set Buffer Size: $AUDIO_BUFFER_SIZE samples"
log ""
log "🌐 LICENSING:"
log "• Click 'Authorize' in Ableton"
log "• Browser will open for authorization"
log "• Copy code back to Ableton"
log ""
log "🐛 TROUBLESHOOTING:"
log "• Full log: $LOG"
log "• Manual WineASIO reg: WINEPREFIX='$PREFIX' $WINE_CMD regsvr32 '$WINEASIO_DST_DLL'"
log "• Kill Wine: wineserver -k"
log "• Test launch: $WRAPPER_SCRIPT"
log ""
log "🎚️  AUDIO SETUP:"
log "• Use QJackCtl to configure JACK before starting Ableton"
log "• Or use PipeWire with --tweak-pipewire (experimental)"
log "• Consider --use-kxstudio for easier WineASIO installation"
log ""
log "🗑️  UNINSTALL:"
log "• ./ableton_setup.sh --uninstall       (keep projects)"
log "• ./ableton_setup.sh --uninstall-full  (remove everything)"
log ""

# Validate installation
[[ -z "$ABLETON_EXE" ]] && die "Installation incomplete: Ableton executable not found"

log "✓ Setup complete! Launch Ableton from your application menu or run: $WRAPPER_SCRIPT"
exit 0
