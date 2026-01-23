// #pragma once

// #include "label/gen_label.cuh"
// #include "cub/cub.cuh"
// #include <cuda_runtime.h>

// typedef size_t SIZE_TYPE;
// const int MAX_BLOCKS_NUM = 96 * 8;
// #define FULL_MASK 0xffffffff
// const uint64_t mask = 0x3FFULL;
// #define CALC_BLOCKS_NUM(ITEMS_PER_BLOCK, CALC_SIZE) min(MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
// #define CALC_BLOCKS_NUM_LL(ITEMS_PER_BLOCK, CALC_SIZE) min((long long)MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
// #define CALC_BLOCKS_NUM_NOLIMIT(ITEMS_PER_BLOCK, CALC_SIZE) ((CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)

// // 64bits, to_vertex 24bits, hub_vertex 24bits, hop 3bits, distance 10bits
// // __forceinline__ __host__ __device__ int get_to_vertex (long long x) {
// //     return ((x >> 37) & 0xFFFFFF);
// // }
// // __forceinline__ __host__ __device__ int get_hub_vertex (long long x) {
// //     return ((x >> 13) & 0xFFFFFF); // 24-bit mask
// // }
// // __forceinline__ __host__ __device__ int get_hop (long long x) {
// //     return ((x >> 10) & 0x7); // 3-bit mask
// // }
// // __forceinline__ __host__ __device__ int get_distance (long long x) {
// //     return (x & 0x3FF); // 10-bit mask
// // }
// // __forceinline__ __host__ __device__ long long get_label (int to_vertex, int hub_vertex, int hop, int distance) {
// //     return ((long long)(to_vertex) << 37) | ((long long)(hub_vertex) << 13) | (hop << 10) | (distance);
// // }
// __forceinline__ __device__ int hash_pos (long long x) {
//     return x % TABLE_SIZE;
// }
// __forceinline__ __device__ int hash_pos_2 (long long x) {
//     return x % MOD;
// }
// __forceinline__ __device__ int hash_52_to_30(uint64_t input) {
//     // input *= (input >> 24);
//     // input *= 0x9E3779B97F4A7C15ULL;
//     // input ^= input << 30;
//     // input *= 0xbf58476d1ce4e5b9LL;
//     // input ^= input >> 27;
//     // input *= 0x94d049bb133111ebLL;
//     // input ^= input << 31;
//     // return (input >> 22) & 0x3FFFFFFF;
//     return input % TABLE_SIZE;
// }
// __forceinline__ __device__ int hash_52_to_22(uint64_t input) {
//     // input *= (input >> 24);
//     // input *= 0xc6a4b3b5d82bc2c9ULL;
//     // input ^= (input >> 3) * 0x1B873593;  // 右移29位，乘以质数0x1B873593
//     // input ^= (input << 17) * 0x4C190623;  // 左移17位，乘以质数0x4C190623
//     // input ^= (input >> 32) * 0x82E7E515;  // 右移32位，乘以质数0x82E7E515
//     // input ^= (input << 11) * 0x5BD1E995;  // 左移11位，乘以质数0x5BD1E995
//     // return (input >> 25) & 0x003FFFFF;
//     return input % MOD;
// }

