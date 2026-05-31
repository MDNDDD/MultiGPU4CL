#include <bits/stdc++.h>
#include <boost/random.hpp>
#include <boost/signals2/signal.hpp>
#include <iomanip>

#include <utils/pair_hash.hpp>

#include <cpu_label_gen/cpu_label_gen.hpp>
#include <gpu_label_gen/gpu_label_gen.cuh>
#include <gpu_label_gen/gpu_label_manager.cuh>
#include <gpu_label_gen/gpu_label_clean.cuh>

#include <partition/graph_partition.cuh>
#include <partition/graph_pool.hpp>

#include <graph/ldbc_graph.hpp>
#include <graph/csr_graph.hpp>
#include <graph/graph_v_of_v.hpp>
#include <graph/graph_v_of_v_generate_random_graph.hpp>
#include <graph/graph_v_of_v_hop_constrained_shortest_path.hpp>
#include <graph/graph_v_of_v_hop_constrained_shortest_distance.hpp>
#include <graph/graph_v_of_v_update_vertexIDs_by_degrees_large_to_small.hpp>

#include <checker/checker.cuh>

#include <core/gpu_warmup.cuh>

boost::random::mt19937 boost_random_time_seed { static_cast<std::uint32_t>(std::time(0)) };

std::vector<std::vector<hop_constrained_two_hop_label>> L_hybrid;

hop_constrained_case_info_cpu info_cpu;
hop_constrained_case_info_gpu *info_gpu;

graph_v_of_v<int> instance_graph;
CSR_graph<weight_type> csr_graph;
Graph_pool<int> graph_pool;

std::unordered_map<std::pair<int, int>, int, PairHash> edge_id;

std::vector<Query> queries;
double time_query_dis_total = 0.0, time_query_path_total = 0.0;
double time_hop_dijkstra_query_dis_total = 0.0, time_hop_dijkstra_query_path_total = 0.0;

void read_graph(int &generate_new_graph, int &V, int &E, std::string &data_path) {
    if (generate_new_graph) {
        instance_graph = graph_v_of_v_generate_random_graph<int>(V, E, 1, 100, 1, boost_random_time_seed);
        instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph);
        instance_graph.txt_save("../data/simple_iterative_tests.txt");
    } else {
        V = 0, E = 0;
        instance_graph.txt_read(data_path);
        instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph);
        V = instance_graph.size();
        for (int i = 0; i < V; ++ i) {
            E += instance_graph[i].size();
        }
    }

    LDBC<weight_type> graph(V);
    graph.graph_v_of_v_to_LDBC(instance_graph);
    csr_graph = toCSR(graph);
    printf("generation graph successful.\n");
}

inline void sub_graph(int &use_cd, int &V, int &E, int &G_max, int &Distributed_Graph_Num, double &time_cd_total) {
    if (use_cd == 0) {
        graph_pool.graph_group.resize(Distributed_Graph_Num);
        int Nodes_Per_Graph = (V - 1) / Distributed_Graph_Num + 1;
        for (int i = 0; i < Distributed_Graph_Num; ++ i) {
            for (int j = Nodes_Per_Graph * i; j < Nodes_Per_Graph * (i + 1); ++ j) {
                if (j >= V) break;
                graph_pool.graph_group[i].push_back(j);
            }
        }
        G_max = V / Distributed_Graph_Num + 1;
    } else if (use_cd == 1) {
        auto begin = std::chrono::high_resolution_clock::now();
        generate_Group_CDLP(instance_graph, graph_pool.graph_group, G_max);
        auto end = std::chrono::high_resolution_clock::now();
        time_cd_total = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        for (int i = 0; i < graph_pool.graph_group.size(); i ++) {
            G_max = std::max(G_max, (int) graph_pool.graph_group[i].size());
        }
        Distributed_Graph_Num = graph_pool.graph_group.size();
    }
}

