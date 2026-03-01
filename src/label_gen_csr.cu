#include <label/gen_label.cuh>
#include <cub/cub.cuh>
#include <cuda_runtime.h>
#include <nvml.h>
#include <atomic>
#include <cuda_runtime.h>
#include <definition/cuda_err.cuh>

typedef size_t SIZE_TYPE;
const int MAX_BLOCKS_NUM = 96 * 8;
#define FULL_MASK 0xffffffff
#define CALC_BLOCKS_NUM(ITEMS_PER_BLOCK, CALC_SIZE) min(MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
#define CALC_BLOCKS_NUM_LL(ITEMS_PER_BLOCK, CALC_SIZE) min((long long)MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
#define CALC_BLOCKS_NUM_NOLIMIT(ITEMS_PER_BLOCK, CALC_SIZE) ((CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)

__forceinline__ __device__ int hash_pos (const long long &x) {
    return x % TABLE_SIZE;
}
__forceinline__ __device__ int hash_pos_2 (const long long &x) {
    return x % MOD;
}
__forceinline__ __device__ int hash_52_to_30(const uint64_t &input) {
    // input *= (input >> 24);
    // input *= 0x9E3779B97F4A7C15ULL;
    // input ^= input << 30;
    // input *= 0xbf58476d1ce4e5b9LL;
    // input ^= input >> 27;
    // input *= 0x94d049bb133111ebLL;
    // input ^= input << 31;
    // return (input >> 22) & 0x3FFFFFFF;
    return input % TABLE_SIZE;
}
__forceinline__ __device__ int hash_52_to_22(const uint64_t &input) {
    // input *= (input >> 24);
    // input *= 0xc6a4b3b5d82bc2c9ULL;
    // input ^= (input >> 3) * 0x1B873593;  // 右移29位，乘以质数0x1B873593
    // input ^= (input << 17) * 0x4C190623;  // 左移17位，乘以质数0x4C190623
    // input ^= (input >> 32) * 0x82E7E515;  // 右移32位，乘以质数0x82E7E515
    // input ^= (input << 11) * 0x5BD1E995;  // 左移11位，乘以质数0x5BD1E995
    // return (input >> 25) & 0x003FFFFF;
    return input % MOD;
}

__forceinline__ __device__ void insertKernel_has (long long* d_table, long long d_input) {
    long long pos = hash_pos(d_input & (~0ull << 10));
    long long old;
    while (true) {
        old = d_table[pos];
        if (old == 0) {
            long long expected = 0;
            if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
                break;
            }
        } else {
            if ((old >> 10) == (d_input >> 10)) {
                d_table[pos] = d_input;
                return;
            }
            pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
        }
    }
}

__forceinline__ __device__ long long change_label(const long long &x, int *source) {
    return get_label(source[get_to_vertex(x)], get_hub_vertex(x), get_hop(x), get_distance(x));
}

__forceinline__ __device__ bool insertKernel_das (long long *d_table, int *source, long long d_input) {
    long long pos = hash_pos(change_label(d_input, source) & (~0ull << 10));
    long long old;
    while (true) {
        old = d_table[pos];
        if (old == 0) {
            long long expected = 0;
            if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
                return 1;
            }
        } else {
            if ((change_label(old, source) >> 10) == (change_label(d_input, source) >> 10)) {
                while (1) {
                    old = d_table[pos];
                    long long old_low10 = old & 0x3FF;  // 0x3FF = (1 << 10) - 1
                    long long input_low10  = d_input & 0x3FF;
                    if (input_low10 < old_low10) {
                        atomicCAS((unsigned long long*)&d_table[pos], old, d_input);
                        if (d_table[pos] == d_input) {
                            return 0;
                        }
                    } else {
                        return 0;
                    }
                }
                // long long old_low10 = old & 0x3FF;  // 0x3FF = (1 << 10) - 1
                // long long input_low10  = d_input & 0x3FF;
                // if (input_low10 < old_low10) {
                //     atomicCAS((unsigned long long*)&d_table[pos], old, d_input);
                // }
                // return 0;
            }
            pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
        }
    }
}

__global__ void clearKernel_das (long long *d_table, long long *d_input, int *source, int inputSize) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;

    long long old;
    long long d_input_change = change_label(d_input[idx], source);
    long long pos = hash_pos(d_input_change & (~0ull << 10));
    while (true) {
        old = d_table[pos];
        if ((change_label(old, source) >> 10) == (change_label(d_input[idx], source) >> 10)) {
            d_table[pos] = 0;
            d_input[idx] = old;
            return;
        }
        pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
    }
}

