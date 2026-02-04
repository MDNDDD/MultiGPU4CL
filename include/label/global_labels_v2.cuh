// #ifndef GLOBAL_LABELS_V2_CUH
// #define GLOBAL_LABELS_V2_CUH
// #pragma once

// #include "definition/hub_def.h"
// #include "label/hop_constrained_two_hop_labels_v2.cuh"
// #include "HBPLL/hop_constrained_two_hop_labels.h"
// #include "memoryManagement/cuda_hashtable_v2.cuh"
// #include "memoryManagement/cuda_vector_v2.cuh"
// #include "memoryManagement/mmpool_v2.cuh"
// #include <cuda_runtime.h>
// #include <memoryManagement/cuda_vector.cuh>

// class hop_constrained_case_info_v2 {
// public:
//     // for generation
//     // labels
//     mmpool_v2<long long> *mmpool_labels = NULL;
//     mmpool_v2<T_item> *mmpool_T0 = NULL;
//     mmpool_v2<T_item> *mmpool_T1 = NULL;

//     // 64bits, hub_vertex 24bits, parent_vertex 24bits, hop 3bits, distance 10bits
//     cuda_vector_v2<long long> *L_cuda = NULL; // gpu res
//     cuda_vector_v2<T_item> *T0 = NULL; // T0
//     cuda_vector_v2<T_item> *T1 = NULL; // T1

//     // hash for distance
//     cuda_hashTable_v2<short> *L_hash;
//     cuda_hashTable_v2<short> *D_hash;

//     int **nid;
//     int *nid_size;

//     int *D_vector;
//     int *D_pare;
    
//     int *Num_T; // Num_T, Test use
//     int *Num_L;
//     std::pair<int, short> *T_push_back;
//     std::pair<int, short> *L_push_back;

//     // hop bounded
//     int thread_num = 1;
//     int hop_cst = 0;
//     int Distributed_Graph_Num = 0;
//     int use_2023WWW_GPU_version = 0;
//     int use_new_algo = 0;
    
//     // running time records
// 	double time_initialization = 0;
	
//     double time_generate_labels_step1 = 0;
//     double time_generate_labels_step2 = 0;
//     double time_generate_labels_step3 = 0;
//     double time_generate_labels_step4 = 0;
//     double time_generate_traverse_labels = 0;

//     double time_clean_labels_step1 = 0;
//     double time_clean_labels_step2 = 0;
//     double time_clean_labels_step3 = 0;
//     double time_clean_traverse_labels = 0;

// 	double time_total = 0;
//     double label_size = 0;

//     int L_size;
//     int _G_max;

//     hop_constrained_case_info_v2() {}

//     // Constructor
//     // mmpool_size_block is the total number of elements to store
//     // nodes_per_block is the required number of blocks
//     __host__ void init (int V, int hop_cst, int G_max, int thread_num, std::vector<std::vector<int> > graph_group) {
        
//         cudaError_t err;
//         size_t free_byte, total_byte;

//         L_size = V;
//         _G_max = G_max;

//         // Create three memory pools
//         // The first memory pool is used to store labels
//         cudaMallocManaged(&mmpool_labels, sizeof(mmpool_v2<long long>));
//         cudaDeviceSynchronize();
//         new (mmpool_labels) mmpool_v2<long long> (V, max((long long)V, (long long) G_max * V * (hop_cst) / 2 / nodes_per_block));
//         cudaDeviceSynchronize();

//         // The second memory pool is used to store T0
//         cudaMallocManaged(&mmpool_T0, sizeof(mmpool_v2<T_item>));
//         cudaDeviceSynchronize();
//         new (mmpool_T0) mmpool_v2<T_item> (G_max, (long long) G_max * V / 2 / nodes_per_block);
//         cudaDeviceSynchronize();

//         // The second memory pool is used to store T1
//         cudaMallocManaged(&mmpool_T1, sizeof(mmpool_v2<T_item>));
//         cudaDeviceSynchronize();
//         new (mmpool_T1) mmpool_v2<T_item> (G_max, (long long) G_max * V / 2 / nodes_per_block);
//         cudaDeviceSynchronize();

