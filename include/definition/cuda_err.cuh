#ifndef CUDA_ERR_H
#define CUDA_ERR_H
#pragma once

#include <cuda_runtime.h>
#include <stdio.h>
#include <stdlib.h>

static inline void checkKernelLaunchImpl(const char* file, int line, const char* kernelName = nullptr) {
    cudaError_t err = cudaGetLastError();
    if (err != cudaSuccess) {
        if (kernelName) {
            fprintf(stderr, "CUDA kernel launch error in %s:%d\n", file, line);
            fprintf(stderr, "  Kernel: %s\n", kernelName);
        } else {
            fprintf(stderr, "CUDA kernel launch error in %s:%d\n", file, line);
        }
        fprintf(stderr, "  Error: %s\n", cudaGetErrorString(err));
        exit(EXIT_FAILURE);
    }
}

#define CHECK_CUDA_KERNEL() \
    checkKernelLaunchImpl(__FILE__, __LINE__)

#endif