// __device__ void insertKernel_has (long long* d_table, long long d_input) {
//     long long pos = hash_pos(d_input & (~0ull << 10));
//     // long long key = hash_pos_2(d_input & (~0ull << 10));
//     // key = (key << 10) | (d_input & 0x3FF);
//     // long long pos = hash_pos(d_input >> 10);
//     // long long key = hash_52_to_22(d_input >> 13);
//     // printf("%d, %lld\n", pos, key);
//     long long old;
//     // if (key == 1834131525) {
//     //     printf("shit!!!!!!!! %lld, %lld\n", (d_input & (~0ull << 10)), pos);
//     // }
//     // if (key == 1834131591) {
//     //     printf("shit!!!!!!!! %lld, %lld\n", (d_input & (~0ull << 10)), pos);
//     // }
//     // Hash1: 8556262057579731, 8556262057579520, 252267090, 1221919
//     // Hash2: 1834131591, 1834131456, 835887103, 1221919
//     // Pos: 252267192
//     while (true) {
//         old = d_table[pos];
//         if (old == 0) {
//             long long expected = 0;
//             if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
//                 break;
//             }
//             // long long expected = 0;
//             // if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&key) == *(unsigned long long*)&expected) {
//             //     break;
//             // }
//         } else {
//             if ((old >> 10) == (d_input >> 10)) {
//                 d_table[pos] = d_input;
//                 return;
//             }
//             // if ((old >> 10) == (key >> 10)) {
//             //     d_table[pos] = key;
//             //     return;
//             // }
//             // if (hash_pos_2(d_input & (~0ull << 10)) == (old >> (~0ull << 10))) {
//             //     printf("Same Label:\nLabel1:%d, %d, %d, %d\nLabel2:%d, %d, %d, %d\n",
//             //     get_to_vertex(d_input), get_hub_vertex(d_input), get_hop(d_input), get_distance(d_input),
//             //     get_to_vertex(old), get_hub_vertex(old), get_hop(old), get_distance(old));
//             //     printf("Hash1: %lld, %lld, %d, %d\nHash2: %lld, %lld, %d, %d\nPos: %lld\n", 
//             //     d_input, (d_input & (~0ull << 10)), hash_pos(d_input & (~0ull << 10)), hash_pos_2(d_input & (~0ull << 10))
//             //     , old, (old & (~0ull << 10)), hash_pos(old & (~0ull << 10)), hash_pos_2(old & (~0ull << 10))
//             //     , pos);
//             //     printf("Hash1: %d\nHash2: %d\n", hash_pos_2(d_input & (~0ull << 10)), hash_pos_2(old & (~0ull << 10)));
//             // }
//             // pos = (pos + 1) % TABLE_SIZE;
//             pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//         }
//     }
// }

// __device__ bool insertKernel_das (long long *d_table, long long d_input) {
//     // long long pos = hash_pos(d_input & (~0ull << 10));
//     long long pos = hash_pos(d_input & (~0ull << 10));
//     // long long key = hash_pos_2(d_input & (~0ull << 10));
//     // int pos = hash_52_to_30(d_input >> 10);
//     // long long key = hash_52_to_22(d_input >> 13);
//     // key = (key << 10) | (d_input & 0x3FF);
//     long long old;
//     while (true) {
//         old = d_table[pos];
//         if (old == 0) {
//             long long expected = 0;
//             if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
//                 return 1;
//             }
//             // long long expected = 0;
//             // if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&key) == *(unsigned long long*)&expected) {
//             //     return 1;
//             // }
//         } else {
//             if ((old >> 10) == (d_input >> 10)) {
//                 atomicMin((unsigned long long*)&d_table[pos], (unsigned long long)d_input);
//                 return 0;
//             }
//             // if ((old >> 10) == (key >> 10)) {
//             //     atomicMin((unsigned long long*)&d_table[pos], key);
//             //     return 0;
//             // }
//             // pos = (pos + 1) % TABLE_SIZE;
//             pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//         }
//     }
// }

// __global__ void clearKernel_das (long long *d_table, long long *d_input, int inputSize) {
//     long long idx = threadIdx.x + blockIdx.x * blockDim.x;
//     if (idx >= inputSize) return;