//         // Allocate the L_cuda memory pool
//         cudaMallocManaged(&L_cuda, (long long) V * sizeof(cuda_vector_v2<long long>)); // Allocate n cuda_vector Pointers
//         cudaDeviceSynchronize();
//         for (int i = 0; i < V; i++) {
//             new (L_cuda + i) cuda_vector_v2<long long> (mmpool_labels, i, (long long) G_max * hop_cst / nodes_per_block + 1);
//         }
//         cudaDeviceSynchronize();

//         // Allocate the T0 memory pool
//         cudaMallocManaged(&T0, (long long) G_max * sizeof(cuda_vector_v2<T_item>)); // Allocate n cuda_vector Pointers
//         cudaDeviceSynchronize();
//         for (int i = 0; i < G_max; i++) {
//             new (T0 + i) cuda_vector_v2<T_item> (mmpool_T0, i, V / 2 / nodes_per_block + 1);
//         }
//         cudaDeviceSynchronize();

//         // Allocate the T1 memory pool
//         cudaMallocManaged(&T1, (long long) G_max * sizeof(cuda_vector_v2<T_item>)); // Allocate n cuda_vector Pointers
//         cudaDeviceSynchronize();
//         for (int i = 0; i < G_max; i++) {
//             new (T1 + i) cuda_vector_v2<T_item> (mmpool_T1, i, V / 2 / nodes_per_block + 1);
//         }
//         cudaDeviceSynchronize();

//         // ready L_hash
//         cudaMallocManaged(&L_hash, (long long) thread_num * sizeof(cuda_hashTable_v2<short>));
//         cudaDeviceSynchronize();
//         for (int i = 0; i < thread_num; i++) {
//             new (L_hash + i) cuda_hashTable_v2 <short> ((long long) G_max * (hop_cst + 1));
//         }
//         cudaDeviceSynchronize();

//         // ready D_hashTable
//         cudaMallocManaged(&D_hash, (long long) thread_num * sizeof(cuda_hashTable_v2<short>));
//         cudaDeviceSynchronize();
//         for (int i = 0; i < thread_num; i++) {
//             new (D_hash + i) cuda_hashTable_v2 <short> (V);
//         }
//         cudaDeviceSynchronize();
        
//         // ready D_parent_vertex
//         cudaMallocManaged(&D_pare, (long long) thread_num * V * sizeof(int));
//         cudaDeviceSynchronize();

//         // ready D_vector
//         cudaMallocManaged(&D_vector, (long long) thread_num * V * sizeof(int));
//         cudaDeviceSynchronize();
        
//         // if (use_2023WWW_GPU_version) {
//         //     cudaMallocManaged(&Num_T, (long long) sizeof(int) * V);
//         //     cudaDeviceSynchronize();
//         //     cudaMallocManaged(&T_push_back, (long long) thread_num * V * 10 * sizeof(std::pair<int, int>));
//         //     cudaDeviceSynchronize();

//         //     cudaMallocManaged(&Num_L, (long long) sizeof(int) * V);
//         //     cudaDeviceSynchronize();
//         //     cudaMallocManaged(&L_push_back, (long long) thread_num * V * 10 * sizeof(std::pair<int, int>));
//         //     cudaDeviceSynchronize();
//         // } else {
//         cudaMallocManaged(&Num_T, (long long) V * sizeof(int));
//         cudaDeviceSynchronize();
//         cudaMallocManaged(&T_push_back, (long long) thread_num * V * sizeof(std::pair<int, int>));
//         cudaDeviceSynchronize();

//         cudaMallocManaged(&Num_L, (long long) V * sizeof(int));
//         cudaDeviceSynchronize();
//         cudaMallocManaged(&L_push_back, (long long) thread_num * V * sizeof(std::pair<int, int>));
//         cudaDeviceSynchronize();
//         // }
        
// 	    // cudaMemGetInfo(&free_byte, &total_byte);
//         // printf("Device memory: total %ld, free %ld\n", total_byte, free_byte);

