#!/bin/bash

# run this script from the root of the caelestia repo to build and install the latest version of caelestia (when cpp files changed)
cd ~/.config/quickshell/caelestia

# 1. Wipe old build (avoids stale CMake cache + old .so files)
rm -rf build

# 2. Configure with the correct prefix
cmake -B build -S . -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/

# 3. Build
cmake --build build -j$(nproc) #-j is the number of parallel jobs to run, $(nproc) returns the number of available CPU cores

# 4. Install to /usr
sudo cmake --install build