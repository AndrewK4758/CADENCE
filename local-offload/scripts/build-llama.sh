#!/usr/bin/env bash
# ==============================================================================
# build-llama.sh
#
# Automated CUDA build and installation script for llama.cpp
# Optimized for NVIDIA GeForce RTX 5070 Ti (Blackwell / compute 120a)
# Builds and installs binaries to /usr/local/bin and libraries to /usr/local/lib
# ==============================================================================

set -euo pipefail

LLAMA_DIR="${HOME}/projects/llama.cpp"
BUILD_DIR="${LLAMA_DIR}/build"

echo -e "\033[1;36m=== Building llama.cpp with CUDA for RTX 5070 Ti ===\033[0m"

# 1. Stop any running server instance to prevent "Text file busy"
echo -e "\n\033[1;33m[1/5] Stopping any active llama-server instances...\033[0m"
killall -9 llama-server 2>/dev/null || true

# 2. Configure CMake with CUDA enabled and native architecture targeting
echo -e "\n\033[1;33m[2/5] Configuring CMake with CUDA & native Blackwell architecture (120a)...\033[0m"
cmake -B "${BUILD_DIR}" -S "${LLAMA_DIR}" \
    -DGGML_CUDA=ON \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES=native \
    -DGGML_CUDA_FA=ON \
    -DCMAKE_INSTALL_PREFIX=/usr/local

# 3. Compile across all CPU cores
echo -e "\n\033[1;33m[3/5] Compiling with $(nproc) threads...\033[0m"
cmake --build "${BUILD_DIR}" --config Release -j "$(nproc)"

# 4. Install binaries and shared libraries to /usr/local
echo -e "\n\033[1;33m[4/5] Installing to /usr/local (requires sudo)...\033[0m"
sudo cmake --install "${BUILD_DIR}" --prefix /usr/local

# 5. Ensure /usr/local/lib is registered with the system dynamic linker
echo -e "\n\033[1;33m[5/5] Updating ldconfig cache for /usr/local/lib...\033[0m"
echo "/usr/local/lib" | sudo tee /etc/ld.so.conf.d/local.conf > /dev/null
sudo ldconfig

echo -e "\n\033[1;32m=== Build and Installation Completed Successfully! ===\033[0m"
echo -e "Verifying installed CUDA binary:"
/usr/local/bin/llama-cli --version
/usr/local/bin/llama-cli --list-devices