__global__ void clearKernel_has (long long *d_table, long long* d_input, int *source, int inputSize, int hop_cst) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;
    
    long long item = d_input[idx];
    item = change_label(item, source);
    int hop = get_hop(item);
    for (int i = hop; i <= hop_cst; i ++) {
        long long pos = hash_pos(item & (~0ull << 10));
        while (true) {
            if (d_table[pos]) {
                d_table[pos] = 0;
                pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
            } else {
                break;
            }
        }
        item += (1 << 10);
    }
}

__forceinline__ __device__ int queryKernel_single (long long *d_table, long long d_input) {
    long long pos = hash_pos(d_input & (~0ull << 10));
    long long old;
    int x = 0;
    while (true) {
        old = d_table[pos];
        if (old == 0) return 1e5;
        if ((old >> 10) == (d_input >> 10)) {
            return (int)((old) & 0x3FF);
        }
        pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
    }
}

template<int THREADS_NUM>
__global__ void HSDL_gather_kernel_naive (long long *T_pre, unsigned long long *T_pre_offset, long long *T_after, unsigned long long *T_after_offset,
    long long *das, int *out_edge, int *out_edge_weight, int *out_pointer, int *inv, int *source, int hop) {
    
    int idx = blockIdx.x * blockDim.x + threadIdx.x;
    unsigned long long total_vertices = T_pre_offset[0];

    for (int i = idx; i < total_vertices; i += blockDim.x * gridDim.x) {
        
        long long node = T_pre[i];
        
        int src = source[get_to_vertex(node)];
        int hub_vertex = get_hub_vertex(node);
        int current_dist = get_distance(node);
        int row_begin = out_pointer[src], row_end = out_pointer[src + 1];

        for (int gather = row_begin; gather < row_end; ++ gather) {
            
            // 计算邻居的新 label
            long long neighbour = get_label(inv[gather], hub_vertex, hop, current_dist + out_edge_weight[gather]);

            // 5. 条件判定与插入
            // 只有满足特定条件且成功插入 das 集合时，才将其放入下一轮 Frontier
            if (hub_vertex < out_edge[gather] && insertKernel_das(das, source, neighbour)) {
                
                // 6. 使用原子操作竞争输出位置
                // 原代码复杂的 BlockScan 最终目的就是为了算出这个 offset
                unsigned long long output_pos = atomicAdd(T_after_offset, 1ULL);
                T_after[output_pos] = neighbour;
            }
        }
    }
}

