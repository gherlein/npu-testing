# x86_64 Computer Requirements

## Overview

Certain critical tasks in the Rockchip NPU development workflow **MUST** be performed on an x86_64 architecture computer. This is due to toolchain and Docker container compatibility restrictions.

## Architecture Requirement Summary

| Task | x86_64 Required | ARM64 Support | Why |
|------|----------------|---------------|-----|
| **Model Compilation (ONNX→RKNN)** | ✅ **REQUIRED** | ❌ Not supported | RKNN Python toolkit only runs on x86_64 |
| **BrightSign SDK Build** | ✅ **REQUIRED** | ❌ Not supported | OpenEmbedded BitBake requires x86_64 |
| **Cross-compilation for BrightSign** | ✅ **REQUIRED** | ❌ Not supported | SDK toolchain is x86_64 only |
| **Native development/testing** | ⚠️ Emulated only | ✅ **Preferred** | ARM64 runs natively on Orange Pi |

---

## 1. Model Compilation (ONNX → RKNN) - MANDATORY x86_64

### What it does:
Converts ONNX model files to RKNN format optimized for Rockchip NPU hardware.

### Commands:
```bash
# On x86_64 computer ONLY:
cd /path/to/project
./setup                  # Downloads toolkit, builds Docker container
./compile-models         # Compiles YOLOX model for all platforms
```

### Why x86_64 only:
- RKNN Toolkit 2 Python libraries are compiled for x86_64
- Docker container `rknn_tk2` is x86_64 based (Ubuntu 20.04 for x86_64)
- Cannot be run on ARM64 (Orange Pi) even with emulation

### Output files:
```
install/
├── RK3588/model/
│   ├── yolox_s.rknn              # Compiled model for RK3588
│   └── coco_80_labels_list.txt   # COCO class labels
├── RK3568/model/
│   ├── yolox_s.rknn              # Compiled model for RK3568
│   └── coco_80_labels_list.txt
└── RK3576/model/
    ├── yolox_s.rknn              # Compiled model for RK3576
    └── coco_80_labels_list.txt
```

### Docker container details:
- **Container name**: `rknn_tk2`
- **Base image**: Ubuntu 20.04 (x86_64)
- **Python version**: 3.8
- **Built by**: `./setup` script
- **Size**: ~2-3 GB

### Time required:
- First time (with Docker build): ~15-25 minutes
- Subsequent runs: ~3-5 minutes

---

## 2. BrightSign SDK Build - MANDATORY x86_64

### What it does:
Builds the OpenEmbedded cross-compilation SDK for BrightSign OS, which includes all necessary libraries and toolchains.

### Commands:
```bash
# On x86_64 computer ONLY:
cd /path/to/project
./setup                            # Sets up Docker environment
./build --extract-sdk               # Builds SDK (~30-45 min)

# Install the SDK (creates sdk/ directory)
./brightsign-x86_64-cobra-toolchain-9.1.52.sh -d ./sdk -y
```

### Why x86_64 only:
- OpenEmbedded BitBake build system requires x86_64
- BrightSign OS SDK is packaged as x86_64 installer
- Docker build environment is x86_64 based

### What gets built:
- **Cross-compiler**: `aarch64-oe-linux-gcc` (ARM64 target)
- **Libraries**: OpenCV, Boost, TurboJPEG, RGA, RKNN runtime
- **Headers**: All development headers for BrightSign OS
- **CMake toolchain**: For cross-compilation

### SDK directory structure:
```
sdk/
├── environment-setup-aarch64-oe-linux   # Environment script
├── sysroots/
│   ├── aarch64-oe-linux/                # Target platform files
│   │   ├── usr/include/                 # Headers (OpenCV, Boost, etc.)
│   │   └── usr/lib/                     # Libraries (.so files)
│   └── x86_64-oesdk-linux/              # Host toolchain
│       └── usr/bin/                     # Cross-compiler binaries
└── version-*                            # SDK version info
```