void set_info(int &algo, int &hop_cst, int &thread_num, int &CPU_Gen_Num, int &GPU_Gen_Num) {
    info_cpu.upper_k = hop_cst;
	info_cpu.use_rank_prune = 1;
	info_cpu.use_2023WWW_generation = 0;
    info_cpu.use_2023WWW_generation_optimized = 1;
    info_cpu.use_GPU_version_generation = 0;
    info_cpu.use_GPU_version_generation_optimized = 0;
	info_cpu.use_canonical_repair = 0;
    info_cpu.thread_num = thread_num;
    printf("init CPU_info successful.\n");

    info_gpu = new hop_constrained_case_info_gpu();
    info_gpu->hop_cst = hop_cst;
    info_gpu->thread_num = thread_num;
    info_gpu->use_2023WWW_GPU_version = 0;
    info_gpu->use_new_algo = 0;
    printf("init GPU_info successful.\n");
}

int main(int argc, char** argv) {

    srand(time(0));
    int iteration_source_times = 2000, iteration_terminal_times = 2000;
    int V = 5000, E = 30000, hop_cst = 5, G_max = 400, Distributed_Graph_Num = 1, thread_num = 50;
    int check_correctness = 1, check_path = 1, use_cd = 1, cpu_type = 0;
    int CPU_Gen_Num = 0, GPU_Gen_Num = 4, CPU_Clean_Num = 0, GPU_Clean_Num = 4;
    std::string data_path, out_put_path;

    double time_cd_total = 0.0, sort_time_record = 0.0;

    data_path = argv[1];
    hop_cst = std::stoi(argv[2]);
    out_put_path = argv[3];
    G_max = std::stoi(argv[4]);
    cpu_type = std::stoi(argv[5]);

    read_query(data_path.substr(0, data_path.rfind(".e")) + "_queries.txt");

    instance_graph.txt_read(data_path);
    V = instance_graph.vertex_num(), E = instance_graph.edge_num();
    instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph);
    sub_graph(use_cd, V, E, G_max, Distributed_Graph_Num, time_cd_total);
    printf("V, E, G_max, Distributed_Graph_Num: %d, %d, %d, %d\n", V, E, G_max, Distributed_Graph_Num);

    LDBC<weight_type> graph(V);
    graph.graph_v_of_v_to_LDBC(instance_graph);
    csr_graph = toCSR(graph, &edge_id);

    info_gpu = new hop_constrained_case_info_gpu();
    info_gpu->hop_cst = hop_cst;
    info_gpu->set_nid(Distributed_Graph_Num, graph_pool.graph_group);
    info_gpu->init(V, hop_cst, G_max, thread_num, graph_pool.graph_group);

    info_cpu.upper_k = hop_cst;
    info_cpu.use_rank_prune = 1;
    info_cpu.use_2023WWW_generation = cpu_type ? 1 : 0;
    info_cpu.use_2023WWW_generation_optimized = cpu_type ? 0 : 1;
    info_cpu.thread_num = thread_num;
    hop_constrained_two_hop_labels_generation_init(instance_graph, info_cpu);

    L_hybrid.resize(V);

    long long *L;
    cudaMallocHost(&L, 10000000000ll * sizeof(long long));
    long long delta_L = 0, tot_L = 0;

    LabelGenTimings total_timings;

    priority_queue<Executive_Core> pq_gen; Executive_Core x;
    std::vector<long long> L_size_before(V, 0);
    for (int i = 0; i < CPU_Gen_Num; ++ i) pq_gen.push(Executive_Core(GPU_Gen_Num + i, 0, 0));
    printf("GPU_Gen_Num: %d\n", GPU_Gen_Num);
    for (int i = 0; i < GPU_Gen_Num; ++ i) pq_gen.push(Executive_Core(i, 0, 1));
    gpu_warmup();
    for (int i = 0; i < Distributed_Graph_Num; ++ i) {
        x = pq_gen.top();
        pq_gen.pop();
        auto begin = std::chrono::high_resolution_clock::now();
        if (x.core_type == 0) {
            hop_constrained_two_hop_labels_generation(instance_graph, info_cpu, L_hybrid, graph_pool.graph_group[i]);
        } else {
            LabelGenTimings current_timings;
            long long current_delta = 0;
            gpu_label_gen(csr_graph, info_gpu, L + tot_L, current_delta, graph_pool.graph_group[i], i, sort_time_record, current_timings);
            total_timings.expand_time += current_timings.expand_time;
            total_timings.sort_time += current_timings.sort_time;
            total_timings.tranverse_time += current_timings.tranverse_time;
            total_timings.gather_time += current_timings.gather_time;
            total_timings.memcpy_time += current_timings.memcpy_time;
            total_timings.update_hash_time += current_timings.update_hash_time;
            total_timings.clear_das_time += current_timings.clear_das_time;
            total_timings.init_time += current_timings.init_time;
            total_timings.finalize_time += current_timings.finalize_time;

            tot_L += current_delta;
        }
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        x.time_use += duration;
        pq_gen.push(x);
        printf("duration time: %.8lf\n", (double)duration);
    }

    auto t_process_start = std::chrono::high_resolution_clock::now();
    printf("Start batch converting %lld labels to L_hybrid.\n", tot_L);
    #pragma omp parallel for schedule(dynamic, 1024)
    for (long long j = 0; j < tot_L; ++ j) {
        long long T = L[j];
        int to_v = get_to_vertex(T);
        L_hybrid[csr_graph.ARRAY_source[to_v]].push_back({get_hub_vertex(T), csr_graph.OUTs_Edges[to_v], get_hop(T), get_distance(T)});
    }
    auto t_process_end = std::chrono::high_resolution_clock::now();
    total_timings.process_result_time += std::chrono::duration<double>(t_process_end - t_process_start).count();
    cudaFreeHost(L);
    printf("Batch convert done. time: %.8lf\n", total_timings.process_result_time);
    printf("sort_time_record: %.8lf\n", sort_time_record);

    double time_generate_labels_total = 0.0;
    while (!pq_gen.empty()) {
        time_generate_labels_total = max(time_generate_labels_total, pq_gen.top().time_use);
        printf("time generate labels total: %.8lf\n", time_generate_labels_total);
        pq_gen.pop();
    }
    printf("finish add label.\n");

    long long label_before_clean = 0, label_after_clean = 0;
    for (int v_k = 0; v_k < V; v_k ++) {
        label_before_clean += L_hybrid[v_k].size();
    }

    if (check_correctness) {
        #pragma omp parallel for schedule(dynamic, 128)
        for (int v_k = 0; v_k < V; ++ v_k) {
            sort(L_hybrid[v_k].begin(), L_hybrid[v_k].end(), compare_hop_constrained_two_hop_label);
        }
    }
    printf("finish sort label.\n");

    size_t free_byte, total_byte;
    if (GPU_Gen_Num) {
        info_gpu->destroy_L_cuda();
    }
    cudaMemGetInfo(&free_byte, &total_byte);
    printf("Device memory after: total %ld, free %ld\n", total_byte, free_byte);
    info_gpu->init_clean(V, L_hybrid, csr_graph, label_before_clean, edge_id, G_max);
    L_hybrid.resize(V);
    printf("finish init clean.\n");

    priority_queue<Executive_Core> pq_clean;
    long long clean_size = G_max, last_pos = 1;
    std::vector<std::pair<long long, long long>> gpu_clean_ranges;
    for (int i = 0; i < CPU_Clean_Num; ++ i) pq_clean.push(Executive_Core(GPU_Clean_Num + i, 0, 0));
    for (int i = 0; i < GPU_Clean_Num; ++ i) pq_clean.push(Executive_Core(i, 0, 1));
    gpu_warmup();
    for (long long i = 0; i < V; i += clean_size) {
        printf("clean!!!\n");
        x = pq_clean.top();
        pq_clean.pop();
        auto begin = std::chrono::high_resolution_clock::now();
        if (x.core_type == 0) {
            printf("hop_constrained_clean_L_distributed!!!\n");
            hop_constrained_clean_L_distributed(info_cpu, L_hybrid, i, min(i + clean_size, (long long)V), info_cpu.thread_num);
        } else {
            printf("gpu_label_clean!!!\n");
            gpu_label_clean(csr_graph, i, min(i + clean_size, (long long)V), info_gpu, last_pos, total_timings);
            for (int j = i; j < min(i + clean_size, (long long)V); j ++) {
                L_hybrid[j].clear();
            }
            gpu_clean_ranges.push_back({last_pos, info_gpu->last_size});
        }
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        x.time_use += duration;
        pq_clean.push(x);
        printf("duration time: %.8lf\n", (double)duration);
    }
    double time_clean_labels_total = 0.0;
    while (!pq_clean.empty()) {
        time_clean_labels_total = max(time_clean_labels_total, pq_clean.top().time_use);
        printf("time clean labels total: %.8lf\n", time_clean_labels_total);
        pq_clean.pop();
    }
    printf("finish clean label.\n");

    if (!gpu_clean_ranges.empty()) {
        auto t_convert_start = std::chrono::high_resolution_clock::now();
        long long clean_max_pos = 0;
        long long total_clean_labels = 0;
        for (auto& [s, e] : gpu_clean_ranges) {
            clean_max_pos = max(clean_max_pos, e);
            total_clean_labels += e - s;
        }
        printf("Start batch converting %lld clean labels to L_hybrid.\n", total_clean_labels);
        if (total_clean_labels > 0) {
            cudaMemPrefetchAsync(info_gpu->L_clean, clean_max_pos * sizeof(long long), cudaCpuDeviceId, 0);
            cudaDeviceSynchronize();
            #pragma omp parallel for schedule(dynamic, 1)
            for (int r = 0; r < (int)gpu_clean_ranges.size(); r++) {
                auto [s, e] = gpu_clean_ranges[r];
                for (long long j = s; j < e; j++) {
                    long long T = info_gpu->L_clean[j];
                    hop_constrained_two_hop_label xxx_t;
                    xxx_t.hub_vertex = get_hub_vertex(T);
                    xxx_t.hop = get_hop(T);
                    xxx_t.distance = get_distance(T);
                    if (xxx_t.hop == 0) {
                        xxx_t.parent_vertex = csr_graph.ARRAY_source[get_to_vertex(T)];
                    } else {
                        xxx_t.parent_vertex = csr_graph.OUTs_Edges[get_to_vertex(T)];
                    }
                    L_hybrid[csr_graph.ARRAY_source[get_to_vertex(T)]].push_back(xxx_t);
                }
            }
        }
        auto t_convert_end = std::chrono::high_resolution_clock::now();
        total_timings.clean_convert_time += std::chrono::duration<double>(t_convert_end - t_convert_start).count();
    }

    for (int i = 0; i < V; i ++) {
        label_after_clean += L_hybrid[i].size();
    }
    if (check_correctness) {
        #pragma omp parallel for schedule(dynamic, 128)
        for (int v_k = 0; v_k < V; ++ v_k) {
            sort(L_hybrid[v_k].begin(), L_hybrid[v_k].end(), compare_hop_constrained_two_hop_label);
        }
    }

    printf("label size before: %lld\n", label_before_clean);
    printf("label size after: %lld\n", label_after_clean);
    printf("total generation time: %.8lf\n", (double)time_generate_labels_total);
    printf("total clean time: %.8lf\n", (double)time_clean_labels_total);

    check_correctness = 1;
    if (check_correctness) {
        printf("check union correctness.\n");
        HybridHopHL_checker_query_file(L_hybrid, instance_graph, iteration_source_times, iteration_terminal_times, hop_cst, check_path);
    }

    printf("\n===== Label Generation Stage Timings =====\n");
    printf("Init time:       %.8f s\n", total_timings.init_time);
    printf("Expand time:     %.8f s\n", total_timings.expand_time);
    printf("Sort time:       %.8f s\n", total_timings.sort_time);
    printf("Tranverse time:  %.8f s\n", total_timings.tranverse_time);
    printf("Gather time:     %.8f s\n", total_timings.gather_time);
    printf("Memcpy hash:     %.8f s\n", total_timings.memcpy_time);
    printf("Update hash:     %.8f s\n", total_timings.update_hash_time);
    printf("Clear das:       %.8f s\n", total_timings.clear_das_time);
    printf("Finalize time:   %.8f s\n", total_timings.finalize_time);
    printf("Process result:  %.8f s\n", total_timings.process_result_time);
    printf("Total:           %.8f s\n",
        total_timings.init_time + total_timings.expand_time + total_timings.sort_time +
        total_timings.tranverse_time + total_timings.gather_time + total_timings.memcpy_time +
        total_timings.update_hash_time + total_timings.clear_das_time +
        total_timings.finalize_time + total_timings.process_result_time);
    printf("==========================================\n\n");

    printf("===== Label Clean Stage Timings =====\n");
    printf("Init hash:       %.8f s\n", total_timings.clean_init_hash_time);
    printf("Clean label:     %.8f s\n", total_timings.clean_label_time);
    printf("Clean hash:      %.8f s\n", total_timings.clean_hash_time);
    printf("Gather:          %.8f s\n", total_timings.clean_gather_time);
    printf("Update L:        %.8f s\n", total_timings.clean_update_L_time);
    printf("Convert:         %.8f s\n", total_timings.clean_convert_time);
    printf("Total:           %.8f s\n",
        total_timings.clean_init_hash_time + total_timings.clean_label_time +
        total_timings.clean_hash_time + total_timings.clean_gather_time +
        total_timings.clean_update_L_time + total_timings.clean_convert_time);
    printf("====================================\n\n");

    std::ofstream out(out_put_path, std::ios::app);
    out << std::fixed << std::setprecision(8);

    out << "data_path: \"" << data_path << "\", "
        << "hop_cst: " << hop_cst << ", "
        << "G_max: " << G_max << ", "
        << "gen_labels_time: " << time_generate_labels_total << ", "
        << "gen_labels_total: " << label_before_clean << ", "
        << "clean_labels_time: " << time_clean_labels_total << ", "
        << "clean_labels_total: " << label_after_clean << ", "
        << "algo_query_dis_time: " << time_query_dis_total << ", "
        << "algo_query_path_time: " << time_query_path_total << ", "
        << "hopdij_query_dis_time: " << time_hop_dijkstra_query_dis_total << ", "
        << "hopdij_query_path_time: " << time_hop_dijkstra_query_path_total << ", "
        << "query_num: " << queries.size() << ", "
        << "label_gen_init_time: " << total_timings.init_time << ", "
        << "label_gen_expand_time: " << total_timings.expand_time << ", "
        << "label_gen_sort_time: " << total_timings.sort_time << ", "
        << "label_gen_tranverse_time: " << total_timings.tranverse_time << ", "
        << "label_gen_gather_time: " << total_timings.gather_time << ", "
        << "label_gen_update_hash_time: " << total_timings.update_hash_time << ", "
        << "label_gen_clear_das_time: " << total_timings.clear_das_time << ", "
        << "label_gen_finalize_time: " << total_timings.finalize_time << ", "
        << "label_gen_process_result_time: " << total_timings.process_result_time << std::endl;
    out.close();

    cudaFreeHost(L);

    return 0;
}
