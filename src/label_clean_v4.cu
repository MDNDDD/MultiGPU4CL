#include <iostream>
#include <cuda_runtime.h>
#include <HBPLL/gpu_clean.cuh>
#include <utility>
#include <definition/cuda_err.cuh>

#define THREADS_NUM_CLEAN 256
#define CALC_BLOCKS_NUM_NO(ITEMS_PER_BLOCK, CALC_SIZE) ((CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)

__forceinline__ __device__ long long change_label_ (long long x, int* source) {
    return get_label(source[get_to_vertex(x)], get_hub_vertex(x), get_hop(x), get_distance(x));
}

__forceinline__ __device__ long long hash_pos_clean (long long x) {
    x = _get_label(get_hub_vertex(x), get_to_vertex(x), get_hop(x), get_distance(x));
    return x % TABLE_SIZE_CLEAN;
}

__forceinline__ __device__ void insert_has_clean (long long* has_clean, long long d_input) {
    long long pos = hash_pos_clean (d_input & (~0ull << 10));
    // printf("init_hash_clean LL: %lld %lld\n", d_input, pos);
    long long old;
    while (true) {
        old = has_clean[pos];
        if (old == 0) {
            long long expected = 0;
            if (atomicCAS((unsigned long long*)&has_clean[pos], *(unsigned long long*)&expected, *(unsigned long long*)&d_input) == *(unsigned long long*)&expected) {
                break;
            }
        } else {
            if ((old >> 10) == (d_input >> 10)) {
                // has_clean[pos] = d_input;
                atomicMin(&has_clean[pos], d_input);
                return;
            }
            pos = (pos == TABLE_SIZE_CLEAN_MINUS_ONE) ? 0 : pos + 1;
        }
    }
}

__global__ void clear_hash_clean (long long *has_clean, long long *d_input, int *source, long long inputSize, int hop_cst) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;
    long long item = change_label_ (d_input[idx], source);
    int hop = get_hop(item);
    for (int i = hop; i <= hop_cst; i ++) {
        long long pos = hash_pos_clean (item & (~0ull << 10));
        while (true) {
            if (has_clean[pos]) {
                has_clean[pos] = 0;
                pos = (pos == TABLE_SIZE_CLEAN_MINUS_ONE) ? 0 : pos + 1;
            } else {
                break;
            }
        }
        item += (1 << 10);
    }
}

__forceinline__ __device__ int query_hash_clean (long long *has_clean, long long d_input) {
    long long pos = hash_pos_clean (d_input & (~0ull << 10));
    long long old;
    int cnt = 0;
    while (true) {
        cnt ++;
        old = has_clean[pos];
        if (old == 0) return 1e5;
        if ((old >> 10) == (d_input >> 10)) {
            return (int)((old) & 0x3FF);
        }
        pos = (pos == TABLE_SIZE_CLEAN_MINUS_ONE) ? 0 : pos + 1;
    }
}

__global__ void init_hash_clean (long long *L, long long *has_clean, int *source, long long siz, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < siz) {
        long long LL = change_label_ (L[tid], source);
        int hop = get_hop(LL);
        for (int i = hop; i <= hop_cst; i ++) {
            insert_has_clean (has_clean, LL);
            LL += (1 << 10);
        }
    }
}

// __global__ void clear_label_clean (long long *L_clean, long long *L, long long *L_start,
// long long *L_end, long long *has_clean, char *mark, int *source, long long clean_num, long long start) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid >= clean_num) return;

//     int to_vertex = source[get_to_vertex(L_clean[tid])];
//     int hub_vertex = get_hub_vertex(L_clean[tid]);
//     int hop = get_hop(L_clean[tid]);
//     int distance = get_distance(L_clean[tid]);
//     if (hop == 0) return;
//     for (long long i = L_start[hub_vertex]; i < L_end[hub_vertex]; i ++) {
//         if (hop > get_hop(L[i]) && (get_hop(L[i]) && get_distance(L[i]) + 
//         query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(L[i]), hop - get_hop(L[i]), 0)) <= distance)
//         || (get_hop(L[i]) == 0 && query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(L[i]), hop - get_hop(L[i]) - 1, 0)) <= distance)
//         ) {
//             mark[start + tid] = 0;
//             return;
//         }
//     }
// }

__global__ void clear_label_clean (long long *L_clean, long long *L, long long *L_start,
long long *L_end, long long *has_clean, char *mark, int *source, long long clean_num, long long start) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= clean_num) return;

    long long label_clean = L_clean[tid];
    int to_vertex = source[get_to_vertex(label_clean)];
    int hub_vertex = get_hub_vertex(label_clean);
    int hop = get_hop(label_clean);
    int distance = get_distance(label_clean);

    if (hop == 0) return;
    
    long long begin = L_start[hub_vertex];
    long long end = L_end[hub_vertex];

    for (long long i = begin; i < end; i ++) {
        long long label_L = L[i];
        int hop_i = get_hop(label_L);

        if (hop > hop_i && (hop_i && get_distance(label_L) + 
        query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(label_L), hop - hop_i, 0)) <= distance)
        || (hop_i == 0 && query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(label_L), hop - hop_i - 1, 0)) <= distance)
        ) {
            mark[start + tid] = 0;
            return;
        }
    }
}