### Time required:
- First build: ~30-45 minutes
- Disk space: ~20-25 GB (downloads BrightSign OS source)

---

## 3. Cross-Compilation - MANDATORY x86_64

### What it does:
Compiles C++ application for BrightSign players using the SDK cross-compiler.

### Commands:
```bash
# On x86_64 computer ONLY:
# Ensure SDK is installed first (see step 2)
./build-apps              # Builds for all platforms
./build-apps XT5          # Builds only for XT5/RK3588
```

### Why x86_64 only:
- Requires SDK installed (which is x86_64 only)
- Uses `aarch64-oe-linux-gcc` cross-compiler from SDK
- CMake toolchain files expect x86_64 host

### Build process:
```bash
# The script internally does:
source sdk/environment-setup-aarch64-oe-linux
cmake .. -DOECORE_TARGET_SYSROOT="${OECORE_TARGET_SYSROOT}" -DTARGET_SOC=rk3588
make -j$(nproc)
make install
```

### Output:
```
build_xt5/
├── object_detection_demo     # Executable (ARM64)
├── librknnrt.so              # RKNN runtime
├── librga.so                 # RGA library
└── model/                    # Model files

install/RK3588/
├── object_detection_demo     # Installed executable
├── lib/                      # Required libraries
└── model/                    # Model files
```

### Time required:
- Clean build: ~3-8 minutes per platform
- Incremental build: ~1-2 minutes

---

## 4. Complete Workflow on x86_64

### One-time setup (run once):
```bash
# Install the Rockchip components
./install_rockchip_components.sh

# Or manually:
./setup                            # 5-10 min
./compile-models                   # 3-5 min
./build --extract-sdk              # 30-45 min
./brightsign-x86_64-*.sh -d ./sdk -y  # 1 min
```

### Development iteration (repeat as needed):
```bash
# Edit C++ source code
nano src/main.cpp

# Rebuild application
./build-apps                       # 3-8 min

# Package for deployment
./package                          # 1 min
```

### Transfer to target device:
```bash
# Copy to BrightSign player or Orange Pi for testing
scp -r install/RK3588/* user@device:/path/to/app/
```

---

## 5. What CAN be done on ARM64 (Orange Pi)

While model compilation and cross-compilation require x86_64, you **CAN** develop natively on ARM64:

### Native ARM64 workflow:
```bash
# On ARM64 (Orange Pi):
# 1. Install dependencies
sudo apt install -y cmake build-essential libopencv-dev \
    libboost-all-dev libturbojpeg-dev

# 2. Copy pre-compiled models from x86_64 machine
# (Models must be compiled on x86_64 first!)
scp -r user@x86machine:/path/to/install/ .

# 3. Build natively
mkdir build && cd build
cmake .. -DTARGET_SOC=rk3588
make

# 4. Run inference
./object_detection_demo ../install/RK3588/model/yolox_s.rknn image.jpg
```

### Benefits of ARM64 development:
- **Faster builds**: Native compilation vs cross-compilation
- **Better debugging**: Full GDB, valgrind, perf support
- **Real hardware**: Test on actual NPU hardware
- **Rapid iteration**: No Docker overhead

### Limitations:
- **Cannot compile models**: ONNX→RKNN requires x86_64
- **Not for production**: BrightSign deployment requires SDK build

---

## 6. System Requirements for x86_64 Machine

### Hardware:
- **Architecture**: x86_64 (Intel or AMD)
- **RAM**: 16GB+ recommended (8GB minimum)
- **Disk**: 30GB+ free space
- **CPU**: Multi-core recommended (parallel builds)

### Software:
- **OS**: Linux (Ubuntu 20.04+ recommended) or WSL2 on Windows
- **Docker**: Docker CE 20.10+
- **Git**: 2.25+
- **CMake**: 3.10+
- **wget, tar, curl**: For downloads

### Not supported:
- ❌ **Apple Silicon (M1/M2/M3)**: ARM64 architecture
- ❌ **ARM-based cloud instances**: Wrong architecture
- ❌ **32-bit x86**: Only x86_64 supported

