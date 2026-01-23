// #ifndef CUDA_HASH_CUH
// #define CUDA_HASH_CUH
// #pragma once

// #include <cuda_runtime.h>
// #include <iostream>

// #define TABLE_SIZE 1024 * 1024  // 哈希表大小

// class cuda_hashTable_v2 {
// public:
//     long long key;

//     __device__ long long hash_pos(long long key) {
//         return key % TABLE_SIZE;  // 简单取模哈希函数
//     }

// };


// #endif