//         err = cudaGetLastError(); // Check for kernel memory request errors
//         if (err != cudaSuccess) {
//             printf("init cuda error !: %s\n", cudaGetErrorString(err));
//         }
//     }

//     // set nid
//     __host__ void set_nid (int distributed_graph_num, std::vector<std::vector<int> > graph_group) {
//         Distributed_Graph_Num = distributed_graph_num;
//         cudaMallocManaged(&nid, sizeof(int*) * Distributed_Graph_Num);
//         cudaMallocManaged(&nid_size, sizeof(int) * Distributed_Graph_Num);
//         for (int j = 0; j < Distributed_Graph_Num; ++ j) {
//             cudaMallocManaged(&nid[j], sizeof(int) * graph_group[j].size());
//             nid_size[j] = graph_group[j].size();
//             for (int k = 0; k < graph_group[j].size(); ++k) {
//                 nid[j][k] = graph_group[j][k];
//             }
//         }
//     }

//     // Points in label
//     inline int cuda_vector_size() {
//         return L_size;
//     }

//     // destructor
//     __host__ void destroy_L_cuda(int G_max) {
//         for (int i = 0; i < L_size; ++i) {
//             L_cuda[i].~cuda_vector_v2 <long long> ();
//         }
//         cudaFree(L_cuda);
        
//         for (int i = 0; i < G_max; ++i) {
//             T0[i].~cuda_vector_v2 <T_item> ();
//             T1[i].~cuda_vector_v2 <T_item> ();
//             // printf("gmax_destory: %d\n", i);
//         }
        
//         cudaFree(T0);
//         cudaFree(T1);
        
//         for (int i = 0; i < thread_num; ++i) {
//             L_hash[i].~cuda_hashTable_v2 <short> ();
//             D_hash[i].~cuda_hashTable_v2 <short> ();
//         }
        
//         for (int i = 0; i < Distributed_Graph_Num; ++ i) {
//             cudaFree(nid[i]);
//         }
//         cudaFree(nid);
//         cudaFree(nid_size);
        
//         cudaFree(L_hash);
//         cudaFree(D_hash);
        
//         cudaFree(D_vector);
//         cudaFree(D_pare);
        
//         cudaFree(Num_T);
//         cudaFree(T_push_back);
//         cudaFree(Num_L);
//         cudaFree(L_push_back);
        
//         mmpool_labels->~mmpool_v2();
//         mmpool_T0->~mmpool_v2();
//         mmpool_T1->~mmpool_v2();
//         cudaFree(mmpool_labels);
//         cudaFree(mmpool_T0);
//         cudaFree(mmpool_T1);
//     }

//     // for clean_v1
//     long long *L_start = nullptr;
//     long long *L_end = nullptr;
//     int *node_id = nullptr;
//     int *nid_to_tid = nullptr;
//     long long *L = nullptr; // label on gpu
//     int *mark = nullptr; // mark the label clean state
//     int *hash_array = nullptr;
//     // int *L_size = nullptr;

//     // for clean_v2
//     int *in_L = nullptr;
//     long long *L2 = nullptr; // label on gpu
// };

// #endif

#ifndef GLOBAL_LABELS_V2_CUH
#define GLOBAL_LABELS_V2_CUH
#pragma once

#include <definition/hub_def.h>
#include <definition/pair_hash.hpp>
#include <definition/cuda_err.cuh>

#include <graph/csr_graph.hpp>
#include <label/hop_constrained_two_hop_labels_v2.cuh>
#include <HBPLL/hop_constrained_two_hop_labels.h>
// #include "memoryManagement/cuda_hash.cuh"

#include <memoryManagement/cuda_hashtable_v2.cuh>
#include <memoryManagement/cuda_vector_v2.cuh>
#include <memoryManagement/mmpool_v2.cuh>
#include <memoryManagement/cuda_vector.cuh>

#include <cuda_runtime.h>
#include <fstream>
#include <sstream>
#include <malloc.h>
#include <omp.h>