//     long long old;
//     long long pos = hash_pos(d_input[idx] & (~0ull << 10));
//     // long long key = hash_pos_2(d_input[idx] & (~0ull << 10));
//     // key = (key << 10) | (d_input[idx] & 0x3FF);
//     // int pos = hash_52_to_30(d_input[idx] >> 10);
//     // long long key = hash_52_to_22(d_input[idx] >> 13);
//     while (true) {
//         old = d_table[pos];
//         if ((old >> 10) == (d_input[idx] >> 10)) {
//             d_table[pos] = 0;
//             d_input[idx] = old;
//             return;
//         }
//         // if ((old >> 10) == (key >> 10)) {
//         //     d_input[idx] = (d_input[idx] & ~mask) | (old & mask);
//         //     d_table[pos] = 0;
//         //     return;
//         // }
//         // pos = (pos + 1) % TABLE_SIZE;
//         pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//     }
// }

// __global__ void clearKernel_has (long long *d_table, long long* d_input, int inputSize, int hop_cst) {
//     long long idx = threadIdx.x + blockIdx.x * blockDim.x;
//     if (idx >= inputSize) return;
    
//     long long item = d_input[idx];
//     int hop = get_hop(item);
//     for (int i = hop; i <= hop_cst; i ++) {
//         long long pos = hash_pos(item & (~0ull << 10));
//         while (true) {
//             // if (d_table[pos] == 0) return;
//             // if ((item >> 10) == (d_table[pos] >> 10)) {
//             //     d_table[pos] = 0;
//             //     return;
//             // } else {
//             //     pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//             // }
//             if (d_table[pos]) {
//                 d_table[pos] = 0;
//                 pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//             } else {
//                 break;
//             }
//         }
//         item += (1 << 10);
//     }
    
//     // long long idx = threadIdx.x + blockIdx.x * blockDim.x;
//     // if (idx >= inputSize) return;

//     // long long item = d_input[idx];
//     // long long pos = hash_pos(item & (~0ull << 10));
//     // // long long key = hash_pos_2(item & (~0ull << 10));
//     // // key = (key << 10) | (item & 0x3FF);
    
//     // // int pos = hash_52_to_30(item >> 10);
//     // // long long key = hash_52_to_22(item >> 13);
//     // int hop = get_hop
//     // while (true) {
//     //     if (d_table[pos] == 0) return;
//     //     // if ((d_table[pos] >> 10) == (key >> 10)) {
//     //     //     d_table[pos] = 0;
//     //     //     return;
//     //     // } else {
//     //     //     pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//     //     // }
//     //     if ((item >> 10) == (d_table[pos] >> 10)) {
//     //         d_table[pos] = 0;
//     //         return;
//     //     } else {
//     //         pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//     //     }
//     // }
// }

// __device__ int queryKernel_single (long long *d_table, long long d_input) {
//     long long pos = hash_pos(d_input & (~0ull << 10));
//     // long long key = hash_pos_2(d_input & (~0ull << 10));
//     // key = (key << 10) | (d_input & 0x3FF);
//     // int pos = hash_52_to_30(d_input >> 10);
//     // long long key = hash_52_to_22(d_input >> 13);
//     long long old;
//     int x = 0;
//     while (true) {
//         old = d_table[pos];
//         if (old == 0) return 1e5;
//         if ((old >> 10) == (d_input >> 10)) {
//             return (int)((old) & 0x3FF);
//         }
//         // if ((old >> 10) == (key >> 10)) return (int)((old) & 0x3FF);
//         // pos = (pos + 1) & TABLE_SIZE_MINUS_ONE;
//         pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
//         // x ++;
//         // if (x >= 1000) {
//         //     printf("label: %d %d %d %d %lld %lld\n", get_hub_vertex(old), get_to_vertex(old),
//         //             get_hop(old), get_distance(old), old, hash_pos(old & (~0ull << 10)));
//         //     // printf("query shit !!!!\n");
//         // }
//         // pos = (pos + 1) % TABLE_SIZE;
//     }
// }

// template<int THREADS_NUM>
// __global__ void HSDL_gather_kernel (long long *T_pre, unsigned long long *T_pre_offset, long long *T_after, 
//     unsigned long long *T_after_offset, long long *das, int *out_edge, int *out_edge_weight, int *out_pointer, int hop) {
//     typedef cub::BlockScan<int, THREADS_NUM> BlockScan;
//     __shared__ typename BlockScan::TempStorage block_temp_storage;

