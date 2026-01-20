# AWS G4ad ROCm Setup & Benchmark

This project provides a turnkey solution for setting up **AMD ROCm 5.7** drivers on **AWS EC2 G4ad** instances (AMD Radeon Pro V520). It includes an automated setup script to handle the specific kernel overrides required for the `gfx1011` architecture and a high-precision benchmark suite to compare CPU vs. GPU performance.

## Overview

Running ROCm on AWS G4ad instances is historically difficult because the Radeon Pro V520 is an RDNA1 card that requires specific environment overrides and kernel headers to function correctly. This project automates the fix and proves the performance gain.

This project demonstrates:
*   **Automated Recovery:** Fixes broken driver states and installs AWS-specific kernel modules.
*   **Architecture Overrides:** Automatically forces `HSA_OVERRIDE_GFX_VERSION=10.1.0` for compatibility.
*   **High-Precision Benchmarking:** Compares vector addition ($C = A + B$) on CPU vs. GPU across varying array sizes.

## Files

| File | Description |
| :--- | :--- |
| `setup_rocm.sh` | The installation script. It removes conflicting drivers, installs ROCm 5.7 without DKMS, fixes permissions, and applies the necessary architecture workarounds. |
| `rocm_benchmark.sh` | A C++ based benchmark suite. It runs 50 iterations per data point, ranging from 10 to 10,000,000 elements, to visualize the latency crossover point between CPU and GPU. |

## Demo

Below are examples of the benchmark running on a g4ad.xlarge instance.

<div align="center">

<img width="1000" height="537" alt="img1" src="https://github.com/user-attachments/assets/626a4f1d-46c4-43b0-a951-6ee47adade56" />
<img width="1000" height="858" alt="img2" src="https://github.com/user-attachments/assets/863fe79d-1571-4638-be63-c7c1f18a1806" />

</div>

## Prerequisites

*   **Instance Type:** AWS EC2 `g4ad.xlarge` (or larger).
*   **OS:** Ubuntu 22.04 LTS (x86_64).
*   **Storage:** At least 50GB gp3 (ROCm is large).

## Installation

### 1. Run the Setup Script
This script installs the necessary AWS kernel headers, `libstdc++-12-dev`, and the ROCm runtime. It handles the removal of broken `amdgpu-dkms` modules if they exist.

```bash
chmod +x setup_rocm.sh
./setup_rocm.sh
```

> [!IMPORTANT]
> **Reboot Required**
> After the setup script finishes, you **must** reboot the instance for the user permissions and driver overrides to take effect.
> ```bash
> sudo reboot
> ```

## Usage

### Run the Benchmark
Once the instance is back online, run the benchmark suite. It compiles the test binary on the fly and executes the suite.

```bash
chmod +x rocm_benchmark.sh
./rocm_benchmark.sh
```

## Performance Analysis

The benchmark performs Vector Addition on array sizes ranging from **10** to **10,000,000** elements. It runs **50 iterations** per size to smooth out OS jitter.

### 1. Startup Latency (Small Data)
For small arrays (< 80,000 elements), the **CPU is significantly faster**.
*   **Reason:** Moving data across the PCIe bus and the overhead of launching a GPU kernel takes a fixed amount of time (approx. 15-20 microseconds). The CPU can finish the math before the GPU even starts.

### 2. The Crossover Point
At approximately **82,000 elements**, the sheer parallel power of the GPU overcomes the startup latency.
*   **CPU Time:** ~18.3 µs
*   **GPU Time:** ~18.1 µs

### 3. Massive Scaling (Large Data)
Once the data size exceeds 1 Million, the GPU becomes exponentially more efficient.
*   At **10 Million elements**, the GPU is over **14x faster** than the CPU.

| Size | CPU Time | GPU Time | Speedup |
| :--- | :--- | :--- | :--- |
| 1,000 | 0.14 us | 15.70 us | CPU Win |
| 82,000 | 18.30 us | 18.10 us | **Crossover** |
| 1,000,000 | 207.12 us | 44.46 us | **4.6x** |
| 10,000,000 | 4570.06 us | 313.79 us | **14.5x** |

## Sample Output

```text
--------------------------------------------------------------------------------
Size         | Iters        | CPU (us)        | GPU (us)        | Winner
--------------------------------------------------------------------------------
...
70000        | 50           | 15.195          | 17.957          | CPU
76000        | 50           | 16.895          | 18.032          | CPU
82000        | 50           | 18.306          | 18.109          | GPU
88000        | 50           | 19.462          | 28.224          | CPU
94000        | 50           | 23.285          | 18.395          | GPU
100000       | 50           | 21.107          | 17.800          | GPU
...
1000000      | 50           | 207.121         | 44.467          | GPU
...
10000000     | 50           | 4570.060        | 313.790         | GPU
--------------------------------------------------------------------------------
```