#define TABLE_SIZE_CLEAN 2999999929
#define TABLE_SIZE_CLEAN_MINUS_ONE 2999999928
// #define TABLE_SIZE_CLEAN 1549736851
// #define TABLE_SIZE_CLEAN_MINUS_ONE 1549736850
#define TABLE_SIZE 1599999983
#define TABLE_SIZE_MINUS_ONE 1599999982
// #define TABLE_SIZE 1499999983
// #define TABLE_SIZE_MINUS_ONE 1499999982
// #define TABLE_SIZE 998244353
// #define TABLE_SIZE_MINUS_ONE 998244352
#define MOD 4194301

// #define TABLE_SIZE 1073741824
// #define TABLE_SIZE_MINUS_ONE 1073741823

// 64bits, to_vertex 24bits, hub_vertex 24bits, hop 3bits, distance 10bits
__forceinline__ __host__ __device__ int get_to_vertex (long long x) {
    return ((x >> 37) & 0x1FFFFFF);
}
__forceinline__ __host__ __device__ int get_hub_vertex (long long x) {
    return ((x >> 13) & 0xFFFFFF); // 24-bit mask
}
__forceinline__ __host__ __device__ int get_hop (long long x) {
    return ((x >> 10) & 0x7); // 3-bit mask
}
__forceinline__ __host__ __device__ int get_distance (long long x) {
    return (x & 0x3FF); // 10-bit mask
}
__forceinline__ __host__ __device__ long long get_label (const int &to_vertex, const int &hub_vertex, const int &hop, const int &distance) {
    return ((long long)(to_vertex) << 37) | ((long long)(hub_vertex) << 13) | (hop << 10) | (distance);
}

// __forceinline__ __host__ __device__ long long _get_label (int to_vertex, int hub_vertex, int hop, int distance) {
//     return ((long long)(to_vertex) << 37) | ((long long)(hub_vertex) << 13) | (hop << 10) | (distance);
// }

class hop_constrained_case_info_v2 {
public:
    // for generation
    int hop_cst;
    int thread_num;
    int use_2023WWW_GPU_version;
    int use_new_algo;
    int Distributed_Graph_Num;

    long long *T, *T_offset_begin, *T_offset_end;
    long long *has, *das;
    int **nid, *nid_size;
    char *flag;
    long long *D_sort_temp;

    // for clean
    long long *has_clean;
    long long *L_clean;
    long long *L_start, *L_end;
    char *mark;
    long long *sort_temp;
    long long last_size;

    // for generation
    hop_constrained_case_info_v2() {}