//     volatile __shared__ int comm[THREADS_NUM / 32][3];
//     volatile __shared__ long long comm_node[THREADS_NUM / 32];
//     volatile __shared__ int comm2[THREADS_NUM];
//     volatile __shared__ long long comm2_node[THREADS_NUM];
//     volatile __shared__ int output_cta_offset;
//     volatile __shared__ int output_warp_offset[THREADS_NUM / 32];

//     typedef cub::WarpScan<int> WarpScan;
//     __shared__ typename WarpScan::TempStorage temp_storage[THREADS_NUM / 32];

//     int thread_id = threadIdx.x;
//     int lane_id = thread_id % 32;
//     int warp_id = thread_id / 32;

//     int cta_offset = blockDim.x * blockIdx.x;
//     while (cta_offset < T_pre_offset[0]) {
//         long long node;
//         int row_begin, row_end;
//         if (cta_offset + thread_id < T_pre_offset[0]) {
//             node = T_pre[cta_offset + thread_id];
//             row_begin = out_pointer[get_to_vertex(node)];
//             row_end = out_pointer[get_to_vertex(node) + 1];
//         } else
//             row_begin = row_end = 0;

//         // CTA-based coarse-grained gather
//         while (__syncthreads_or(row_end - row_begin >= THREADS_NUM)) {
//             // vie for control of block
//             if (row_end - row_begin >= THREADS_NUM)
//                 comm[0][0] = thread_id;
//             __syncthreads();

//             // winner describes adjlist
//             if (comm[0][0] == thread_id) {
//                 comm[0][1] = row_begin;
//                 comm[0][2] = row_end;
//                 comm_node[0] = node;
//                 row_begin = row_end;
//             }
//             __syncthreads();

//             int gather = comm[0][1] + thread_id;
//             int gather_end = comm[0][2];
//             long long u = comm_node[0];
//             long long neighbour;
//             int thread_data_in;
//             int thread_data_out;
//             int block_aggregate;
//             int hub_vertex;
//             while (__syncthreads_or(gather < gather_end)) {
//                 if (gather < gather_end) {
//                     hub_vertex = get_hub_vertex(u);
//                     neighbour = get_label(out_edge[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]); 
//                     if (hub_vertex < out_edge[gather] && insertKernel_das(das, neighbour)) {
//                         thread_data_in = 1;
//                     } else {
//                         thread_data_in = 0;
//                     }
//                 } else
//                     thread_data_in = 0;

//                 __syncthreads();
//                 BlockScan(block_temp_storage).ExclusiveSum(thread_data_in, thread_data_out, block_aggregate);
//                 __syncthreads();
//                 if (0 == thread_id) {
//                     output_cta_offset = atomicAdd(T_after_offset, (unsigned long long)block_aggregate);
//                 }
//                 __syncthreads();
//                 if (thread_data_in)
//                     T_after[output_cta_offset + thread_data_out] = neighbour;
//                 gather += THREADS_NUM;
//             }
//         }

//         // warp-based coarse-grained gather
//         while (__any_sync(FULL_MASK, row_end - row_begin >= 32)) {
//             // vie for control of warp
//             if (row_end - row_begin >= 32)
//                 comm[warp_id][0] = lane_id;

//             // winner describes adjlist
//             if (comm[warp_id][0] == lane_id) {
//                 comm[warp_id][1] = row_begin;
//                 comm[warp_id][2] = row_end;
//                 comm_node[warp_id] = node;
//                 row_begin = row_end;
//             }

