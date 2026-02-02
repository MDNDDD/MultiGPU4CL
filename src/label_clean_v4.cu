// #include <iostream>
// #include <cuda_runtime.h>
// #include <HBPLL/gpu_clean.cuh>
// #include <utility>

// #define THREADS_PER_BLOCK 256
// #define clean_thread_num 1000

// int *L2_pos_2;
// int *L_size_2;
// long long L_tot_2 = 0;
// vector<long long> label_id;

// // 64bits, hub_vertex 24bits, parent_vertex 24bits, hop 3bits, distance 10bits
// __host__ __device__ __inline__ int get_hub_vertex (long long x) {
//     return (x >> 37);
// }
// __host__ __device__ __inline__ int get_parent_vertex (long long x) {
//     return (x >> 13) & ((1 << 24) - 1);
// }
// __host__ __device__ __inline__ int get_hop (long long x) {
//     return (x >> 10) & ((1 << 3) - 1);
// }
// __host__ __device__ __inline__ int get_distance (long long x) {
//     return (x) & ((1 << 10) - 1);
// }
// __host__ __device__ __inline__ long long get_label (int hub_vertex, int parent_vertex, int hop, int distance) {
//     return ((long long)hub_vertex << 37) | ((long long)parent_vertex << 13) | ((long long)hop << 10) | ((long long)distance);
// }

// inline bool operator < (hop_constrained_two_hop_label a, hop_constrained_two_hop_label b) {
//     if (a.hub_vertex == b.hub_vertex) {
//         return a.parent_vertex < b.parent_vertex;
//     } else {
//         return a.hub_vertex < b.hub_vertex;
//     }
// }
// inline bool operator > (hop_constrained_two_hop_label a, hop_constrained_two_hop_label b) {
//     if (a.hub_vertex == b.hub_vertex) {
//         return a.parent_vertex < b.parent_vertex;
//     } else {
//         return a.hub_vertex < b.hub_vertex;
//     }
// }

// // label sort, according to hub_vertex
// inline bool cmp_LL(std::pair<long long, int> x, std::pair<long long, int> y) {
//     int vx1 = get_hub_vertex(x.first);
//     int vx2 = get_parent_vertex(x.first);
//     int vy1 = get_hub_vertex(y.first);
//     int vy2 = get_parent_vertex(y.first);
//     return min(vx1, vx2) > min(vy1, vy2);
// }

// // get hash_table
// __global__ void get_hash_v3 (int V, int hop_cst, int vid, long long L_start_vid, long long L_end_vid, int *in_L, long long *L, long long *L_start, long long *L_end, int *hash_array) {
//     int tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < 0 || tid >= L_end_vid - L_start_vid) {
//         return;
//     }
//     long long LL = L[L_start_vid + tid]; // get the label need to get hash

//     // gets the properties of the label
//     int hub_vertex = get_hub_vertex(LL);
//     int hop = get_hop(LL);
//     int dis = get_distance(LL);
//     int offset = hub_vertex * (hop_cst + 1) + hop;

//     // update the hash table
//     for (int x = hop; x <= hop_cst; ++ x) {
//         if (hash_array[offset] > dis) {
//             atomicMin(&hash_array[offset ++], dis);
//         } else {
//             break;
//         }
//     }

//     // mark whether the vertex is in the hash
//     in_L[hub_vertex] = 1;
//     // atomicExch(&in_L[hub_vertex], 1);
// }

// // clean hash_table
// __global__ void clear_hash_v3 (int V, int hop_cst, int vid, long long L_start_vid, long long L_end_vid, int *in_L, long long *L, long long *L_start, long long *L_end, int *hash_array) {
//     int tid = blockIdx.x * blockDim.x + threadIdx.x;
//     if (tid < 0 || tid >= L_end_vid - L_start_vid) {
//         return;
//     }
//     long long LL = L[L_start_vid + tid]; // get the label need to get hash

//     // gets the properties of the label
//     int hub_vertex = get_hub_vertex(LL);
//     int hop = get_hop(LL);
//     int offset = hub_vertex * (hop_cst + 1) + hop;

//     // clear the hash table
//     for (int x = hop; x <= hop_cst; ++ x) {
//         if (hash_array[offset] != (1 << 14)) {
//             hash_array[offset ++] = (1 << 14);
//         } else {
//             break;
//         }
//     }

//     // clear the in_L
//     // atomicExch(&in_L[hub_vertex], 0);
//     in_L[hub_vertex] = 0;
// }

// // The core part of clean code uses hash to determine whether each label needs to be cleaned
// __global__ void clean_check_v3 (int hop_cst, int vid, long long L_tot, int *in_L, long long *L, int *hash_array, int *mark) {
//     long long tid = blockIdx.x * blockDim.x + threadIdx.x;

