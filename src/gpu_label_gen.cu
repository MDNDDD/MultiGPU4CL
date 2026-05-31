#include <gpu_label_gen/gpu_label_gen.cuh>
#include <cub/cub.cuh>
#include <cuda_runtime.h>
#include <nvml.h>
#include <atomic>
#include <cuda_runtime.h>
#include <core/cuda_error.cuh>
#include <cub/device/device_select.cuh>

typedef size_t SIZE_TYPE;
const int MAX_BLOCKS_NUM = 96 * 8;
#define FULL_MASK 0xffffffff
#define CALC_BLOCKS_NUM(ITEMS_PER_BLOCK, CALC_SIZE) min(MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
#define CALC_BLOCKS_NUM_LL(ITEMS_PER_BLOCK, CALC_SIZE) min((long long)MAX_BLOCKS_NUM, (CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)
#define CALC_BLOCKS_NUM_NOLIMIT(ITEMS_PER_BLOCK, CALC_SIZE) ((CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)

__forceinline__ __device__ int gen_hash_pos (const long long &x) {
    return x % TABLE_SIZE;
}

__forceinline__ __device__ void gen_hash_insert (long long* d_table, long long d_input) {
    long long pos = gen_hash_pos(d_input & (~0ull << 10));
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

__forceinline__ __device__ long long gen_remap_source(const long long &x, int *source) {
    return get_label(source[get_to_vertex(x)], get_hub_vertex(x), get_hop(x), get_distance(x));
}

__forceinline__ __device__ bool gen_das_insert (long long *d_table, int *source, long long d_input) {
    long long pos = gen_hash_pos(gen_remap_source(d_input, source) & (~0ull << 10));
    long long old;
    while (true) {
        old = d_table[pos];
        if (old == 0) {
            long long expected = 0;
            if (atomicCAS((unsigned long long*)&d_table[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
                return 1;
            }
        } else {
            if ((gen_remap_source(old, source) >> 10) == (gen_remap_source(d_input, source) >> 10)) {
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
            }
            pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
        }
    }
}

__global__ void gen_das_clear (long long *d_table, long long *d_input, int *source, int inputSize) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;

    long long old;
    long long d_input_change = gen_remap_source(d_input[idx], source);
    long long pos = gen_hash_pos(d_input_change & (~0ull << 10));
    while (true) {
        old = d_table[pos];
        if ((gen_remap_source(old, source) >> 10) == (gen_remap_source(d_input[idx], source) >> 10)) {
            d_table[pos] = 0;
            d_input[idx] = old;
            return;
        }
        pos = (pos == TABLE_SIZE_MINUS_ONE) ? 0 : pos + 1;
    }
}

__global__ void gen_hash_clear (long long *d_table, long long* d_input, int *source, int inputSize, int hop_cst) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;
    
    long long item = d_input[idx];
    item = gen_remap_source(item, source);
    int hop = get_hop(item);
    for (int i = hop; i <= hop_cst; i ++) {
        long long pos = gen_hash_pos(item & (~0ull << 10));
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

__forceinline__ __device__ int gen_hash_query (long long *d_table, long long d_input) {
    long long pos = gen_hash_pos(d_input & (~0ull << 10));
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
__global__ void gen_gather (long long *T_pre, unsigned long long *T_pre_offset, long long *T_after, unsigned long long *T_after_offset, 
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
            row_begin = out_pointer[src];
            row_end = out_pointer[src + 1];
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
                    neighbour = get_label(inv[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    if (hub_vertex < out_edge[gather] && gen_das_insert(das, source, neighbour)) {
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
                    neighbour = get_label(inv[gather], hub_vertex, hop, get_distance(u) + out_edge_weight[gather]);
                    if (hub_vertex < out_edge[gather] && gen_das_insert(das, source, neighbour)) {
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
                neighbour = get_label(inv[e], hub_vertex, hop, get_distance(u) + out_edge_weight[e]);
                if (hub_vertex < out_edge[e] && gen_das_insert(das, source, neighbour)) {
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

inline void gen_flagged_select (long long *T, char *flag, unsigned long long last_size, long long *D_sort_temp, long long *d_num_selected, cudaStream_t stream = 0) { 
    void* d_temp_storage = nullptr;
    size_t temp_storage_bytes = 0;
    cub::DeviceSelect::Flagged(d_temp_storage, temp_storage_bytes, T, flag, T, d_num_selected, last_size, stream, false);
    cub::DeviceSelect::Flagged(D_sort_temp, temp_storage_bytes, T, flag, T, d_num_selected, last_size, stream, false);
}

inline void gen_radix_sort (long long *T, unsigned long long last_size, unsigned long long last_pos, long long *D_sort_temp, cudaStream_t stream = 0) { 
    void *d_temp_storage = nullptr;
    size_t temp_storage_bytes = 0;
    cub::DeviceRadixSort::SortKeys(d_temp_storage, temp_storage_bytes, T + last_pos, T + last_pos, last_size, 0, sizeof(long long) * 8, stream);
    cub::DeviceRadixSort::SortKeys(D_sort_temp, temp_storage_bytes, T + last_pos, T + last_pos, last_size, 0, sizeof(long long) * 8, stream);
}

__global__ void gen_traverse_prune (
    const long long * __restrict__ T1, 
    long long * __restrict__ T2, 
    long long * __restrict__ has, 
    const long long * __restrict__ T_offset_begin, 
    const long long * __restrict__ T_offset_end,
    int * source,
    char * __restrict__ flag, 
    const unsigned long long * __restrict__ T_size, 
    int V
) {
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
    
    for (int i = 1; i < hop; i ++) {
        long long idx = (long long) V * i + to_vertex;
        long long posl = __ldg(T_offset_begin + idx);
        long long posr = __ldg(T_offset_end + idx);
        for (long long j = posl; j < posr; j ++) {
            long long TT = T2[j];
            int mid_vertex = get_hub_vertex(TT);
            if (get_distance(TT) + gen_hash_query(has, get_label(hub_vertex, mid_vertex, hop - i, 0)) <= dis) {
                flag[tid] = 0;
                return;
            }
        }
    }
}

__global__ void gen_update_hash (long long *T, long long T_start, long long *has, unsigned long long T_size, 
    long long *T_offset_begin, long long *T_offset_end, int *source, long long V, int hop, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= T_size) return;

    long long TT = T[tid];
    TT = gen_remap_source(TT, source);
    for (int i = hop; i < hop_cst; i ++) {
        gen_hash_insert (has, TT);
        TT += (1 << 10);
    }
    if (get_to_vertex(TT) != source[get_to_vertex(T[tid - 1])]) {
        T_offset_begin[V * hop + get_to_vertex(TT)] = T_start + tid;
    }
    if (get_to_vertex(TT) != source[get_to_vertex(T[tid + 1])]) {
        T_offset_end[V * hop + get_to_vertex(TT)] = T_start + tid + 1;
    }
}

__global__ void gen_init_frontier (int group_size, long long *T, long long *has, int *nid, long long *T_offset_begin, long long *T_offset_end, 
    int *out_edge, int *out_edge_weight, int *out_pointer, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= group_size) return;

    int v = nid[tid];
    long long TT = get_label(v, v, 0, 0);
    for (int i = 0; i <= hop_cst; i ++) {
        gen_hash_insert (has, TT);
        TT += (1 << 10);
    }
    T[tid] = get_label(out_pointer[v], v, 0, 0);
    T_offset_begin[v] = tid + 1;
    T_offset_end[v] = tid + 2;
}

__global__ void gen_init_offsets (long long *T_offset_begin, long long *T_offset_end, long long V_hop) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= V_hop) return;

    T_offset_begin[tid] = 0;
    T_offset_end[tid] = 0;
}

__global__ void gen_hash_check(long long *h_table) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid <= TABLE_SIZE_MINUS_ONE && h_table[tid]) {
        printf("check hash error. %d, %d, %d, %d\n", get_to_vertex(h_table[tid]), get_hub_vertex(h_table[tid]),
                    get_hop(h_table[tid]), get_distance(h_table[tid]));
    }
}

// the proces of generate labels
void gpu_label_gen (CSR_graph<weight_type>& input_graph, hop_constrained_case_info_gpu *info, long long *L, 
        long long &L_size, std::vector<int>& nid_vec, int nid_vec_id, double &sort_time_record, LabelGenTimings &timings) {
    
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

    cudaDeviceSynchronize();
    auto t_init_start = std::chrono::high_resolution_clock::now();
    
    unsigned long long *T_pre_offset, *T_after_offset;
    long long *d_num_selected;
    cudaMalloc(&T_pre_offset, sizeof(unsigned long long));
    cudaMalloc(&T_after_offset, sizeof(unsigned long long));
    cudaMalloc(&d_num_selected, sizeof(long long));
    cudaStream_t copy_stream;
    cudaStreamCreate(&copy_stream);
    cudaDeviceSynchronize();

    unsigned long long last_pos = 1, last_size[1] = {group_size};
    long long inf_ll[1] = {0x7FFFFFFFFFFFFFFFLL};

    long long BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, V * (hop_cst + 1));
    gen_init_offsets<<<BLOCKS_NUM, THREADS_NUM>>>(T_offset_begin, T_offset_end, V * (hop_cst + 1));
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, group_size);
    gen_init_frontier<<<BLOCKS_NUM, THREADS_NUM>>>(group_size, T + last_pos, H, nid, T_offset_begin, T_offset_end, out_edge, out_edge_weight, out_pointer, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    cudaMemcpyAsync(L + last_pos, T + last_pos, group_size * sizeof(long long), cudaMemcpyDeviceToHost);
    
    auto t_init_end = std::chrono::high_resolution_clock::now();
    timings.init_time += std::chrono::duration<double>(t_init_end - t_init_start).count();
    
    int print_tag = 0;
    unsigned long long zero = 0;
    for (int hop = 1; hop <= hop_cst; hop ++) { // generate the label with (hop = hop)
        if (last_size[0] == 0) break;

        printf("hop: %d\n", hop);
        cudaDeviceSynchronize();
        auto t_expand_start = std::chrono::high_resolution_clock::now();
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        cudaMemcpy(T_pre_offset, last_size, sizeof(unsigned long long), cudaMemcpyHostToDevice);
        cudaMemcpy(T_after_offset, &zero, sizeof(unsigned long long), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();

        gen_gather<THREADS_NUM> <<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, T_pre_offset, T + last_pos + last_size[0], 
                T_after_offset, D, out_edge, out_edge_weight, out_pointer, inv, source, hop);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        
        last_pos += last_size[0];
        cudaMemcpy(last_size, T_after_offset, sizeof(unsigned long long), cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
        
        auto t_expand_end = std::chrono::high_resolution_clock::now();
        timings.expand_time += std::chrono::duration<double>(t_expand_end - t_expand_start).count();
        
        if (last_size[0] == 0) break;
        
        // clear das
        cudaDeviceSynchronize();
        auto t_clear_start = std::chrono::high_resolution_clock::now();
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        gen_das_clear <<<BLOCKS_NUM, THREADS_NUM>>> (D, T + last_pos, source, last_size[0]);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        auto t_clear_end = std::chrono::high_resolution_clock::now();
        timings.clear_das_time += std::chrono::duration<double>(t_clear_end - t_clear_start).count();
        printf("clear done.\n");

        long long *output;
        if (print_tag) {
            output = (long long *)malloc(1000);
            cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
            cudaDeviceSynchronize();
            for (long long i = 0; i < last_size[0]; i++) {
                printf("gen1 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
                                                                            get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
            }
        }

        cudaDeviceSynchronize();
        auto t_sort_start = std::chrono::high_resolution_clock::now();
        gen_radix_sort(T, last_size[0], last_pos, D_sort_temp);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        auto t_sort_end = std::chrono::high_resolution_clock::now();
        timings.sort_time += std::chrono::duration<double>(t_sort_end - t_sort_start).count();
        printf("sort done.\n");

        if (print_tag) {
            output = (long long *)malloc(1000);
            cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
            cudaDeviceSynchronize();
            for (long long i = 0; i < last_size[0]; i++) {
                printf("gen2 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
                                                                            get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
            }
        }

        cudaDeviceSynchronize();
        auto t_tranverse_start = std::chrono::high_resolution_clock::now();
        BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_size[0]);
        gen_traverse_prune <<<BLOCKS_NUM, THREADS_NUM>>> (T + last_pos, T, H, T_offset_begin, T_offset_end, source, flag, T_after_offset, V);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        auto t_tranverse_end = std::chrono::high_resolution_clock::now();
        timings.tranverse_time += std::chrono::duration<double>(t_tranverse_end - t_tranverse_start).count();
        printf("tranverse done.\n");

        cudaDeviceSynchronize();
        auto t_gather_start = std::chrono::high_resolution_clock::now();
        gen_flagged_select(T + last_pos, flag, last_size[0], D_sort_temp, d_num_selected);
        cudaMemcpy(&last_size, d_num_selected, sizeof(long long), cudaMemcpyDeviceToHost);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        auto t_gather_end = std::chrono::high_resolution_clock::now();
        timings.gather_time += std::chrono::duration<double>(t_gather_end - t_gather_start).count();

        cudaMemcpyAsync(L + last_pos, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost, copy_stream);

        if (print_tag) {
            cudaDeviceSynchronize();
            cudaMemcpy(output, T + last_pos, last_size[0] * sizeof(long long), cudaMemcpyDeviceToHost);
            cudaDeviceSynchronize();
            for (long long i = 0; i < last_size[0]; i++) {
                printf("gen3 output, to, par, hub, h, dis: %d, %d, %d, %d, %d\n", input_graph.ARRAY_source[get_to_vertex(output[i])], input_graph.OUTs_Edges[get_to_vertex(output[i])],\
                                                                            get_hub_vertex(output[i]), get_hop(output[i]), get_distance(output[i]));
            }
        }

        cudaStreamSynchronize(copy_stream);
        auto t_update_start = std::chrono::high_resolution_clock::now();
        gen_update_hash<<<BLOCKS_NUM, THREADS_NUM>>>(T + last_pos, last_pos, H, last_size[0], T_offset_begin, T_offset_end, source, V, hop, hop_cst);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
        auto t_update_end = std::chrono::high_resolution_clock::now();
        timings.update_hash_time += std::chrono::duration<double>(t_update_end - t_update_start).count();
        printf("gen_update_hash done.\n");
    }
    last_pos += last_size[0] - 1;
    cudaDeviceSynchronize();
    auto t_finalize_start = std::chrono::high_resolution_clock::now();
    BLOCKS_NUM = CALC_BLOCKS_NUM_NOLIMIT(THREADS_NUM, last_pos);
    gen_hash_clear<<<BLOCKS_NUM, THREADS_NUM>>>(H, T + 1, source, last_pos, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();

    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    L_size += last_pos;
    auto t_finalize_end = std::chrono::high_resolution_clock::now();
    timings.finalize_time += std::chrono::duration<double>(t_finalize_end - t_finalize_start).count();
    
    cudaStreamDestroy(copy_stream);

    return;
}