//             int gather = comm[warp_id][1] + lane_id;
//             int gather_end = comm[warp_id][2];
//             long long u = comm_node[warp_id];
//             long long neighbour;
//             int hub_vertex;
//             int thread_data_in;
//             int thread_data_out;
//             int warp_aggregate;
//             while (__any_sync(FULL_MASK, gather < gather_end)) {
//                 if (gather < gather_end) {
//                     hub_vertex = get_hub_vertex(u);
//                     neighbour = get_label(out_edge[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
//                     if (hub_vertex < out_edge[gather] && insertKernel_das(das, neighbour)) {
//                         thread_data_in = 1;
//                     } else {
//                         thread_data_in = 0;
//                     }
//                 } else
//                     thread_data_in = 0;

//                 WarpScan(temp_storage[warp_id]).ExclusiveSum(thread_data_in, thread_data_out, warp_aggregate);

//                 if (0 == lane_id) {
//                     output_warp_offset[warp_id] = atomicAdd(T_after_offset, (unsigned long long)warp_aggregate);
//                 }

//                 if (thread_data_in)
//                     T_after[output_warp_offset[warp_id] + thread_data_out] = neighbour;
//                 gather += 32;
//             }
//         }

//         // scan-based fine-grained gather
//         int thread_data = row_end - row_begin;
//         int rsv_rank;
//         int total;
//         int remain;
//         __syncthreads();
//         BlockScan(block_temp_storage).ExclusiveSum(thread_data, rsv_rank, total);
//         __syncthreads();

//         int cta_progress = 0;
//         while (cta_progress < total) {
//             remain = total - cta_progress;

//             // share batch of gather offsets
//             while ((rsv_rank < cta_progress + THREADS_NUM) && (row_begin < row_end)) {
//                 comm2[rsv_rank - cta_progress] = row_begin;
//                 comm2_node[rsv_rank - cta_progress] = node;
//                 rsv_rank++;
//                 row_begin++;
//             }
//             __syncthreads();
//             long long neighbour;
//             int hub_vertex;
//             long long u = comm2_node[thread_id];
//             int e = comm2[thread_id];
//             // gather batch of adjlist
//             if (thread_id < min(remain, THREADS_NUM)) {
//                 hub_vertex = get_hub_vertex(u);
//                 neighbour = get_label(out_edge[e], hub_vertex, hop, get_distance(u) + out_edge_weight[e]);
//                 if (hub_vertex < out_edge[e] && insertKernel_das(das, neighbour)) {
//                     thread_data = 1;
//                 } else {
//                     thread_data = 0;
//                 }
//             } else
//                 thread_data = 0;
//             __syncthreads();

//             int scatter;
//             int block_aggregate;

//             BlockScan(block_temp_storage).ExclusiveSum(thread_data, scatter, block_aggregate);
//             __syncthreads();

//             if (0 == thread_id) {
//                 output_cta_offset = atomicAdd(T_after_offset, (unsigned long long)block_aggregate);
//             }
//             __syncthreads();

//             if (thread_data)
//                 T_after[output_cta_offset + scatter] = neighbour;
//             cta_progress += THREADS_NUM;
//             __syncthreads();
//         }

//         cta_offset += blockDim.x * gridDim.x;
//     }
// }

// inline void Gather_kernel (long long *T, char *flag, unsigned long long last_size, long long *D_sort_temp, long long *d_num_selected) { 
//     void* d_temp_storage = nullptr;
//     size_t temp_storage_bytes = 0;
//     cub::DeviceSelect::Flagged(d_temp_storage, temp_storage_bytes, T, flag, T, d_num_selected, last_size);
//     cudaDeviceSynchronize();
//     cub::DeviceSelect::Flagged(D_sort_temp, temp_storage_bytes, T, flag, T, d_num_selected, last_size);
//     cudaDeviceSynchronize();
// }