    // Constructor
    __host__ void init (int V, int hop_cst, int G_max, int thread_num, std::vector<std::vector<int> > graph_group) {
        long long max_val[1] = {0x7FFFFFFFFFFFFFFFLL};
        cudaMallocManaged(&has, (long long)TABLE_SIZE * sizeof(long long));
        cudaMemset(has, 0ll, (long long)TABLE_SIZE * sizeof(long long));
        cudaMallocManaged(&das, (long long)TABLE_SIZE * sizeof(long long));
        cudaMemset(das, 0ll, (long long)TABLE_SIZE * sizeof(long long));
        cudaMallocManaged(&T_offset_begin, (hop_cst + 1) * (V + 1) * sizeof(long long));
        cudaMallocManaged(&T_offset_end, (hop_cst + 1) * (V + 1) * sizeof(long long));
        cudaDeviceSynchronize();

        size_t free, total;
        cudaMemGetInfo(&free, &total);
        std::cout << "free memory: " << free / (1024 * 1024) << " MB" << std::endl;
        std::cout << "total memory: " << total / (1024 * 1024) << " MB" << std::endl;
    
        // T 45%, D_sort_temp 45%, flag 10%
        // T 42%, D_sort_temp 42%, flag 7%
        // long long T_size = (free * 0.50) / 8;
        // long long flag_size = (free * 0.05) / 1;
        // long long D_sort_temp_size = (free * 0.35) / 8;
        long long T_size = (free * 0.40) / 8;
        long long flag_size = (free * 0.05) / 1;
        long long D_sort_temp_size = (free * 0.35) / 8;
        printf("T, flag, D_sort size: %lld %lld %lld\n", T_size, flag_size, D_sort_temp_size);
        cudaMallocManaged(&T, T_size * sizeof(long long));
        cudaMallocManaged(&flag, flag_size * sizeof(char));
        cudaMemset(flag, 0, flag_size * sizeof(char));
        cudaMallocManaged(&D_sort_temp, D_sort_temp_size * sizeof(long long));
        cudaDeviceSynchronize();

        cudaMemGetInfo(&free, &total);
        std::cout << "free memory: " << free / (1024 * 1024) << " MB" << std::endl;
        std::cout << "total memory: " << total / (1024 * 1024) << " MB" << std::endl;

        cudaMemcpy(T, max_val, sizeof(long long), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();
    }

    // set nid
    __host__ void set_nid (int distributed_graph_num, std::vector<std::vector<int> > graph_group) {
        Distributed_Graph_Num = distributed_graph_num;
        cudaMallocManaged(&nid, Distributed_Graph_Num * sizeof(int*));
        cudaMallocManaged(&nid_size, sizeof(int) * Distributed_Graph_Num);
        cudaDeviceSynchronize();

        std::vector<int> sz;
        for (int i = 0; i < Distributed_Graph_Num; ++ i) {
            int num_nodes = graph_group[i].size();
            cudaMallocManaged((nid + i), num_nodes * sizeof(int));
            cudaDeviceSynchronize();
            cudaMemcpy(nid[i], graph_group[i].data(), num_nodes * sizeof(int), cudaMemcpyHostToDevice);
            cudaDeviceSynchronize();
            sz.push_back(graph_group[i].size());
        }
        cudaMemcpy(nid_size, sz.data(), Distributed_Graph_Num * sizeof(int), cudaMemcpyHostToDevice);
        cudaDeviceSynchronize();
        CHECK_CUDA_KERNEL();

        // Distributed_Graph_Num = distributed_graph_num;
        // cudaMallocManaged(&nid, sizeof(int*) * Distributed_Graph_Num);
        // cudaMallocManaged(&nid_size, sizeof(int) * Distributed_Graph_Num);
        // for (int j = 0; j < Distributed_Graph_Num; ++ j) {
        //     cudaMallocManaged(&nid[j], sizeof(int) * graph_group[j].size());
        //     nid_size[j] = graph_group[j].size();
        //     for (int k = 0; k < graph_group[j].size(); ++k) {
        //         nid[j][k] = graph_group[j][k];
        //     }
        // }
    }

    // destructor
    __host__ void destroy_L_cuda() {
        cudaFree(T);
        cudaFree(has);
        cudaFree(das);
        cudaFree(T_offset_begin);
        cudaFree(T_offset_end);
        for (int i = 0; i < Distributed_Graph_Num; ++ i) {
            cudaFree(nid[i]);
        }
        cudaFree(nid);
        cudaFree(nid_size);
        cudaFree(flag);
        cudaFree(D_sort_temp);
        CHECK_CUDA_KERNEL();
    }

    // print memory infomation
    inline void print_memory_info() {
        std::cout << "===== memory status =====\n";
        std::ifstream memInfo("/proc/meminfo");
        if (!memInfo.is_open()) {
            std::cerr << "error: failed to open /proc/meminfo\n";
            return;
        }
        long totalMem = 0, freeMem = 0, availableMem = 0;
        std::string line;
        while (std::getline(memInfo, line)) {
            if (line.find("MemTotal") == 0) {
                std::sscanf(line.c_str(), "MemTotal: %ld KB", &totalMem);
            } else if (line.find("MemFree") == 0) {
                std::sscanf(line.c_str(), "MemFree: %ld KB", &freeMem);
            } else if (line.find("MemAvailable") == 0) {
                std::sscanf(line.c_str(), "MemAvailable: %ld KB", &availableMem);
            }
        }
        memInfo.close();

        std::cout << "total RAM:  " << totalMem / 1024 << " MB\n";
        std::cout << "free RAM:   " << freeMem / 1024 << " MB\n";
        std::cout << "available:  " << availableMem / 1024 << " MB (better indicator)\n";
    }

    // init clean for memory
    __host__ void init_clean (int V, std::vector<std::vector<hop_constrained_two_hop_label>> &res, 
        CSR_graph<weight_type> &csr_graph, long long L_size, std::unordered_map<std::pair<int, int>, int, PairHash> &edge_id) {

        last_size = 1;
        cudaMallocManaged(&has_clean, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMemset(has_clean, 0ll, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMallocManaged(&L_start, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_end, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_clean, (long long)(L_size + 1) * sizeof(long long));
        cudaMallocManaged(&mark, (long long)(L_size + 1) * sizeof(char));
        cudaMemset(mark, 1, (long long)(L_size + 1) * sizeof(char));
        cudaMallocManaged(&sort_temp, 1500000000ll * sizeof(long long));
        cudaDeviceSynchronize();

        // long long pos = 1;
        // for (int i = 0; i < V; ++ i) {
        //     L_start[i] = pos;
        //     for (int j = 0; j < res[i].size(); ++ j) {
        //         auto& lbl = res[i][j];
        //         if (edge_id.count(std::make_pair(i, lbl.parent_vertex)) == 0) {
        //             L_clean[pos] = get_label(csr_graph.OUTs_Neighbor_start_pointers[i], lbl.hub_vertex, lbl.hop, lbl.distance);
        //         } else {
        //             L_clean[pos] = get_label(edge_id[std::make_pair(i, lbl.parent_vertex)], lbl.hub_vertex, lbl.hop, lbl.distance);
        //             if (lbl.hop == 0) {
        //                 lbl.parent_vertex = i;
        //             }
        //         }
        //         pos ++;
        //     }
        //     L_end[i] = pos;
        //     if (i < 20) printf("L_start, L_end: %d, %lld, %lld\n", i, L_start[i], L_end[i]);
        //     if (V - i < 20) printf("L_start, L_end: %d, %lld, %lld\n", i, L_start[i], L_end[i]);
        //     if (i % 200000 == 0) {
        //         printf("swap clear vector %d\n", i);
        //     }
        // }
        // L_start[V] = pos;

        L_clean[0] = 0x7FFFFFFFFFFFFFFFLL;
        print_memory_info();
        L_start[0] = 1;
        for (int i = 0; i < V; ++ i) {
            L_start[i + 1] = L_start[i] + res[i].size();
        }
        long long pos = L_start[V];

        #pragma omp parallel for schedule(dynamic, 64)
        for (int i = 0; i < V; ++ i) {
            long long base = L_start[i];
            for (int j = 0; j < res[i].size(); ++ j) {
                auto& lbl = res[i][j];
                if (edge_id.count(std::make_pair(i, lbl.parent_vertex)) == 0) {
                    L_clean[base + j] = get_label(csr_graph.OUTs_Neighbor_start_pointers[i], lbl.hub_vertex, lbl.hop, lbl.distance);
                } else {
                    L_clean[base + j] = get_label(edge_id[std::make_pair(i, lbl.parent_vertex)], lbl.hub_vertex, lbl.hop, lbl.distance);
                    if (lbl.hop == 0) {
                        lbl.parent_vertex = i;
                    }
                }
            }
            L_end[i] = base + res[i].size();

            if (i % 50000 == 0) {
                #pragma omp critical
                {
                    std::cout << "processed i = " << i << " / " << V << std::endl;
                }
            }
        }

        // int device;
        // cudaGetDevice(&device);
        // cudaMemAdvise(L_clean, L_start[20000] * sizeof(long long), cudaMemAdviseSetPreferredLocation, device);
        // cudaMemPrefetchAsync(L_clean, L_start[20000] * sizeof(long long), device, 0);

        long long label_cnt = 0;
        for (int i = 0; i < V; ++ i) {
            label_cnt += res[i].size();
            if (i % 50000 == 0) {
                printf("count label: %d, %lld, %.6lf, %.6lf\n", i, res[i].size(), label_cnt / (double)pos, L_end[i] / (double)pos);
            } 
        }

        print_memory_info();
    }
};

#endif