//     if (tid < 0 || tid >= L_tot) {
//         return;
//     }

//     if (mark[tid]) return;

//     long long LL = L[tid];
    
//     int st_vertex = (LL >> 37);
//     int ed_vertex = (LL >> 13) & ((1 << 24) - 1);
    
//     // These two vertices don't exist in L
//     if (!in_L[st_vertex] || !in_L[ed_vertex]) {
//         return;
//     }

//     int hop_now = (LL >> 10) & ((1 << 3) - 1);
//     int dis = (LL) & ((1 << 10) - 1);
//     st_vertex = st_vertex * (hop_cst + 1) + hop_now;
//     ed_vertex = ed_vertex * (hop_cst + 1);

//     // Enumerate hop to merge labels
//     for (int i = hop_now; i >= 0; -- i) {
//         if (hash_array[st_vertex --] + hash_array[ed_vertex ++] <= dis) {
//             mark[tid] = 1;
//             return;
//         }
//     }

//     return;
// }

// // Clear video memory and memory space
// void gpu_clean_clear_v3 (hop_constrained_case_info_v2 *info_gpu) {
//     L_tot_2 = 0;
//     label_id.clear();
//     label_id.shrink_to_fit();
//     // free(L_size_2);

//     // cudaFree(&info_gpu->L_start);
//     // cudaFree(&info_gpu->L_end);
//     // cudaFree(&info_gpu->L);
//     // cudaFree(&info_gpu->L2);
//     // cudaFree(&info_gpu->mark);
//     // cudaFree(&info_gpu->hash_array);
//     // cudaFree(&info_gpu->in_L);
//     // cudaDeviceSynchronize();
// }

// void gpu_clean_init_init_v3(graph_v_of_v<int> &input_graph, hop_constrained_case_info_v2 *info_gpu, int K) {
//     int V = input_graph.size();
//     L2_pos_2 = (int*) malloc(((long long)(V + 1)) * sizeof(int));
//     L_size_2 = (int*) malloc(sizeof(int) * V);

//     cudaMallocManaged(&info_gpu->L_start, ((long long) (V + 1)) * sizeof(long long));
//     cudaDeviceSynchronize();
//     cudaMallocManaged(&info_gpu->L_end, ((long long) (V + 1)) * sizeof(long long));
//     cudaDeviceSynchronize();
//     cudaMallocManaged(&info_gpu->hash_array, (long long) V * sizeof(int) * (K + 1));
//     cudaDeviceSynchronize();
//     cudaMallocManaged(&info_gpu->in_L, (long long) V * sizeof(int));
//     cudaDeviceSynchronize();
// }

// void gpu_clean_init_v3 (graph_v_of_v<int> &input_graph, const vector<vector<hop_constrained_two_hop_label>> &use_L,
// vector<vector<hop_constrained_two_hop_label>> &clean_L, vector<vector<long long>> &label_id_2to1, hop_constrained_case_info_v2 *info_gpu, Graph_pool<int> &graph_pool, int tc, int K) {
//     gpu_clean_clear_v3 (info_gpu);
    
//     // label_id
//     int V = input_graph.size();

//     vector<vector<hop_constrained_two_hop_label>> transfer_L;
//     transfer_L.resize(V);

//     // start get L
//     // use_L is a label used to clean labels
//     hop_constrained_two_hop_label temp;
//     for (int i = 0; i < V; ++ i) {
//         for (int j = 0; j < use_L[i].size(); ++ j) {
//             temp.hub_vertex = use_L[i][j].hub_vertex;
//             temp.hop = use_L[i][j].hop;
//             temp.distance = use_L[i][j].distance;
//             temp.parent_vertex = i;
//             transfer_L[temp.parent_vertex].push_back(temp);
//         }
//     }

//     printf("clean stage 1 !!\n");

//     vector<long long> L_flat;

//     // cudaError_t err = cudaMallocManaged(&info_gpu->L_start, ((long long) (V + 1)) * sizeof(long long));
//     // cudaDeviceSynchronize();
//     // if (err != cudaSuccess) {
//     //     printf("error in cudaMallocManaged !!!!\n");
//     // }
//     // cudaMallocManaged(&info_gpu->L_end, ((long long) (V + 1)) * sizeof(long long));
//     // cudaDeviceSynchronize();

//     printf("clean stage 2 !!\n");

//     for (int i = 0; i < V; ++i) L_size_2[i] = 0;

//     long long point = 0;
//     int x;

//     printf("clean stage 3 !!\n");

