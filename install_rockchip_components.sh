#!/bin/bash
#
# Rockchip NPU Components Installation Script (Podman Edition)
#
# This script installs all required components for building C++ applications
# that use the Rockchip NPU for inference with YOLOX model.
#
# Uses Podman instead of Docker (daemonless, rootless container runtime)
#
# Supports:
# - Orange Pi 5/5B/5 Plus (RK3588) - Native ARM64 development
# - BrightSign XT-5 (RK3588) - Cross-compilation via SDK
# - BrightSign LS-5 (RK3568) - Cross-compilation via SDK
#
# Usage:
#   ./install_rockchip_components.sh [OPTIONS]
#
# Options:
#   --native-arm64    Install for native ARM64 development (Orange Pi)
#   --cross-compile   Install for x86_64 cross-compilation (BrightSign SDK)
#   --skip-podman     Skip Podman container setup
#   --skip-models     Skip model download and compilation
#   --help            Show this help message
#

set -e  # Exit on error

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}"

# Default configuration
INSTALL_MODE="auto"  # auto, native-arm64, cross-compile
SKIP_PODMAN=false
SKIP_MODELS=false
RKNN_TOOLKIT_VERSION="v2.3.0"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log() {
    echo -e "${BLUE}[$(date +'%T')] $1${NC}"
}

success() {
    echo -e "${GREEN}✓ $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

error() {
    echo -e "${RED}✗ $1${NC}"
    exit 1
}

# Parse command line arguments
parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case $1 in
            --native-arm64)
                INSTALL_MODE="native-arm64"
                shift
                ;;
            --cross-compile)
                INSTALL_MODE="cross-compile"
                shift
                ;;
            --skip-podman|--skip-docker)
                # Support both for backwards compatibility
                SKIP_PODMAN=true
                shift
                ;;
            --skip-models)
                SKIP_MODELS=true
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                error "Unknown option: $1. Use --help for usage information."
                ;;
        esac
    done
}

show_help() {
    cat << HELPEOF
Rockchip NPU Components Installation Script (Podman Edition)

This script installs all required components for building C++ applications
that use the Rockchip NPU for inference with YOLOX model.

Usage:
  $0 [OPTIONS]

Options:
  --native-arm64    Install for native ARM64 development (Orange Pi)
  --cross-compile   Install for x86_64 cross-compilation (BrightSign SDK)
  --skip-podman     Skip Podman container setup (--skip-docker also works)
  --skip-models     Skip model download and compilation
  --help            Show this help message

Examples:
  # Auto-detect platform and install
  $0

  # Install for Orange Pi development
  $0 --native-arm64

  # Install for BrightSign cross-compilation
  $0 --cross-compile

  # Install without Podman (models only)
  $0 --skip-podman

Components Installed:
  - System dependencies (CMake, GCC, Git, etc.)
  - RKNN Toolkit ${RKNN_TOOLKIT_VERSION}
  - RKNN Model Zoo ${RKNN_TOOLKIT_VERSION}
  - OpenCV (image processing)
  - Boost libraries
  - TurboJPEG (JPEG encoding/decoding)
  - Podman (daemonless container runtime)
  - YOLOX models (ONNX and compiled RKNN format)

Note: This script uses Podman instead of Docker.
      Podman is a daemonless, rootless container runtime that is 
      compatible with Docker commands and Dockerfiles.
      
      Advantages of Podman:
      - No daemon required (more secure, lighter weight)
      - Runs rootless by default (better security)
      - Drop-in replacement for Docker (same CLI)
      - Compatible with existing Dockerfiles

HELPEOF
}

# Detect platform
detect_platform() {
    local arch=$(uname -m)
    local os=$(uname -s)

    log "Detecting platform..."
    log "Architecture: $arch"
    log "OS: $os"

    if [[ "$INSTALL_MODE" == "auto" ]]; then
        if [[ "$arch" == "aarch64" ]]; then
            INSTALL_MODE="native-arm64"
            success "Auto-detected: Native ARM64 development environment"
            warn "Note: Model compilation requires x86_64 - you'll need compiled models from x86_64 machine"
        elif [[ "$arch" == "x86_64" ]]; then
            INSTALL_MODE="cross-compile"
            success "Auto-detected: x86_64 cross-compilation environment"
        else
            error "Unsupported architecture: $arch"
        fi
    fi

    log "Installation mode: $INSTALL_MODE"
}

