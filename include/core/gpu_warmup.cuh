#ifndef GPU_WARMUP_CUH
#define GPU_WARMUP_CUH
#pragma once

#include <cuda_runtime.h>

__global__ void gpu_warmup_kernel(float* dummy, int iterations) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    float sum = 0.0f;
    for (int i = 0; i < iterations; ++i) sum += sqrtf(float(idx) + 0.1f) * cosf(float(i) * 0.5f);
    if (dummy) dummy[idx] = sum;
}

inline void gpu_warmup() {
    const int num_threads = 256, num_blocks = 256, iterations = 100;
    float* d_dummy;
    cudaMalloc(&d_dummy, num_threads * num_blocks * sizeof(float));
    gpu_warmup_kernel<<<num_blocks, num_threads>>>(d_dummy, iterations);
    cudaDeviceSynchronize();
    cudaFree(d_dummy);
}

#endif
