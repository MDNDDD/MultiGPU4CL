#ifndef GPU_LABEL_MANAGER_CUH
#define GPU_LABEL_MANAGER_CUH
#pragma once

#include <core/types.h>
#include <utils/pair_hash.hpp>
#include <core/cuda_error.cuh>

#include <graph/csr_graph.hpp>
#include <label/label_types.cuh>
// #include "memoryManagement/cuda_hash.cuh"

// #include <memoryManagement/cuda_hashtable_v2.cuh>
// #include <memoryManagement/cuda_vector_v2.cuh>
// #include <memoryManagement/mmpool_v2.cuh>
// #include <memory/cuda_vector.cuh>

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
// #define MOD 4194301

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

class hop_constrained_case_info_gpu {
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
    hop_constrained_case_info_gpu() {}

    // Constructor
    __host__ void init (int V, int hop_cst, int G_max, int thread_num, std::vector<std::vector<int> > graph_group) {
        long long max_val[1] = {0x7FFFFFFFFFFFFFFFLL};

        cudaMallocManaged(&has, (long long) TABLE_SIZE * sizeof(long long));
        cudaMemset(has, 0ll, (long long) TABLE_SIZE * sizeof(long long));
        cudaMallocManaged(&das, (long long) TABLE_SIZE * sizeof(long long));
        cudaMemset(das, 0ll, (long long) TABLE_SIZE * sizeof(long long));

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
        // long long T_size = (free * 0.90) / 8;
        // long long flag_size = (free * 0.35) / 1;
        // long long D_sort_temp_size = (free * 0.95) / 8;
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
        CSR_graph<weight_type> &csr_graph, long long L_size, std::unordered_map<std::pair<int, int>, int, PairHash> &edge_id, int G_max) {

        last_size = 1;
        cudaMallocManaged(&has_clean, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMemset(has_clean, 0ll, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMallocManaged(&L_start, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_end, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_clean, (long long)(L_size + 1) * sizeof(long long));
        cudaMallocManaged(&mark, (long long)(L_size + 1) * sizeof(char));
        cudaMemset(mark, 1, (long long)(L_size + 1) * sizeof(char));
        cudaMallocManaged(&sort_temp, 800000000ll * sizeof(long long));
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

        #pragma omp parallel for schedule(dynamic, 128)
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