# Check prerequisites
check_prerequisites() {
    log "Checking prerequisites..."

    # Check for essential tools
    local missing_tools=()

    for tool in git cmake wget tar; do
        if ! command -v $tool &> /dev/null; then
            missing_tools+=($tool)
        fi
    done

    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing_tools[*]}. Please install them first."
    fi

    # Check Podman if not skipped
    if [[ "$SKIP_PODMAN" == false ]] && [[ "$INSTALL_MODE" == "cross-compile" ]]; then
        if ! command -v podman &> /dev/null; then
            error "Podman is required for cross-compilation. Install Podman or use --skip-podman."
        fi

        # Test Podman is working (Podman is daemonless, so just test basic functionality)
        if ! podman info &> /dev/null; then
            error "Podman is not working correctly. Please check your installation."
        fi
        
        success "Podman is installed and working (rootless mode)"
    fi

    # Check disk space (need at least 10GB for components, 25GB for full SDK build)
    local available_space=$(df . | awk 'NR==2 {print $4}')
    local required_space=$((10 * 1024 * 1024)) # 10GB in KB

    if [[ $available_space -lt $required_space ]]; then
        warn "Less than 10GB free space available. Installation may fail."
        warn "Available: $(($available_space / 1024 / 1024))GB, Recommended: 10GB+"
    fi

    success "Prerequisites check passed"
}

# Install system dependencies for native ARM64 (Orange Pi)
install_native_arm64_deps() {
    log "Installing system dependencies for native ARM64 development..."

    # Detect package manager
    if command -v apt &> /dev/null; then
        log "Using apt package manager..."
        sudo apt update
        sudo apt install -y \
            build-essential \
            cmake \
            git \
            wget \
            curl \
            gdb \
            libboost-all-dev \
            libopencv-dev \
            libturbojpeg-dev \
            libjpeg-turbo8-dev \
            libjpeg-turbo-progs \
            pkg-config \
            python3 \
            python3-pip
    else
        error "Unsupported package manager. This script requires apt (Debian/Ubuntu)."
    fi

    success "Native ARM64 dependencies installed"
}

# Install system dependencies for x86_64 cross-compilation
install_cross_compile_deps() {
    log "Installing system dependencies for x86_64 cross-compilation..."

    # Detect package manager
    if command -v apt &> /dev/null; then
        log "Using apt package manager..."
        sudo apt update
        sudo apt install -y \
            build-essential \
            cmake \
            git \
            wget \
            curl \
            podman \
            qemu-user-static \
            binfmt-support \
            pkg-config \
            python3 \
            python3-pip \
            jq
    else
        error "Unsupported package manager. This script requires apt (Debian/Ubuntu)."
    fi

    # Podman runs rootless by default - no group membership needed!
    # Verify Podman is working
    if command -v podman &> /dev/null; then
        if podman info &> /dev/null 2>&1; then
            success "Podman installed and working in rootless mode (no sudo required)"
        else
            warn "Podman installed but may need configuration. Try running: podman info"
        fi
    fi

    success "Cross-compilation dependencies installed"
}

# Clone or update RKNN Toolkit
setup_rknn_toolkit() {
    log "Setting up RKNN Toolkit ${RKNN_TOOLKIT_VERSION}..."

    mkdir -p toolkit

    # Clone or update rknn-toolkit2
    if [[ -d "toolkit/rknn-toolkit2" ]]; then
        log "RKNN Toolkit already exists, updating..."
        pushd toolkit/rknn-toolkit2 > /dev/null
        git fetch || warn "Failed to fetch updates"
        git checkout ${RKNN_TOOLKIT_VERSION} || warn "Failed to checkout ${RKNN_TOOLKIT_VERSION}"
        popd > /dev/null
    else
        log "Cloning RKNN Toolkit ${RKNN_TOOLKIT_VERSION}..."
        pushd toolkit > /dev/null
        git clone https://github.com/airockchip/rknn-toolkit2.git \
            --depth 1 --branch ${RKNN_TOOLKIT_VERSION} || error "Failed to clone rknn-toolkit2"
        popd > /dev/null
    fi

    success "RKNN Toolkit ${RKNN_TOOLKIT_VERSION} ready"
}

# Clone or update RKNN Model Zoo
setup_rknn_model_zoo() {
    log "Setting up RKNN Model Zoo ${RKNN_TOOLKIT_VERSION}..."

    mkdir -p toolkit

    # Clone or update rknn_model_zoo
    if [[ -d "toolkit/rknn_model_zoo" ]]; then
        log "RKNN Model Zoo already exists, updating..."
        pushd toolkit/rknn_model_zoo > /dev/null
        git fetch || warn "Failed to fetch updates"
        git checkout ${RKNN_TOOLKIT_VERSION} || warn "Failed to checkout ${RKNN_TOOLKIT_VERSION}"
        popd > /dev/null
    else
        log "Cloning RKNN Model Zoo ${RKNN_TOOLKIT_VERSION}..."
        pushd toolkit > /dev/null
        git clone https://github.com/airockchip/rknn_model_zoo.git \
            --depth 1 --branch ${RKNN_TOOLKIT_VERSION} || error "Failed to clone rknn_model_zoo"
        popd > /dev/null
    fi

    success "RKNN Model Zoo ${RKNN_TOOLKIT_VERSION} ready"
}