__global__ void check_hash(long long *has_clean) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid <= TABLE_SIZE_CLEAN_MINUS_ONE && has_clean[tid]) {
        printf("error !!!!!\n");
    }
}

__forceinline__ __device__ long long get_source (long long to_vertex, int *source) {
    if (to_vertex == 0x7FFFFFFFFFFFFFFFLL) {
        return 0x7FFFFFFFFFFFFFFFLL;
    } else {
        return source[get_to_vertex(to_vertex)];
    }
}

__global__ void update_L (long long *L, long long *L_start, long long *L_end, int *source,
    long long start_pos, long long L_size) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid >= L_size) return;

    long long LL = L[tid];
    long long pos = start_pos + tid;
    long long cur_src = get_source(LL, source);

    if (cur_src != get_source(L[tid - 1], source)) {
        L_start[cur_src] = pos;
    }
    if (cur_src != get_source(L[tid + 1], source)) {
        L_end[cur_src] = pos + 1;
    }
}

void gpu_clean_v4 (CSR_graph<weight_type>& input_graph, long long L_clean_start, long long L_clean_end, 
        hop_constrained_case_info_v2 *info_gpu, long long &last_pos) {
    int hop_cst = info_gpu->hop_cst;
    long long *L = info_gpu->L_clean;
    long long *L_start = info_gpu->L_start;
    long long *L_end = info_gpu->L_end;
    long long *has_clean = info_gpu->has_clean;
    long long *sort_temp = info_gpu->sort_temp;
    int *source = input_graph.source;
    int *inv = input_graph.inv;
    char *mark = info_gpu->mark;
    long long last_size;

    // init
    L_clean_start = L_start[L_clean_start];
    L_clean_end = L_end[L_clean_end - 1];
    info_gpu->last_size = last_pos = last_size = L_clean_start;
    
    long long clean_num = L_clean_end - L_clean_start;
    printf("clean_num: %lld, %lld, %lld\n", clean_num, L_clean_start, L_clean_end);
    if (clean_num <= 0) return;
    long long BLOCKS_NUM = CALC_BLOCKS_NUM_NO(THREADS_NUM_CLEAN, clean_num);

    // init hash
    init_hash_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(L + L_clean_start, has_clean, source, clean_num, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();

    // void *d_temp_storage = nullptr;
    // size_t temp_storage_bytes = 0;
    // cub::DeviceRadixSort::SortKeysDescending(d_temp_storage, temp_storage_bytes, L + L_clean_start, L + L_clean_start, clean_num);
    // cudaDeviceSynchronize();
    // cub::DeviceRadixSort::SortKeysDescending(sort_temp, temp_storage_bytes, L + L_clean_start, L + L_clean_start, clean_num);
    // cudaDeviceSynchronize();

    // clean label
    clear_label_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(L + L_clean_start, L, L_start, L_end, has_clean, mark, source, clean_num, L_clean_start);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    // clean hash
    clear_hash_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(has_clean, L + L_clean_start, source, clean_num, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();

    // flag gather
    long long *d_num_selected;
    void *d_temp_storage = nullptr;
    size_t temp_storage_bytes = 0;
    cudaMallocManaged(&d_num_selected, sizeof(long long));
    cudaDeviceSynchronize();
    cub::DeviceSelect::Flagged(d_temp_storage, temp_storage_bytes, L + L_clean_start, mark + L_clean_start, L + last_size, d_num_selected, clean_num);
    cudaDeviceSynchronize();
    cub::DeviceSelect::Flagged(sort_temp, temp_storage_bytes, L + L_clean_start, mark + L_clean_start, L + last_size, d_num_selected, clean_num);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();

    // update labels
    BLOCKS_NUM = CALC_BLOCKS_NUM_NO(THREADS_NUM_CLEAN, (*d_num_selected));
    update_L<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(L + last_size, L_start, L_end, source, last_size, *d_num_selected);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    info_gpu->last_size += (*d_num_selected);

    // printf("d_num_selected, last_size: %lld, %lld\n", (*d_num_selected), info_gpu->last_size);
    // BLOCKS_NUM = CALC_BLOCKS_NUM_NO(THREADS_NUM_CLEAN, TABLE_SIZE_CLEAN);
    // check_hash<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(has_clean);
    // cudaDeviceSynchronize();
    // CHECK_CUDA_KERNEL();

    return;
}