template<int THREADS_NUM>
__global__ void HSDL_gather_kernel (long long *T_pre, unsigned long long *T_pre_offset, long long *T_after, unsigned long long *T_after_offset, 
    long long *das, int *out_edge, int *out_edge_weight, int *out_pointer, int *inv, int *source, int hop) {
    typedef cub::BlockScan<int, THREADS_NUM> BlockScan;
    __shared__ typename BlockScan::TempStorage block_temp_storage;

    volatile __shared__ int comm[THREADS_NUM / 32][3];
    volatile __shared__ long long comm_node[THREADS_NUM / 32];
    volatile __shared__ int comm2[THREADS_NUM];
    volatile __shared__ long long comm2_node[THREADS_NUM];
    volatile __shared__ int output_cta_offset;
    volatile __shared__ int output_warp_offset[THREADS_NUM / 32];

    typedef cub::WarpScan<int> WarpScan;
    __shared__ typename WarpScan::TempStorage temp_storage[THREADS_NUM / 32];

    int thread_id = threadIdx.x;
    int lane_id = thread_id % 32;
    int warp_id = thread_id / 32;

    int cta_offset = blockDim.x * blockIdx.x;
    while (cta_offset < T_pre_offset[0]) {
        long long node;
        int row_begin, row_end;
        if (cta_offset + thread_id < T_pre_offset[0]) {
            node = T_pre[cta_offset + thread_id];
            int src = source[get_to_vertex(node)];
            // printf("src: %d\n", src);
            row_begin = out_pointer[src];
            row_end = out_pointer[src + 1];
            // row_begin = out_pointer[get_to_vertex(node)];
            // row_end = out_pointer[get_to_vertex(node) + 1];
        } else
            row_begin = row_end = 0;

        // CTA-based coarse-grained gather
        while (__syncthreads_or(row_end - row_begin >= THREADS_NUM)) {
            // vie for control of block
            if (row_end - row_begin >= THREADS_NUM)
                comm[0][0] = thread_id;
            __syncthreads();

            // winner describes adjlist
            if (comm[0][0] == thread_id) {
                comm[0][1] = row_begin;
                comm[0][2] = row_end;
                comm_node[0] = node;
                row_begin = row_end;
            }
            __syncthreads();

            int gather = comm[0][1] + thread_id;
            int gather_end = comm[0][2];
            long long u = comm_node[0];
            long long neighbour;
            int thread_data_in;
            int thread_data_out;
            int block_aggregate;
            int hub_vertex;
            while (__syncthreads_or(gather < gather_end)) {
                if (gather < gather_end) {
                    hub_vertex = get_hub_vertex(u);
                    // neighbour = get_label(out_edge[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    neighbour = get_label(inv[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    // printf("source[inv[gather]], out_edge[gather]: %d, %d\n", source[inv[gather]], out_edge[gather]);
                    // printf("out_edge[gather], source: %d, %d\n", out_edge[inv[gather]], source);
                    if (hub_vertex < out_edge[gather] && insertKernel_das(das, source, neighbour)) {
                        thread_data_in = 1;
                    } else {
                        thread_data_in = 0;
                    }
                } else
                    thread_data_in = 0;

                __syncthreads();
                BlockScan(block_temp_storage).ExclusiveSum(thread_data_in, thread_data_out, block_aggregate);
                __syncthreads();
                if (0 == thread_id) {
                    output_cta_offset = atomicAdd(T_after_offset, (unsigned long long)block_aggregate);
                }
                __syncthreads();
                if (thread_data_in)
                    T_after[output_cta_offset + thread_data_out] = neighbour;
                gather += THREADS_NUM;
            }
        }

        // warp-based coarse-grained gather
        while (__any_sync(FULL_MASK, row_end - row_begin >= 32)) {
            // vie for control of warp
            if (row_end - row_begin >= 32)
                comm[warp_id][0] = lane_id;

            // winner describes adjlist
            if (comm[warp_id][0] == lane_id) {
                comm[warp_id][1] = row_begin;
                comm[warp_id][2] = row_end;
                comm_node[warp_id] = node;
                row_begin = row_end;
            }

            int gather = comm[warp_id][1] + lane_id;
            int gather_end = comm[warp_id][2];
            long long u = comm_node[warp_id];
            long long neighbour;
            int hub_vertex;
            int thread_data_in;
            int thread_data_out;
            int warp_aggregate;
            while (__any_sync(FULL_MASK, gather < gather_end)) {
                if (gather < gather_end) {
                    hub_vertex = get_hub_vertex(u);
                    // neighbour = get_label(out_edge[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    neighbour = get_label(inv[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    // printf("source[inv[gather]], out_edge[gather]: %d, %d\n", source[inv[gather]], out_edge[gather]);
                    // printf("inv[gather]: %d\n", inv[gather]);
                    // printf("out_edge[gather], source: %d, %d\n", out_edge[inv[gather]], source);
                    if (hub_vertex < out_edge[gather] && insertKernel_das(das, source, neighbour)) {
                        thread_data_in = 1;
                    } else {
                        thread_data_in = 0;
                    }
                } else
                    thread_data_in = 0;

                WarpScan(temp_storage[warp_id]).ExclusiveSum(thread_data_in, thread_data_out, warp_aggregate);

                if (0 == lane_id) {
                    output_warp_offset[warp_id] = atomicAdd(T_after_offset, (unsigned long long)warp_aggregate);
                }

                if (thread_data_in)
                    T_after[output_warp_offset[warp_id] + thread_data_out] = neighbour;
                gather += 32;
            }
        }

        // scan-based fine-grained gather
        int thread_data = row_end - row_begin;
        int rsv_rank;
        int total;
        int remain;
        __syncthreads();
        BlockScan(block_temp_storage).ExclusiveSum(thread_data, rsv_rank, total);
        __syncthreads();

        int cta_progress = 0;
        while (cta_progress < total) {
            remain = total - cta_progress;

            // share batch of gather offsets
            while ((rsv_rank < cta_progress + THREADS_NUM) && (row_begin < row_end)) {
                comm2[rsv_rank - cta_progress] = row_begin;
                comm2_node[rsv_rank - cta_progress] = node;
                rsv_rank++;
                row_begin++;
            }
            __syncthreads();
            long long neighbour;
            int hub_vertex;
            long long u = comm2_node[thread_id];
            int e = comm2[thread_id];
            // gather batch of adjlist
            if (thread_id < min(remain, THREADS_NUM)) {
                hub_vertex = get_hub_vertex(u);
                // neighbour = get_label(out_edge[e], hub_vertex, hop, get_distance(u) + out_edge_weight[e]);
                neighbour = get_label(inv[e], hub_vertex, hop, get_distance(u) + out_edge_weight[e]);
                // printf("source[inv[gather]], out_edge[gather]: %d, %d\n", source[inv[e]], out_edge[e]);
                // printf("inv[gather]: %d\n", inv[e]);
                // printf("out_edge[gather], source: %d, %d\n", out_edge[inv[e]], source);
                if (hub_vertex < out_edge[e] && insertKernel_das(das, source, neighbour)) {
                    thread_data = 1;
                } else {
                    thread_data = 0;
                }
            } else
                thread_data = 0;
            __syncthreads();

            int scatter;
            int block_aggregate;

            BlockScan(block_temp_storage).ExclusiveSum(thread_data, scatter, block_aggregate);
            __syncthreads();

            if (0 == thread_id) {
                output_cta_offset = atomicAdd(T_after_offset, (unsigned long long)block_aggregate);
            }
            __syncthreads();

            if (thread_data)
                T_after[output_cta_offset + scatter] = neighbour;
            cta_progress += THREADS_NUM;
            __syncthreads();
        }

        cta_offset += blockDim.x * gridDim.x;
    }
}