# Download YOLOX ONNX model
download_yolox_model() {
    log "Downloading YOLOX model..."

    local model_dir="toolkit/rknn_model_zoo/examples/yolox/model"

    if [[ ! -d "$model_dir" ]]; then
        error "Model directory not found: $model_dir. Run setup_rknn_model_zoo first."
    fi

    pushd "$model_dir" > /dev/null

    # Check if model already exists
    if [[ -f "yolox_s.onnx" ]]; then
        local size=$(stat -c%s "yolox_s.onnx" 2>/dev/null || stat -f%z "yolox_s.onnx" 2>/dev/null || echo 0)
        local min_size=$((10 * 1024 * 1024)) # 10MB

        if [[ $size -gt $min_size ]]; then
            success "YOLOX model already exists ($(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo ${size} bytes))"
            popd > /dev/null
            return 0
        else
            warn "YOLOX model exists but appears incomplete, re-downloading..."
        fi
    fi

    # Download using the provided script
    if [[ -f "download_model.sh" ]]; then
        chmod +x download_model.sh
        ./download_model.sh || error "Failed to download YOLOX model"
    else
        # Fallback: direct download
        log "Downloading YOLOX-s ONNX model directly..."
        wget -O yolox_s.onnx \
            "https://github.com/Megvii-BaseDetection/YOLOX/releases/download/0.1.1rc0/yolox_s.onnx" \
            || error "Failed to download YOLOX model"
    fi

    popd > /dev/null
    success "YOLOX model downloaded"
}

# Setup Podman container for RKNN Toolkit
setup_podman_container() {
    if [[ "$SKIP_PODMAN" == true ]]; then
        log "Skipping Podman container setup (--skip-podman specified)"
        return 0
    fi

    # Check architecture - RKNN toolkit only works on x86_64
    local arch=$(uname -m)
    if [[ "$arch" != "x86_64" ]]; then
        echo ""
        warn "═══════════════════════════════════════════════════════════"
        warn "IMPORTANT: RKNN Toolkit container requires x86_64 architecture"
        warn "Current architecture: $arch"
        warn ""
        warn "Model compilation (ONNX→RKNN) CANNOT be done on ARM64!"
        warn "The RKNN Python toolkit and container only work on x86_64."
        warn ""
        warn "Solution:"
        warn "  1. Run model compilation on an x86_64 machine"
        warn "  2. Transfer compiled models to this ARM64 machine"
        warn "  3. Use this ARM64 machine for native development/testing"
        warn ""
        warn "Skipping container build on ARM64..."
        warn "═══════════════════════════════════════════════════════════"
        echo ""
        return 0
    fi

    log "Setting up RKNN Toolkit Podman container..."

    local dockerfile_dir="toolkit/rknn-toolkit2/rknn-toolkit2/docker/docker_file/ubuntu_20_04_cp38"

    if [[ ! -d "$dockerfile_dir" ]]; then
        error "Dockerfile directory not found: $dockerfile_dir"
    fi

    pushd "$dockerfile_dir" > /dev/null

    # Check if Podman image already exists
    if podman images | grep -q "rknn_tk2"; then
        log "RKNN Toolkit container image already exists"
    else
        log "Building RKNN Toolkit Podman container (this may take 10-20 minutes)..."
        log "Note: Building with Podman in rootless mode (no sudo required)..."
        podman build --rm -t rknn_tk2 -f Dockerfile_ubuntu_20_04_for_cp38 . \
            || error "Failed to build RKNN Toolkit Podman container"
        
        success "Container image built successfully"
    fi

    popd > /dev/null
    success "RKNN Toolkit Podman container ready"
}