// inline void Sort_kernel (long long *T, unsigned long long last_size, unsigned long long last_pos, long long *D_sort_temp) { 
//     void *d_temp_storage = nullptr;
//     size_t temp_storage_bytes = 0;
//     cub::DeviceRadixSort::SortKeys(d_temp_storage, temp_storage_bytes, T + last_pos, T + last_pos, last_size);
//     cudaDeviceSynchronize();
//     cub::DeviceRadixSort::SortKeys(D_sort_temp, temp_storage_bytes, T + last_pos, T + last_pos, last_size);
//     cudaDeviceSynchronize();
// }

// __global__ void Tranverse_kernel (
//     const long long * __restrict__ T1, 
//     long long * __restrict__ T2, 
//     long long * __restrict__ has, 
//     const long long * __restrict__ T_offset_begin, 
//     const long long * __restrict__ T_offset_end, 
//     char * __restrict__ flag, 
//     const unsigned long long * __restrict__ T_size, 
//     int V
// ) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < T_size[0]) {
//         long long entry = T1[tid];
//         int hop = get_hop(entry);
//         // if (hop <= 1) return;
//         int to_vertex = get_to_vertex(entry);
//         int hub_vertex = get_hub_vertex(entry);
//         int dis = get_distance(entry);
//         flag[tid] = 1;
        
//         for (int i = 1; i < hop; i ++) {
//             long long idx = (long long)V * i + to_vertex;
//             long long posl = __ldg(T_offset_begin + idx);
//             long long posr = __ldg(T_offset_end + idx);
//             for (long long j = posl; j < posr; j ++) {
//                 long long TT = T2[j];
//                 int mid_vertex = get_hub_vertex(TT);
//                 if (get_distance(TT) + queryKernel_single(has, get_label(hub_vertex, mid_vertex, hop - i, 0)) <= dis) {
//                     flag[tid] = 0;
//                     return;
//                 }
//             }
//         }
//     }
// }

// __global__ void updateHas (long long *T, long long T_start, long long *has, unsigned long long T_size, 
//     long long *T_offset_begin, long long *T_offset_end, long long V, int hop, int hop_cst) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < T_size) {
//         long long TT = T[tid];
//         for (int i = hop; i < hop_cst; i ++) {
//             insertKernel_has (has, TT);
//             TT += (1 << 10);
//         }
//         if (get_to_vertex(TT) != get_to_vertex(T[tid - 1])) {
//             T_offset_begin[V * hop + get_to_vertex(TT)] = T_start + tid;
//         }
//         if (get_to_vertex(TT) != get_to_vertex(T[tid + 1])) {
//             T_offset_end[V * hop + get_to_vertex(TT)] = T_start + tid + 1;
//         }
//     }
// }

// __global__ void init_T (int group_size, long long *T, long long *has, int *nid, 
//     long long *T_offset_begin, long long *T_offset_end, int hop_cst) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < group_size) {
//         int v = nid[tid];
//         T[tid] = get_label(v, v, 0, 0); // to, hub, hop, dis
//         long long TT = T[tid];
//         for (int i = 0; i <= hop_cst; i ++) {
//             insertKernel_has (has, TT);
//             TT += (1 << 10);
//         }
//         T_offset_begin[v] = tid + 1;
//         T_offset_end[v] = tid + 2;
//     }
// }

// __global__ void init_T_offset (long long *T_offset_begin, long long *T_offset_end, long long V_hop) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < V_hop) {
//         T_offset_begin[tid] = 0;
//         T_offset_end[tid] = 0;
//     }
// }

// __global__ void check_hash_(long long *h_table) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid <= TABLE_SIZE_MINUS_ONE) {
//         if (h_table[tid]) {
//             printf("shit!!!!! %d %d %d %d\n", get_to_vertex(h_table[tid]), get_hub_vertex(h_table[tid]),
//             get_hop(h_table[tid]), get_distance(h_table[tid]));
//         }
//     }
// }