//     for (int i = 0; i < V; ++i) {
//         info_gpu->L_start[i] = point;
//         int _size = transfer_L[i].size();
//         for (int j = 0; j < _size; j++) {
//             L_flat.push_back(get_label(transfer_L[i][j].hub_vertex, transfer_L[i][j].parent_vertex, 
//                                        transfer_L[i][j].hop, transfer_L[i][j].distance));
//         }
//         point += _size;
//         info_gpu->L_end[i] = point;
//         L_size_2[i] = _size;
//     }

//     printf("clean stage 4 !!\n");

//     // get L
//     cudaMallocManaged(&info_gpu->L, (long long) L_flat.size() * sizeof(long long));
//     cudaDeviceSynchronize();
    
//     printf("clean stage 5 !!\n");

//     cudaMemcpy(info_gpu->L, L_flat.data(), (long long) L_flat.size() * sizeof(long long), cudaMemcpyHostToDevice);
//     cudaDeviceSynchronize();
//     // end get L

//     printf("clean stage 2 !!\n");

//     // start get L2
//     // clean_L is the label that needs to be cleaned
//     vector<vector<std::pair<hop_constrained_two_hop_label, long long>>> transfer_L_v2;
//     transfer_L_v2.resize(V);
    
//     for (int i = 0; i < V; ++ i) {
//         for (int j = 0; j < clean_L[i].size(); ++ j) {
//             hop_constrained_two_hop_label temp;
//             temp.hub_vertex = i;
//             temp.hop = clean_L[i][j].hop;
//             temp.distance = clean_L[i][j].distance;
//             temp.parent_vertex = clean_L[i][j].hub_vertex;
//             transfer_L_v2[clean_L[i][j].hub_vertex].push_back(std::make_pair(temp, label_id_2to1[i][j]));
//         }
//     }

//     vector<std::pair<long long, long long>> L_flat_v2;
//     L_flat.clear();
//     L_flat.shrink_to_fit();

//     for (int i = 0; i < V; ++ i) {
//         int _size = transfer_L_v2[i].size();
//         for (int j = 0; j < _size; j++) {
//             hop_constrained_two_hop_label ll = transfer_L_v2[i][j].first;
//             L_flat_v2.push_back(std::make_pair(get_label(ll.hub_vertex, ll.parent_vertex, 
//                                        ll.hop, ll.distance), transfer_L_v2[i][j].second));
//         }
//         L_tot_2 += _size;
//     }
    
//     printf("clean stage 3 !!\n");

//     // get L2
//     stable_sort(L_flat_v2.begin(), L_flat_v2.end(), cmp_LL);
    
//     for (int i = 0; i <= V; ++ i) L2_pos_2[i] = 0;
//     label_id.resize(L_flat_v2.size());
//     for (int i = 0; i < L_flat_v2.size(); ++ i) {
//         int now_mn = min(get_hub_vertex(L_flat_v2[i].first), get_parent_vertex(L_flat_v2[i].first));
//         L_flat.push_back(L_flat_v2[i].first);
//         L2_pos_2[now_mn] = i;
//         label_id[i] = L_flat_v2[i].second;
//         // label_id.push_back();
//     }
//     for (int i = 0; i < V; ++ i) L2_pos_2[i] = L2_pos_2[i + 1];
    
    
//     printf("clean stage 4 !!\n");

//     for (int i = V; i > 0; -- i) {
//         if (i % 5000 == 0) {
//             printf("%d\n", i);
//         }
//         if (L2_pos_2[i] == 0) {
//             L2_pos_2[i] = L2_pos_2[i + 1];
//         }
//     }
    
//     // for(int i = V - 1000; i < V; ++ i) printf("%d, ", L2_pos_2[i]);
//     // for(int i = 0; i < V; ++ i) {
//     //     // printf("%d ", L2_pos_2[i]);
//     //     if (L2_pos_2[i] == -1) {
//     //         L2_pos_2[i] = L2_pos_2[i + 1];
//     //     }
//     //     // L2_pos_2[i] = max(L2_pos_2[i], L2_pos_2[i - 1]);
//     // }
    
//     // for(int i = 0; i <= V; ++ i) {
//     //     if (L2_pos_2[i] == -1) {
//     //         puts("--------------------111111111111111111111111111 !!!!!");
//     //     }
//     // }
//     // get L2
//     cudaMallocManaged(&info_gpu->L2, (long long) L_flat.size() * sizeof(long long));
//     cudaDeviceSynchronize();
//     cudaMemcpy(info_gpu->L2, L_flat.data(), (long long) L_flat.size() * sizeof(long long), cudaMemcpyHostToDevice);
//     cudaDeviceSynchronize();