---

## 7. Verification Checklist

### Before starting:
- [ ] Confirm architecture: `uname -m` returns `x86_64`
- [ ] Docker installed: `docker --version`
- [ ] Docker running: `docker info`
- [ ] Sufficient disk space: `df -h .` (need 30GB+)
- [ ] Git configured: `git --version`

### After setup:
- [ ] Docker image built: `docker images | grep rknn_tk2`
- [ ] Models compiled: `ls install/RK3588/model/yolox_s.rknn`
- [ ] SDK installed: `ls sdk/environment-setup-aarch64-oe-linux`
- [ ] App built: `ls build_xt5/object_detection_demo`

---

## 8. Common Issues

### Issue: "Docker daemon not running"
```bash
# Linux:
sudo systemctl start docker

# Verify:
docker info
```

### Issue: "Permission denied" for Docker
```bash
# Add user to docker group:
sudo usermod -aG docker $USER

# Log out and back in, then verify:
groups | grep docker
```

### Issue: "Out of disk space" during SDK build
```bash
# Check space:
df -h .

# Clean Docker if needed:
docker system prune -a

# Need at least 30GB free
```

### Issue: "Architecture not supported"
```bash
# Verify you're on x86_64:
uname -m

# Should output: x86_64
# If it outputs: aarch64, arm64, etc. - you need x86_64 machine
```

---

## 9. Hybrid Development Workflow

### Recommended approach:
```
┌─────────────────────────────┐
│   x86_64 Development Host   │
│                             │
│ 1. Compile models (ONNX→RKNN)
│ 2. Build BrightSign SDK     │
│ 3. Cross-compile apps       │
│ 4. Package for deployment   │
└──────────────┬──────────────┘
               │
               ├─────────────────────────────────────┐
               │                                     │
               ▼                                     ▼
    ┌──────────────────────┐          ┌──────────────────────┐
    │  Orange Pi (ARM64)   │          │  BrightSign Player   │
    │  Development/Test    │          │  Production Deploy   │
    │                      │          │                      │
    │ • Native builds      │          │ • Final validation   │
    │ • Fast iteration     │          │ • Production use     │
    │ • NPU testing        │          │                      │
    │ • Pre-compiled models│          │ • Pre-compiled models│
    └──────────────────────┘          └──────────────────────┘
```

### Workflow steps:
1. **x86_64**: Compile models, build SDK (one-time)
2. **x86_64**: Cross-compile application
3. **Orange Pi**: Native build + test (rapid iteration)
4. **x86_64**: Final cross-compile when ready
5. **BrightSign**: Deploy and validate

---

## 10. Summary: What Requires x86_64

### Absolutely requires x86_64 (cannot be done elsewhere):
1. ✅ **Model compilation** (ONNX → RKNN)
2. ✅ **BrightSign SDK build**
3. ✅ **Cross-compilation for BrightSign**

### Can be done on ARM64 (Orange Pi):
1. ✅ **Native development**
2. ✅ **Application testing**
3. ✅ **NPU inference** (with pre-compiled models)

### Installed by `install_rockchip_components.sh`:
On **x86_64**:
- RKNN Toolkit (x86_64 Docker container)
- Model Zoo repositories
- Docker dependencies
- Build tools

On **ARM64**:
- System dependencies (CMake, OpenCV, Boost)
- RKNN Toolkit repositories (for headers/libs)
- Native build tools

---

## Quick Reference

```bash
# On x86_64 - MANDATORY STEPS:
./install_rockchip_components.sh --cross-compile
./compile-models        # MUST run on x86_64
./build --extract-sdk   # MUST run on x86_64
./brightsign-x86_64-*.sh -d ./sdk -y
./build-apps            # MUST run on x86_64

# On ARM64 (Orange Pi) - OPTIONAL for fast development:
./install_rockchip_components.sh --native-arm64
# Copy models from x86_64 machine
mkdir build && cd build
cmake .. -DTARGET_SOC=rk3588
make
```