// // the proces of generate labels
// void label_gen_v3 (CSR_graph<weight_type>& input_graph, hop_constrained_case_info_v2 *info, long long *L, 
//         long long &L_size, std::vector<int>& nid_vec, int nid_vec_id, double &sort_time_record) {
//     cudaError_t err;
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error -2: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
//     constexpr int THREADS_NUM = 256;
//     constexpr int THREADS = 256;
//     long long V = input_graph.OUTs_Neighbor_start_pointers.size() - 1;
//     long long E = input_graph.OUTs_Edges.size();
//     int* out_edge = input_graph.out_edge;
//     int* out_edge_weight = input_graph.out_edge_weight;
//     int* out_pointer = input_graph.out_pointer;
//     // out_edge, out_edge_weight, out_pointer
//     long long hop_cst = info->hop_cst;
//     long long group_size = info->nid_size[nid_vec_id];
//     int *nid = info->nid[nid_vec_id];
//     long long* T = info->T;
//     long long* H = info->has;
//     long long* D = info->das;
//     long long* D_sort_temp = info->D_sort_temp; // 排序辅助空间
//     long long* T_offset_begin = info->T_offset_begin;
//     long long* T_offset_end = info->T_offset_end;
//     char* flag = info->flag;

//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error -1: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }

//     unsigned long long *T_pre_offset, *T_after_offset;
//     cudaMalloc(&T_pre_offset, sizeof(unsigned long long));
//     cudaMalloc(&T_after_offset, sizeof(unsigned long long));

//     long long *d_num_selected;
//     cudaMalloc(&d_num_selected, sizeof(long long));
//     cudaDeviceSynchronize();

//     // 按照hop生成label
//     unsigned long long last_pos = 1, last_size[1] = {group_size}; // 上一次生成到的位置
//     long long inf_ll[1] = {0x7FFFFFFFFFFFFFFFLL};

//     // 初始化
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 0: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
//     // printf("group_size: %d\n", group_size);
//     long long BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, V * (hop_cst + 1));
//     init_T_offset<<<BLOCKS_NUM, THREADS_NUM>>>(T_offset_begin, T_offset_end, V * (hop_cst + 1));
//     cudaDeviceSynchronize();
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 1: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
    
//     BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, group_size);
//     init_T<<<BLOCKS_NUM, THREADS_NUM>>>(group_size, T + last_pos, H, nid, T_offset_begin, T_offset_end, hop_cst);
//     cudaDeviceSynchronize();
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 2: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
        
//     unsigned long long zero = 0;
//     for (int hop = 1; hop <= hop_cst; hop ++) { // generate the label with (hop = hop)
//         if (last_size[0] == 0) break;

//         // printf("hop: %d\n", hop);
//         // step1 扩展
//         BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
//         cudaMemcpy(T_pre_offset, last_size, sizeof(unsigned long long), cudaMemcpyHostToDevice);
//         cudaMemcpy(T_after_offset, &zero, sizeof(unsigned long long), cudaMemcpyHostToDevice);
//         cudaDeviceSynchronize();

//         // cudaMemcpy(L + last_pos - 1, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
//         // printf("size: %llu\n", last_size[0]);
//         HSDL_gather_kernel<THREADS_NUM> <<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, T_pre_offset, T + last_pos + last_size[0], 
//             T_after_offset, D, out_edge, out_edge_weight, out_pointer, hop);
//         cudaDeviceSynchronize();
//         err = cudaGetLastError();
//         if (err != cudaSuccess) {
//             printf("Kernel launch error 3: %s\n", cudaGetErrorString(err));
//             exit(0);
//         }
        
//         last_pos += last_size[0];
//         cudaMemcpy(last_size, T_after_offset, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
        
//         // printf("size: %llu, %llu\n", last_pos, last_size[0]);
        
//         if (last_size[0] == 0) break;
//         BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
//         clearKernel_das <<<BLOCKS_NUM, THREADS_NUM>>> (D, T + last_pos, last_size[0]);
//         cudaDeviceSynchronize();
//         err = cudaGetLastError();
//         if (err != cudaSuccess) {
//             printf("Kernel launch error 4: %s\n", cudaGetErrorString(err));
//             exit(0);
//         }
        