//     cudaMallocManaged(&info_gpu->mark, (long long) L_tot_2 * sizeof(int));
//     cudaDeviceSynchronize();
//     cudaMemset(info_gpu->mark, 0, (long long) L_tot_2 * sizeof(int));
//     cudaDeviceSynchronize();
    
//     for (long long i = 0; i < (long long) V * (K + 1); i++){
//         info_gpu->hash_array[i] = (1 << 14);
//     }
//     cudaDeviceSynchronize();

//     // cudaMallocManaged(&info_gpu->in_L, (long long) V * sizeof(int));
//     // cudaDeviceSynchronize();
// }

// void gpu_clean_v3 (graph_v_of_v<int> &input_graph, hop_constrained_case_info_v2 *info_gpu, 
// vector<vector<hop_constrained_two_hop_label>> &res, vector<int> &check_tot, int thread_num) {
//     int V = input_graph.size();
//     int K = info_gpu->hop_cst;

//     long long *L_start = info_gpu->L_start;
//     long long *L_end = info_gpu->L_end;

//     long long *L = info_gpu->L;
//     long long *L2 = info_gpu->L2;
//     int *in_L = info_gpu->in_L;

//     int *mark = info_gpu->mark;
//     int *hash_array = info_gpu->hash_array; // first dim size is V * (K + 1)

//     int start_id = V, end_id, start_node_id, end_node_id;
    
//     clock_t start_time, end_time;
//     double time1 = 0.0, time2 = 0.0, time3 = 0.0;

//     for (int i = 0; i < V; ++ i) {
//         if (L_size_2[i]) {
//             auto start1 = std::chrono::high_resolution_clock::now();
//             get_hash_v3 <<< (L_size_2[i] + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, THREADS_PER_BLOCK >>>
//             (V, K, i, L_start[i], L_end[i], in_L, L, L_start, L_end, hash_array);
//             cudaDeviceSynchronize();
//             auto end1 = std::chrono::high_resolution_clock::now();
//             time1 += std::chrono::duration_cast<std::chrono::nanoseconds>(end1 - start1).count() / 1e9;
            
//             auto start2 = std::chrono::high_resolution_clock::now();
//             clean_check_v3 <<< (L2_pos_2[i] + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, THREADS_PER_BLOCK >>> 
//             (K, i, L2_pos_2[i], in_L, L2, hash_array, mark);
//             cudaDeviceSynchronize();
//             auto end2 = std::chrono::high_resolution_clock::now();
//             time2 += std::chrono::duration_cast<std::chrono::nanoseconds>(end2 - start2).count() / 1e9;

//             auto start3 = std::chrono::high_resolution_clock::now();
//             clear_hash_v3 <<< (L_size_2[i] + THREADS_PER_BLOCK - 1) / THREADS_PER_BLOCK, THREADS_PER_BLOCK >>> 
//             (V, K, i, L_start[i], L_end[i], in_L, L, L_start, L_end, hash_array);
//             cudaDeviceSynchronize();
//             auto end3 = std::chrono::high_resolution_clock::now();
//             time3 += std::chrono::duration_cast<std::chrono::nanoseconds>(end3 - start3).count() / 1e9;
//         }
//     }
    
//     auto start4 = std::chrono::high_resolution_clock::now();
//     for (long long i = 0; i < L_tot_2; ++ i) {
//         if (info_gpu->mark[i]) {
//             check_tot[label_id[i]] = 0;
//         }
//     }
//     auto end4 = std::chrono::high_resolution_clock::now();

//     printf("time1: %.6lf\n", time1);
//     printf("time2: %.6lf\n", time2);
//     printf("time3: %.6lf\n", time3);

//     // info_gpu->time_clean_traverse_labels += std::chrono::duration_cast<std::chrono::nanoseconds>(end4 - start4).count() / 1e9;

//     // info_gpu->time_clean_labels_step1 += time1;
//     // info_gpu->time_clean_labels_step2 += time2;
//     // info_gpu->time_clean_labels_step3 += time3;

//     return;
// }
// /*

// Time_Generate_Labels_Total: 4.763159
// Time_Generate_Labels_Total: 4.766120
// Time_Generate_Labels_Total: 4.773733
// Time_Generate_Labels_Total: 4.782318
// Device memory before: total 51033931776, free 42583523328
// Device memory after: total 51033931776, free 48730275840
// Device memory after clean: total 51033931776, free 48730275840
// gpu clean group: 0 791 0 26425
// gpu clean group: 0 791 26425 196591
// gpu clean group: 791 196591 0 28104
// gpu clean group: 791 196591 28104 196591
// ./run.sh: line 105: 126992 Segmentation fault      (core dumped) ./build/bin/Test "$dataset" "$upper_k" "$algo" "$output" "$gmax_1" "$thread" "$clean_label_num_1" 1

// */

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