# Copy RKNN runtime libraries to include directory
setup_rknn_runtime_libs() {
    log "Setting up RKNN runtime libraries..."

    local src_lib_dir="toolkit/rknn-toolkit2/rknn-toolkit-lite2/runtime/Linux/librknn_api/aarch64"
    local dest_include_dir="${SCRIPT_DIR}/include"

    mkdir -p "$dest_include_dir"

    # Copy RKNN API headers
    if [[ -d "toolkit/rknn-toolkit2/rknn-toolkit-lite2/runtime/Linux/librknn_api/include" ]]; then
        cp -v toolkit/rknn-toolkit2/rknn-toolkit-lite2/runtime/Linux/librknn_api/include/*.h "$dest_include_dir/"
    fi

    # Copy RKNN runtime libraries
    if [[ -d "$src_lib_dir" ]]; then
        cp -v $src_lib_dir/librknnrt.so "$dest_include_dir/" 2>/dev/null || \
        cp -v $src_lib_dir/librknn_api.so "$dest_include_dir/" 2>/dev/null || \
        warn "Could not find RKNN runtime libraries in $src_lib_dir"
    fi

    success "RKNN runtime libraries set up"
}

# Create directory structure for models
setup_model_directories() {
    log "Creating model directory structure..."

    mkdir -p install/{RK3588,RK3568,RK3576}/model

    # Copy COCO labels
    local labels_src="toolkit/rknn_model_zoo/examples/yolox/model/coco_80_labels_list.txt"
    if [[ -f "$labels_src" ]]; then
        cp "$labels_src" install/RK3588/model/
        cp "$labels_src" install/RK3568/model/
        cp "$labels_src" install/RK3576/model/
    fi

    success "Model directories created"
}

# Print usage instructions
print_usage_instructions() {
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}  Rockchip NPU Components Installation Complete!${NC}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Components installed:"
    echo "  ✓ RKNN Toolkit ${RKNN_TOOLKIT_VERSION}"
    echo "  ✓ RKNN Model Zoo ${RKNN_TOOLKIT_VERSION}"
    echo "  ✓ YOLOX ONNX model"
    
    local arch=$(uname -m)
    if [[ "$arch" == "x86_64" ]] && [[ "$SKIP_PODMAN" == false ]]; then
        echo "  ✓ Podman container for model compilation (rootless mode)"
    fi
    
    echo ""
    echo "Next steps:"
    echo ""

    if [[ "$INSTALL_MODE" == "native-arm64" ]]; then
        echo "1. Compile models on an x86_64 machine first:"
        echo "   ${BLUE}./compile-models${NC}  (must be run on x86_64 with Podman)"
        echo ""
        echo "2. Copy compiled models to this ARM64 machine:"
        echo "   ${BLUE}scp -r x86-machine:/path/to/install/ .${NC}"
        echo ""
        echo "3. Build your C++ application:"
        echo "   ${BLUE}mkdir -p build && cd build${NC}"
        echo "   ${BLUE}cmake .. -DTARGET_SOC=rk3588${NC}"
        echo "   ${BLUE}make${NC}"
        echo ""
        echo "4. Run inference on a JPEG image:"
        echo "   ${BLUE}./build/object_detection_demo install/RK3588/model/yolox_s.rknn /path/to/image.jpg${NC}"
        echo ""
    else
        echo "1. Compile ONNX models to RKNN format:"
        echo "   ${BLUE}./compile-models${NC}  (uses Podman)"
        echo ""
        echo "2. Build the BrightSign SDK (if cross-compiling):"
        echo "   ${BLUE}./build --extract-sdk${NC}"
        echo "   ${BLUE}./brightsign-x86_64-cobra-toolchain-*.sh -d ./sdk -y${NC}"
        echo ""
        echo "3. Build your C++ application:"
        echo "   ${BLUE}./build-apps${NC}"
        echo ""
        echo "4. Package for deployment:"
        echo "   ${BLUE}./package${NC}"
        echo ""
    fi

    echo "For a simple command-line app that counts people in a JPEG:"
    echo "  - See the example in src/main.cpp"
    echo "  - Build with CMake as shown above"
    echo "  - Run: ${BLUE}./your_app install/RK3588/model/yolox_s.rknn input.jpg${NC}"
    echo ""
    echo "Podman Notes:"
    echo "  - This installation uses Podman (daemonless, rootless)"
    echo "  - Podman is compatible with Docker commands/images"
    echo "  - For existing Docker-based scripts, create alias:"
    echo "    ${BLUE}alias docker=podman${NC}"
    echo "  - Or use: ${BLUE}podman-docker${NC} package for automatic compatibility"
    echo ""
    echo "Documentation:"
    echo "  - README.md - Complete project documentation"
    echo "  - OrangePI_Development.md - Orange Pi development guide"
    echo "  - docs/DESIGN.md - Design documentation"
    echo "  - docs/X86_REQUIREMENTS.md - x86_64 requirements guide"
    echo ""
}

# Main installation function
main() {
    local start_time=$(date +%s)

    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  Rockchip NPU Components Installation Script${NC}"
    echo -e "${BLUE}  (Podman Edition - Daemonless & Rootless)${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════════${NC}"
    echo ""

    parse_args "$@"
    detect_platform
    check_prerequisites

    # Install dependencies based on platform
    if [[ "$INSTALL_MODE" == "native-arm64" ]]; then
        install_native_arm64_deps
    else
        install_cross_compile_deps
    fi

    # Setup RKNN components
    setup_rknn_toolkit
    setup_rknn_model_zoo

    if [[ "$SKIP_MODELS" == false ]]; then
        download_yolox_model
        setup_podman_container
        setup_model_directories
    fi

    setup_rknn_runtime_libs

    local end_time=$(date +%s)
    local duration=$(($end_time - $start_time))

    success "Installation completed in $(($duration / 60))m $(($duration % 60))s"

    print_usage_instructions
}

# Run main function
main "$@"
