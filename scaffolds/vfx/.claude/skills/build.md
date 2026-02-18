# /build — Build the project

## Steps
1. Create build directory if needed: `mkdir -p build`
2. Configure: `cd build && cmake .. -G Ninja -DCMAKE_PREFIX_PATH=$CONDA_PREFIX`
3. Build: `cmake --build .`
4. Report success or failure with error details