inline void Gather_kernel (long long *T, char *flag, unsigned long long last_size, long long *D_sort_temp, long long *d_num_selected) { 
    void* d_temp_storage = nullptr;
    size_t temp_storage_bytes = 0;
    cub::DeviceSelect::Flagged(d_temp_storage, temp_storage_bytes, T, flag, T, d_num_selected, last_size);
    cudaDeviceSynchronize();
    cub::DeviceSelect::Flagged(D_sort_temp, temp_storage_bytes, T, flag, T, d_num_selected, last_size);
    cudaDeviceSynchronize();
}

inline void Sort_kernel (long long *T, unsigned long long last_size, unsigned long long last_pos, long long *D_sort_temp) { 
    void *d_temp_storage = nullptr;
    size_t temp_storage_bytes = 0;
    cub::DeviceRadixSort::SortKeys(d_temp_storage, temp_storage_bytes, T + last_pos, T + last_pos, last_size);
    cudaDeviceSynchronize();
    cub::DeviceRadixSort::SortKeys(D_sort_temp, temp_storage_bytes, T + last_pos, T + last_pos, last_size);
    cudaDeviceSynchronize();
}

__global__ void Tranverse_kernel_no_CSR (long long *T1, long long *T2, long long *has, long long *T_offset_begin, long long *T_offset_end,
    int *source, char *flag, const unsigned long long *T_size, int V) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= T_size[0]) return;

    long long entry = T1[tid];
    int hop = get_hop(entry);
    // if (hop <= 1) return;
    // int to_vertex = source[get_to_vertex(entry)];
    int to_vertex = source[get_to_vertex(entry)];
    int hub_vertex = get_hub_vertex(entry);
    int dis = get_distance(entry);
    flag[tid] = 1;
    
    for (int i = 0; i < __ldg(T_offset_end + (hop - 1) * V + V + 1); i ++) {
        long long TT = T2[i];
        if (to_vertex == source[get_to_vertex(TT)]) {
            int mid_vertex = get_hub_vertex(TT);
            if (get_distance(TT) + queryKernel_single(has, get_label(hub_vertex, mid_vertex, hop - i, 0)) <= dis) {
                flag[tid] = 0;
                return;
            }
        }
    }

    // for (int i = 1; i < hop; i ++) {
    //     long long idx = (long long) V * i + to_vertex;
    //     long long posl = __ldg(T_offset_begin + idx);
    //     long long posr = __ldg(T_offset_end + idx);
    //     for (long long j = posl; j < posr; j ++) {
    //         long long TT = T2[j];
    //         int mid_vertex = get_hub_vertex(TT);
    //         if (get_distance(TT) + queryKernel_single(has, get_label(hub_vertex, mid_vertex, hop - i, 0)) <= dis) {
    //             flag[tid] = 0;
    //             return;
    //         }
    //     }
    // }
}

