#!/bin/bash

# =========================================================
# ROCm High-Precision Benchmark Suite
# =========================================================

# Ensure environment is set (in case it wasn't loaded from bashrc yet)
export HSA_OVERRIDE_GFX_VERSION=10.1.0

# 1. Generate C++ Source
cat <<EOF > benchmark_precise.cpp
#include <hip/hip_runtime.h>
#include <iostream>
#include <vector>
#include <chrono>
#include <cstdlib>
#include <iomanip>
#include <unistd.h>

void cpuAdd(const float *a, const float *b, float *c, int n) {
    for (int i = 0; i < n; i++) c[i] = a[i] + b[i];
}

__global__ void gpuAdd(const float *a, const float *b, float *c, int n) {
    int i = blockDim.x * blockIdx.x + threadIdx.x;
    if (i < n) c[i] = a[i] + b[i];
}

int main(int argc, char* argv[]) {
    if (argc < 3) return 1;
    int N = std::atoi(argv[1]);
    int iterations = std::atoi(argv[2]);

    size_t bytes = N * sizeof(float);
    std::vector<float> h_a(N, 1.0f), h_b(N, 2.0f), h_c(N);
    float *d_a, *d_b, *d_c;
    
    // Alloc
    hipMalloc(&d_a, bytes); 
    hipMalloc(&d_b, bytes); 
    hipMalloc(&d_c, bytes);
    
    // Copy (Setup cost, not measured)
    hipMemcpy(d_a, h_a.data(), bytes, hipMemcpyHostToDevice);
    hipMemcpy(d_b, h_b.data(), bytes, hipMemcpyHostToDevice);

    // --- CPU BENCHMARK ---
    double cpu_total = 0.0;
    for(int i=0; i<iterations; i++) {
        auto start = std::chrono::high_resolution_clock::now();
        cpuAdd(h_a.data(), h_b.data(), h_c.data(), N);
        auto end = std::chrono::high_resolution_clock::now();
        cpu_total += std::chrono::duration<double, std::micro>(end - start).count();
    }
    double cpu_avg = cpu_total / iterations;

    // --- GPU BENCHMARK ---
    double gpu_total = 0.0;
    int blockSize = 256;
    int gridSize = (N + blockSize - 1) / blockSize;
    
    // Hard Warmup (2 runs to settle scheduler)
    hipLaunchKernelGGL(gpuAdd, dim3(gridSize), dim3(blockSize), 0, 0, d_a, d_b, d_c, N);
    hipDeviceSynchronize();
    hipLaunchKernelGGL(gpuAdd, dim3(gridSize), dim3(blockSize), 0, 0, d_a, d_b, d_c, N);
    hipDeviceSynchronize();

    for(int i=0; i<iterations; i++) {
        auto start = std::chrono::high_resolution_clock::now();
        
        hipLaunchKernelGGL(gpuAdd, dim3(gridSize), dim3(blockSize), 0, 0, d_a, d_b, d_c, N);
        hipDeviceSynchronize(); // Vital for accurate timing
        
        auto end = std::chrono::high_resolution_clock::now();
        gpu_total += std::chrono::duration<double, std::micro>(end - start).count();
    }
    double gpu_avg = gpu_total / iterations;

    // Output strictly formatted for bash parsing
    std::cout << "DATA:" << cpu_avg << ":" << gpu_avg << std::endl;

    hipFree(d_a); hipFree(d_b); hipFree(d_c);
    return 0;
}
EOF

# 2. Compile
# Check if binary exists to save time, remove it if you want to force recompile
if [ ! -f benchmark_precise ]; then
    echo ">>> Compiling Benchmark..."
    /opt/rocm/bin/hipcc --offload-arch=gfx1010 benchmark_precise.cpp -o benchmark_precise
fi

# 3. Initialize Variables
CPU_POINTS=""
GPU_POINTS=""
ITERATIONS=50
POINTS_PER_DECADE=15

# Print Header
echo "--------------------------------------------------------------------------------"
printf "%-12s | %-12s | %-15s | %-15s | %-10s\n" "Size" "Iters" "CPU (us)" "GPU (us)" "Winner"
echo "--------------------------------------------------------------------------------"

# 4. Run Loop
# We iterate decades: 10, 100, 1000...
for BASE in 10 100 1000 10000 100000 1000000; do
    
    # Calculate step size to get ~15 points in this decade
    STEP=$(( (9 * BASE) / POINTS_PER_DECADE ))
    if [ "$STEP" -lt 1 ]; then STEP=1; fi

    # Run sub-steps
    for (( i=0; i<POINTS_PER_DECADE; i++ )); do
        # Calculate current size
        SIZE=$(( BASE + (i * STEP) ))
        
        # Hard Stop at 10M
        if [ "$SIZE" -gt 10000000 ]; then break; fi

        # Run Test
        OUTPUT=$(./benchmark_precise $SIZE $ITERATIONS)
        
        # Parse Output
        DATALINE=$(echo "$OUTPUT" | grep "DATA:")
        CPU_TIME=$(echo $DATALINE | cut -d':' -f2)
        GPU_TIME=$(echo $DATALINE | cut -d':' -f3)

        # Determine Winner
        WINNER="CPU"
        IS_GPU_FASTER=$(echo "$GPU_TIME < $CPU_TIME" | bc -l)
        if [ "$IS_GPU_FASTER" -eq 1 ]; then
            WINNER="GPU"
        fi

        # Pretty Print Table (Fixed the formatting issue here)
        LC_NUMERIC=C printf "%-12d | %-12d | %-15.3f | %-15.3f | %-10s\n" \
            "$SIZE" "$ITERATIONS" "$CPU_TIME" "$GPU_TIME" "$WINNER"

        # Accumulate Data Points
        CPU_POINTS+="( $SIZE, $CPU_TIME ) "
        GPU_POINTS+="( $SIZE, $GPU_TIME ) "

        # Relax system
        sleep 0.1
    done
done

# Ensure we capture the exact 10M point
if [ "$SIZE" -lt 10000000 ]; then
    SIZE=10000000
    OUTPUT=$(./benchmark_precise $SIZE $ITERATIONS)
    DATALINE=$(echo "$OUTPUT" | grep "DATA:")
    CPU_TIME=$(echo $DATALINE | cut -d':' -f2)
    GPU_TIME=$(echo $DATALINE | cut -d':' -f3)
    WINNER="GPU"
    LC_NUMERIC=C printf "%-12d | %-12d | %-15.3f | %-15.3f | %-10s\n" "$SIZE" "$ITERATIONS" "$CPU_TIME" "$GPU_TIME" "$WINNER"
    CPU_POINTS+="( $SIZE, $CPU_TIME ) "
    GPU_POINTS+="( $SIZE, $GPU_TIME ) "
fi

echo "--------------------------------------------------------------------------------"
echo ""
echo ">>> CPU DATA POINTS:"
echo "$CPU_POINTS"
echo ""
echo ">>> GPU DATA POINTS:"
echo "$GPU_POINTS"
echo "--------------------------------------------------------------------------------"