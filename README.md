# AWS G4ad ROCm Setup & Benchmark

[![License](https://img.shields.io/badge/license-MIT-green.svg)](./LICENSE)
[![Platform](https://img.shields.io/badge/platform-AWS%20EC2%20G4ad-orange.svg)](https://aws.amazon.com/ec2/instance-types/g4/)
[![GPU](https://img.shields.io/badge/GPU-Radeon%20Pro%20V520-red.svg)](https://www.amd.com/en/graphics/workstations)
[![ROCm](https://img.shields.io/badge/ROCm-5.7-blue.svg)](https://rocm.docs.amd.com/)
[![OS](https://img.shields.io/badge/OS-Ubuntu%2022.04-purple.svg)](https://releases.ubuntu.com/jammy/)

This repository contains scripts to install AMD ROCm 5.7 drivers and run compute benchmarks on AWS EC2 G4ad instances (AMD Radeon Pro V520).

## Overview

The Radeon Pro V520 is based on the RDNA1 architecture (`gfx1011`). Official ROCm support for this architecture is limited, often requiring environment overrides (`HSA_OVERRIDE_GFX_VERSION`) and specific kernel headers to function on AWS.

This project automates the installation of these dependencies and provides a benchmark utility to verify the environment by comparing CPU and GPU execution times for vector addition.

## Files

| File | Description |
| :--- | :--- |
| `examples.log` | Contains the full execution transcript of the ROCm setup and validation process, serving as a diagnostic record to verify that the AMD GPU environment is correctly configured. |
| `setup_rocm.sh` | Installs AWS-specific kernel modules, removes conflicting `amdgpu-dkms` drivers, installs the ROCm 5.7 runtime, and configures the necessary environment variables. |
| `rocm_benchmark.sh` | A C++ HIP benchmark suite. It compiles a vector addition program and runs it against array sizes ranging from 10 to 10,000,000 elements to measure latency and throughput. |

## Demo

**Benchmark output on g4ad.xlarge:**

<div align="center">

<img width="1000" alt="img1" src="https://github.com/user-attachments/assets/626a4f1d-46c4-43b0-a951-6ee47adade56" />
<img width="1000" alt="img2" src="https://github.com/user-attachments/assets/863fe79d-1571-4638-be63-c7c1f18a1806" />

</div>

## Prerequisites

*   **Instance Type:** AWS EC2 `g4ad.xlarge` or larger.
*   **OS:** Ubuntu 22.04 LTS (x86_64).
*   **Storage:** Minimum 50GB (Recommended for ROCm dependencies).

## Installation

### 1. Run the Setup Script
Execute the script to update the system, install headers, and setup the drivers.

```bash
chmod +x setup_rocm.sh
./setup_rocm.sh
```

> [!IMPORTANT]
> **Reboot Required**
> A reboot is necessary for the user group permissions (`render`, `video`) and environment variables to apply correctly.
> ```bash
> sudo reboot
> ```

## Usage

### Run the Benchmark
After rebooting, run the benchmark script. This will compile the C++ source and execute the tests.

```bash
chmod +x rocm_benchmark.sh
./rocm_benchmark.sh
```

## Performance Data

The benchmark runs 50 iterations per data point to measure the execution time of Vector Addition ($C = A + B$) on both CPU and GPU.

### Latency vs Throughput
*   **Small Data (< 80k elements):** The CPU is faster due to the overhead associated with PCIe data transfer and GPU kernel launching (approx. 15-20 µs).
*   **Crossover Point:** At roughly **82,000 elements**, the GPU parallelization outweighs the startup overhead.
*   **Large Data (> 1M elements):** The GPU processes data significantly faster than the CPU.

| Size | CPU Time | GPU Time | Note |
| :--- | :--- | :--- | :--- |
| 1,000 | 0.14 us | 15.70 us | Latency dominated |
| 82,000 | 18.30 us | 18.10 us | **Crossover point** |
| 1,000,000 | 207.12 us | 44.46 us | 4.6x Speedup |
| 10,000,000 | 4570.06 us | 313.79 us | 14.5x Speedup |

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
...
1000000      | 50           | 207.121         | 44.467          | GPU
...
10000000     | 50           | 4570.060        | 313.790         | GPU
--------------------------------------------------------------------------------
```