__global__ void updateHas (long long *T, long long T_start, long long *has, unsigned long long T_size, 
    long long *T_offset_begin, long long *T_offset_end, int *source, long long V, int hop, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= T_size) return;

    long long TT = T[tid];
    TT = change_label(TT, source);
    for (int i = hop; i < hop_cst; i ++) {
        insertKernel_has (has, TT);
        TT += (1 << 10);
    }
    if (get_to_vertex(TT) != source[get_to_vertex(T[tid - 1])]) {
        T_offset_begin[V * hop + get_to_vertex(TT)] = T_start + tid;
    }
    if (get_to_vertex(TT) != source[get_to_vertex(T[tid + 1])]) {
        T_offset_end[V * hop + get_to_vertex(TT)] = T_start + tid + 1;
    }
}

__global__ void init_T (int group_size, long long *T, long long *has, int *nid, long long *T_offset_begin, long long *T_offset_end, 
    int *out_edge, int *out_edge_weight, int *out_pointer, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= group_size) return;

    int v = nid[tid];
    // T[tid] = get_label(v, v, 0, 0);
    long long TT = get_label(v, v, 0, 0); // to, hub, hop, dis
    for (int i = 0; i <= hop_cst; i ++) {
        insertKernel_has (has, TT);
        TT += (1 << 10);
    }
    T[tid] = get_label(out_pointer[v], v, 0, 0);
    T_offset_begin[v] = tid + 1;
    T_offset_end[v] = tid + 2;
}

__global__ void init_T_offset (long long *T_offset_begin, long long *T_offset_end, long long V_hop) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= V_hop) return;

    T_offset_begin[tid] = 0;
    T_offset_end[tid] = 0;
}

__global__ void check_hash_(long long *h_table) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid <= TABLE_SIZE_MINUS_ONE && h_table[tid]) {
        printf("check hash error. %d, %d, %d, %d\n", get_to_vertex(h_table[tid]), get_hub_vertex(h_table[tid]),
                    get_hop(h_table[tid]), get_distance(h_table[tid]));
    }
}