//         // printf("Clear done !!\n");
        
//         // step2 sort
//         auto t1 = std::chrono::high_resolution_clock::now();
//         Sort_kernel(T, last_size[0], last_pos, D_sort_temp);
//         auto t2 = std::chrono::high_resolution_clock::now();
//         double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
//         sort_time_record += ms / 1000;
//         // printf("Sort done !!\n");
//         // printf("size: %llu, %llu\n", last_pos, last_size[0]);
//         // cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
//         // cudaDeviceSynchronize();
//         // for (long long i = 0; i < last_size[0]; i++) {
//         //     printf("output: %lld, %d, %d, %d, %d\n", i, get_to_vertex(output[i]), get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
//         // }

//         // step3 遍历
//         BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
//         Tranverse_kernel <<<BLOCKS_NUM, THREADS_NUM>>> (T + last_pos, T, H, T_offset_begin, T_offset_end, flag, T_after_offset, V);
//         cudaDeviceSynchronize();
//         err = cudaGetLastError();
//         if (err != cudaSuccess) {
//             printf("Kernel launch error 5: %s\n", cudaGetErrorString(err));
//             exit(0);
//         }
        
//         // printf("Tranverse done !!\n");
        
//         // step4 gather
//         Gather_kernel(T + last_pos, flag, last_size[0], D_sort_temp, d_num_selected);
//         cudaMemcpy(&last_size, d_num_selected, sizeof(long long), cudaMemcpyDeviceToHost);
//         printf("num_selected: %lld\n", last_size[0]);
    
//         // step5 更新哈希
//         // if (hop < hop_cst) updateHas<<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, last_pos, H, last_size[0], T_offset_begin, T_offset_end, V, hop, hop_cst);
//         updateHas<<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, last_pos, H, last_size[0], T_offset_begin, T_offset_end, V, hop, hop_cst);
//         cudaDeviceSynchronize();
//         err = cudaGetLastError();
//         if (err != cudaSuccess) {
//             printf("Kernel launch error 6: %s\n", cudaGetErrorString(err));
//             exit(0);
//         }

//         // printf("updateHas done!!!\n");
//     }
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 7: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
//     BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_pos + last_size[0] - 1);
//     clearKernel_has<<<BLOCKS_NUM, THREADS_NUM>>>(H, T + 1, last_pos + last_size[0] - 1, hop_cst);
//     // BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_pos - 1);
//     // clearKernel_has<<<BLOCKS_NUM, THREADS_NUM>>>(H, T + 1, last_pos - 1);
//     cudaDeviceSynchronize();
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 8: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
//     printf("clearKernel done!!!\n");
//     // 从设备拷贝到主机 vector
//     auto start = std::chrono::high_resolution_clock::now();
//     cudaMemcpy(L, T + 1, (last_pos + last_size[0] - 1) * sizeof(long long), cudaMemcpyDeviceToHost);
//     cudaDeviceSynchronize();
//     // 在核函数后立即检查
//     err = cudaGetLastError();
//     if (err != cudaSuccess) {
//         printf("Kernel launch error 9: %s\n", cudaGetErrorString(err));
//         exit(0);
//     }
//     auto end = std::chrono::high_resolution_clock::now();
//     double time = std::chrono::duration_cast<std::chrono::nanoseconds>(end - start).count() / 1e9;
    
//     // L_size = 0;
//     L_size += last_pos + last_size[0] - 1;
//     printf("time memcpy: %.6lf\n", time);

//     // BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, TABLE_SIZE);
//     // check_hash_<<<BLOCKS_NUM, THREADS_NUM>>>(H);
//     // cudaDeviceSynchronize();
// }

// inline void Generate_Parent_Vertex () {
    
// }