#include <iostream>
#include <cuda_runtime.h>
#include <HBPLL/gpu_clean.cuh>
#include <utility>
#include <definition/cuda_err.cuh>

#define THREADS_NUM_CLEAN 256
#define INT_MAX_ 0x3f3f3f3f
#define CALC_BLOCKS_NUM_NO(ITEMS_PER_BLOCK, CALC_SIZE) ((CALC_SIZE - 1) / ITEMS_PER_BLOCK + 1)

__constant__ int _V;
__forceinline__ __device__ long long change_label_ (const long long &x, int* source) {
    return get_label(source[get_to_vertex(x)], get_hub_vertex(x), get_hop(x), get_distance(x));
}
__forceinline__ __device__ long long hash_pos_clean (const long long &x) {
    return get_label(get_hub_vertex(x), get_to_vertex(x), get_hop(x), get_distance(x)) % TABLE_SIZE_CLEAN;
}

__forceinline__ __device__ void mod_hash_inf (int *has, int *nid, int *vid, int hub, int tar, int hop, int hop_cst, int value) {
    long long index1 = (long long) vid[tar] * _V * (hop_cst + 1);
    has[index1 + hub * (hop_cst + 1) + hop] = value;
}
__forceinline__ __device__ void mod_hash (int *has, int *nid, int *vid, int hub, int tar, int hop, int hop_cst, int value) {
    long long index1 = (long long) vid[tar] * _V * (hop_cst + 1);
    atomicMin(&has[index1 + hub * (hop_cst + 1) + hop], value);
}
__forceinline__ __device__ int get_hash (int *has, int *nid, int *vid, int hub, int tar, int hop, int hop_cst) {
    long long index1 = (long long) vid[tar] * _V * (hop_cst + 1);
    return has[index1 + hub * (hop_cst + 1) + hop];
}

__global__ void clear_hash_clean (long long *has_clean, long long *d_input, int *nid, int *vid, int *source, long long inputSize, int hop_cst) {
    long long idx = threadIdx.x + blockIdx.x * blockDim.x;
    if (idx >= inputSize) return;
    long long item = change_label_ (d_input[idx], source);
    int hop = get_hop(item);
    for (int i = hop; i <= hop_cst; i ++) {
        // if (get_to_vertex(item) != idx) printf("shit!!!\n");
        mod_hash_inf ((int*)has_clean, nid, vid, get_hub_vertex(item), get_to_vertex(item), get_hop(item), hop_cst, INT_MAX_);
        item += (1 << 10);
    }
}

__global__ void init_hash_clean (long long *L, long long *has_clean, int *nid, int *vid, int *source, long long siz, int hop_cst) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid < siz) {
        long long LL = change_label_ (L[tid], source);
        int hop = get_hop(LL);
        for (int i = hop; i <= hop_cst; i ++) {
            // if (get_to_vertex(LL) != tid) printf("shit!!!\n");
            mod_hash ((int*)has_clean, nid, vid, get_hub_vertex(LL), get_to_vertex(LL), get_hop(LL), hop_cst, get_distance(LL)); // tag_hash
            LL += (1 << 10);
        }
    }
}

__global__ void clear_label_clean (long long *L_clean, long long *L, int *nid, int *vid, long long *L_start,
long long *L_end, long long *has_clean, char *mark, int *source, long long clean_num, long long start, int hop_cst) {
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

        // get_hash((int *)has_clean, nid, vid, get_hub_vertex(label_L), to_vertex, hop - hop_i, hop_cst)
        if (hop > hop_i && (hop_i && get_distance(label_L) + 
        get_hash((int *)has_clean, nid, vid, get_hub_vertex(label_L), to_vertex, hop - hop_i, hop_cst) <= distance)
        || (hop_i == 0 && get_hash((int *)has_clean, nid, vid, get_hub_vertex(label_L), to_vertex, hop - hop_i - 1, hop_cst) <= distance)
        ) {
            mark[start + tid] = 0;
            return;
        }
        // if (hop > hop_i && (hop_i && get_distance(label_L) + 
        // query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(label_L), hop - hop_i, 0)) <= distance)
        // || (hop_i == 0 && query_hash_clean(has_clean, get_label(to_vertex, get_hub_vertex(label_L), hop - hop_i - 1, 0)) <= distance)
        // ) {
        //     mark[start + tid] = 0;
        //     return;
        // }
    }
}

__global__ void check_hash(long long *has_clean) {
    long long tid = blockIdx.x * blockDim.x + threadIdx.x;
    if (tid <= TABLE_SIZE_CLEAN_MINUS_ONE && has_clean[tid] < 1e6) {
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
    
    int V = input_graph.INs_Neighbor_start_pointers.size() - 1;
    printf("V: %d\n", V);
    cudaMemcpyToSymbol(_V, &V, sizeof(int));
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
    int *vid; int *nid;
    cudaMallocManaged(&vid, V * sizeof(int));
    cudaMallocManaged(&nid, V * sizeof(int));
    cudaDeviceSynchronize();
    for (int i = L_clean_start; i < L_clean_end; i ++) {
        vid[i] = i - L_clean_start;
        nid[i - L_clean_start] = i;
    }
    
    L_clean_start = L_start[L_clean_start];
    L_clean_end = L_end[L_clean_end - 1];
    info_gpu->last_size = last_pos = last_size = L_clean_start;

    long long clean_num = L_clean_end - L_clean_start;
    printf("clean_num: %lld, %lld, %lld\n", clean_num, L_clean_start, L_clean_end);
    if (clean_num <= 0) return;
    long long BLOCKS_NUM = CALC_BLOCKS_NUM_NO(THREADS_NUM_CLEAN, clean_num);

    // init hash
    init_hash_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(L + L_clean_start, has_clean, nid, vid, source, clean_num, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();

    // void *d_temp_storage = nullptr;
    // size_t temp_storage_bytes = 0;
    // cub::DeviceRadixSort::SortKeysDescending(d_temp_storage, temp_storage_bytes, L + L_clean_start, L + L_clean_start, clean_num);
    // cudaDeviceSynchronize();
    // cub::DeviceRadixSort::SortKeysDescending(sort_temp, temp_storage_bytes, L + L_clean_start, L + L_clean_start, clean_num);
    // cudaDeviceSynchronize();

    // clean label
    clear_label_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(L + L_clean_start, L, nid, vid, L_start, L_end, has_clean, mark, source, clean_num, L_clean_start, hop_cst);
    cudaDeviceSynchronize();
    CHECK_CUDA_KERNEL();
    
    // clean hash
    clear_hash_clean<<<BLOCKS_NUM, THREADS_NUM_CLEAN>>>(has_clean, L + L_clean_start, nid, vid, source, clean_num, hop_cst);
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