// the proces of generate labels
void label_gen_v4 (CSR_graph<weight_type>& input_graph, hop_constrained_case_info_v2 *info, long long *L, 
        long long &L_size, std::vector<int>& nid_vec, int nid_vec_id, int check_wb, double &sort_time_record) {
    
    constexpr int THREADS_NUM = 256;
    long long V = input_graph.OUTs_Neighbor_start_pointers.size() - 1;
    long long E = input_graph.OUTs_Edges.size();

    // out_edge, out_edge_weight, out_pointer
    int* out_edge = input_graph.out_edge;
    int* out_edge_weight = input_graph.out_edge_weight;
    int* out_pointer = input_graph.out_pointer;
    int* source = input_graph.source;
    int* inv = input_graph.inv;
    
    long long hop_cst = info->hop_cst;
    long long group_size = info->nid_size[nid_vec_id];
    int* nid = info->nid[nid_vec_id];
    long long* T = info->T;
    long long* H = info->has;
    long long* D = info->das;
    long long* D_sort_temp = info->D_sort_temp;
    long long* T_offset_begin = info->T_offset_begin;
    long long* T_offset_end = info->T_offset_end;
    char* flag = info->flag;

    unsigned long long *T_pre_offset, *T_after_offset;
    long long *d_num_selected;
    cudaMalloc(&T_pre_offset, sizeof(unsigned long long));
    cudaMalloc(&T_after_offset, sizeof(unsigned long long));
    cudaMalloc(&d_num_selected, sizeof(long long));
    cudaDeviceSynchronize();

    unsigned long long last_pos = 1, last_size[1] = {group_size};
    long long inf_ll[1] = {0x7FFFFFFFFFFFFFFFLL};

    long long BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, V * (hop_cst + 1));
    init_T_offset<<<BLOCKS_NUM, THREADS_NUM>>>(T_offset_begin, T_offset_end, V * (hop_cst + 1));
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, group_size);
    init_T<<<BLOCKS_NUM, THREADS_NUM>>>(group_size, T + last_pos, H, nid, T_offset_begin, T_offset_end, out_edge, out_edge_weight, out_pointer, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    int print_tag = 0;
    unsigned long long zero = 0;
    for (int hop = 1; hop <= hop_cst; hop ++) { // generate the label with (hop = hop)
        if (last_size[0] == 0) break;

        // printf("hop: %d\n", hop);
        // step1 扩展
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        cudaMemcpy(T_pre_offset, last_size, sizeof(unsigned long long), cudaMemcpyHostToDevice);
        cudaMemcpy(T_after_offset, &zero, sizeof(unsigned long long), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();

        // cudaMemcpy(L + last_pos - 1, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
        // printf("size: %llu\n", last_size[0]);
        if (check_wb) {
            HSDL_gather_kernel_naive<THREADS_NUM> <<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, T_pre_offset, T + last_pos + last_size[0], 
                T_after_offset, D, out_edge, out_edge_weight, out_pointer, inv, source, hop);
            cudaDeviceSynchronize();
        } else {
            HSDL_gather_kernel<THREADS_NUM> <<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, T_pre_offset, T + last_pos + last_size[0], 
                T_after_offset, D, out_edge, out_edge_weight, out_pointer, inv, source, hop);
            cudaDeviceSynchronize();
        }
        CHECK_CUDA_KERNEL();
        
        last_pos += last_size[0];
        cudaMemcpy(last_size, T_after_offset, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
        
        // printf("size: %llu, %llu\n", last_pos, last_size[0]);
        
        if (last_size[0] == 0) break;
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        clearKernel_das <<<BLOCKS_NUM, THREADS_NUM>>> (D, T + last_pos, source, last_size[0]);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        // printf("clear done.\n");

        // long long *output;
        // if (print_tag) {
        //     output = (long long *)malloc(1000);
        //     cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
        //     cudaDeviceSynchronize();
        //     for (long long i = 0; i < last_size[0]; i++) {
        //         printf("gen1 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
        //                                                                     get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
        //     }
        // }

        // step2 sort
        // auto t1 = std::chrono::high_resolution_clock::now();
        // Sort_kernel(T, last_size[0], last_pos, D_sort_temp);
        // cudaDeviceSynchronize();
        // CHECK_CUDA_KERNEL();
        // auto t2 = std::chrono::high_resolution_clock::now();
        // double ms = std::chrono::duration<double, std::milli>(t2 - t1).count();
        // sort_time_record += ms / 1000.0;
        // printf("sort done.\n");

        // if (print_tag) {
        //     output = (long long *)malloc(1000);
        //     cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
        //     cudaDeviceSynchronize();
        //     for (long long i = 0; i < last_size[0]; i++) {
        //         printf("gen2 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
        //                                                                     get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
        //     }
        // }

        // step3 tranverse
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        Tranverse_kernel_no_CSR <<<BLOCKS_NUM, THREADS_NUM>>> (T + last_pos, T, H, T_offset_begin, T_offset_end, source, flag, T_after_offset, V);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        // printf("tranverse done.\n");
        
        // step4 gather
        Gather_kernel(T + last_pos, flag, last_size[0], D_sort_temp, d_num_selected);
        cudaMemcpy(&last_size, d_num_selected, sizeof(long long), cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();

        // if (print_tag) {
        //     cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
        //     cudaDeviceSynchronize();
        //     for (long long i = 0; i < last_size[0]; i++) {
        //         printf("gen3 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
        //                                                                     get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
        //     }
        // }

        // step5 update hash
        // if (hop < hop_cst) updateHas<<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, last_pos, H, last_size[0], T_offset_begin, T_offset_end, V, hop, hop_cst);
        updateHas<<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, last_pos, H, last_size[0], T_offset_begin, T_offset_end, source, V, hop, hop_cst);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        // printf("updateHas done.\n");
    }
    last_pos += last_size[0] - 1;
    BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_pos);
    clearKernel_has<<<BLOCKS_NUM, THREADS_NUM>>>(H, T + 1, source, last_pos, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    // printf("clearKernel done.\n");

    cudaMemcpy(L, T + 1, last_pos * sizeof(long long), cudaMemcpyDeviceToHost);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    L_size += last_pos;
    
    // BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, TABLE_SIZE);
    // check_hash_<<<BLOCKS_NUM, THREADS_NUM>>>(H);
    // cudaDeviceSynchronize();
    // CHECK_CUDA_KERNEL();

    return;
}