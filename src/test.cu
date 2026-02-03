#include <bits/stdc++.h>
#include <boost/random.hpp>
#include <boost/signals2/signal.hpp>
#include <iomanip>

#include <definition/pair_hash.hpp>

#include <label/gen_label.cuh>
#include <label/global_labels_v2.cuh>

#include <memoryManagement/graph_pool.hpp>

#include <graph/ldbc.hpp>
#include <graph/csr_graph.hpp>
#include <graph_v_of_v/graph_v_of_v.h>
#include <graph_v_of_v/graph_v_of_v_shortest_paths.h>
#include <graph_v_of_v/graph_v_of_v_generate_random_graph.h>
#include <graph_v_of_v/graph_v_of_v_hop_constrained_shortest_distance.h>
#include <graph_v_of_v/graph_v_of_v_update_vertexIDs_by_degrees_large_to_small.h>

#include <HBPLL/hop_constrained_two_hop_labels_generation.h>
#include <HBPLL/gpu_clean.cuh>

#include <vgroup/CDLP_group.cuh>

boost::random::mt19937 boost_random_time_seed { static_cast<std::uint32_t>(std::time(0)) }; // Random seed 

vector<vector<hop_constrained_two_hop_label> > L_hybrid;

hop_constrained_case_info info_cpu;
hop_constrained_case_info_v2 *info_gpu;

graph_v_of_v<int> instance_graph;
CSR_graph<weight_type> csr_graph;
Graph_pool<int> graph_pool;

std::unordered_map<std::pair<int, int>, int, PairHash> edge_id;

struct Executive_Core {
    int id = 0;
    double time_use = 0.0;
    int core_type = 0; // 0: cpu, 1: gpu

    Executive_Core() = default;
    Executive_Core(int x, double y, int z) : id(x), time_use(y), core_type(z) {}

    friend bool operator<(const Executive_Core& a, const Executive_Core& b) {
        if (a.time_use == b.time_use) return a.id > b.id;
        return a.time_use > b.time_use;
    }
};

inline void graph_v_of_v_to_LDBC (LDBC<weight_type> &graph, graph_v_of_v<int> &input_graph) {
    int N = input_graph.size();
    for (int i = 0; i < N; ++ i) {
        int v_adj_size = input_graph[i].size();
        for (int j = 0; j < v_adj_size; ++ j) {
            int adj_v = input_graph[i][j].first;
            int ec = input_graph[i][j].second;
            graph.add_edge(i, adj_v, ec);
        }
    }
}

struct Query {
    int u, v, h;
};
vector<Query> queries;
inline void read_query (string query_path) {
    std::ifstream infile(query_path);
    int u, v, h;
    while (infile >> u >> v >> h) {
        queries.push_back({u, v, h});
    }
    infile.close();
}

inline void GPU_HSDL_checker (vector<vector<hub_type_v2> >&LL, graph_v_of_v<int> &instance_graph,
                        int iteration_source_times, int iteration_terminal_times, int hop_bounded, int check_path) {

    boost::random::uniform_int_distribution<> vertex_range{ static_cast<int>(0), static_cast<int>(instance_graph.size() - 1) };
    // boost::random::uniform_int_distribution<> hop_range{ static_cast<int>(1), static_cast<int>(hop_bounded) };
    boost::random::uniform_int_distribution<> hop_range{ static_cast<int>(0), static_cast<int>(hop_bounded) };

    printf("checker start random.\n");

    double time_query_dis_total = 0.0, time_query_path_total = 0.0, time_increase = 0.0;
    for (int yy = 0; yy < iteration_source_times; yy++) {
        // printf("checker iteration %d !\n", yy);

        int source = vertex_range(boost_random_time_seed);
        std::vector<weight_type> distances; // record shortest path
        distances.resize(instance_graph.size());

        int hop_cst = hop_range(boost_random_time_seed);
        graph_v_of_v_hop_constrained_shortest_distance(instance_graph, source, -1, hop_cst, distances);
        for (int xx = 0; xx < iteration_terminal_times; xx++) {
            int terminal = vertex_range(boost_random_time_seed);
            weight_type q_dis = 0;

            auto begin = std::chrono::high_resolution_clock::now();
            q_dis = hop_constrained_extract_distance(LL, source, terminal, hop_cst);
            auto end = std::chrono::high_resolution_clock::now();
            auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
            time_query_dis_total += (double) duration;

            // hop_constrained_extract_shortest_path;
            if (abs(q_dis - distances[terminal]) > 1e-2 ) {
                cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
                cout << fixed << setprecision(5) << "dis = " << q_dis << endl;
                cout << fixed << setprecision(5) << "distances[terminal] = " << distances[terminal] << endl;
                cout << endl;
                printf("L[%d]: %d {", source, LL[source].size());
                for (int i = 0; i < LL[source].size(); i ++) {
                    printf("(%d, %d, %d), ", LL[source][i].hub_vertex, LL[source][i].distance, LL[source][i].hop);
                }
                printf("};\n");
                printf("L[%d]: %d {", terminal, LL[terminal].size());
                for (int i = 0; i < LL[terminal].size(); i ++) {
                    printf("(%d, %d, %d), ", LL[terminal][i].hub_vertex, LL[terminal][i].distance, LL[terminal][i].hop);
                }
                printf("};\n");
                return;
            }else if (distances[terminal] != std::numeric_limits<int>::max()) {
                // cout << "correct !!!" << endl;
                // cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
                // cout << fixed << setprecision(5) << "dis = " << q_dis << endl;
                // cout << fixed << setprecision(5) << "distances[terminal] = " << distances[terminal] << endl;
                // cout << endl;
            }
            if (check_path) {
                auto begin = std::chrono::high_resolution_clock::now();
                // vector<pair<int, int>> path = hop_constrained_extract_shortest_path_v2(LL, instance_graph, source, terminal, hop_cst, time_increase);
                vector<pair<int, int>> path = hop_constrained_extract_shortest_path (LL, source, terminal, hop_cst);
                auto end = std::chrono::high_resolution_clock::now();
                auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
                time_query_path_total += (double) duration;

                int path_dis = 0;
                if (path.size() == 0 && source != terminal) {
                    path_dis = std::numeric_limits<int>::max();
                }
                for (auto xx : path) {
                    path_dis += instance_graph.edge_weight(xx.first, xx.second);
                }
                if (path_dis == std::numeric_limits<int>::max() && q_dis == std::numeric_limits<int>::max()) {
                    continue;
                }
                // printf("path_dis, q_dis: %d, %d\n", path_dis, q_dis);
                if (abs(q_dis - path_dis) > 1e-2) {
                    // instance_graph.print();
                    cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
                    cout << "print_vector_pair_int:" << endl;
                    for (int i = 0; i < path.size(); i++) {
                        cout << "item: [" << path[i].first << "," << path[i].second << "], |" 
                                  << instance_graph.edge_weight(path[i].first, path[i].second) << "|" << endl;
                    }
                    cout << "query_dis = " << q_dis << endl;
                    cout << "path_dis = " << path_dis << endl;
                    cout << "abs(dis - path_dis) > 1e-2!" << endl;
                    getchar();
                    return;
                }
            }
        }
    }
    printf("checker end.\n");
    printf("query distance time: %.8lf\n", time_query_dis_total);
    printf("query path time: %.8lf\n", time_query_path_total);
    printf("query time increase: %.8lf\n", time_increase);
    return;
}

double time_query_dis_total = 0.0, time_query_path_total = 0.0;
double time_hop_dijkstra_query_dis_total = 0.0, time_hop_dijkstra_query_path_total = 0.0;
inline void GPU_HSDL_checker_query_file (vector<vector<hub_type_v2> >&LL, graph_v_of_v<int> &instance_graph,
                        int iteration_source_times, int iteration_terminal_times, int hop_bounded, int check_path) {
    printf("checker start query file.\n");
    
    for (int yy = 0; yy < queries.size(); yy ++) {
        std::vector<weight_type> distances; // record shortest path
        std::vector<int> path;

        distances.resize(instance_graph.size());
        int source = queries[yy].u;
        int terminal = queries[yy].v;
        int hop_cst = queries[yy].h;
        hop_cst = std::min(hop_cst, hop_bounded);

        // hop dijkstra shortest distance
        auto begin = std::chrono::high_resolution_clock::now();
        if (yy < 100) 
            graph_v_of_v_hop_constrained_shortest_distance(instance_graph, source, terminal, hop_cst, distances);
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_hop_dijkstra_query_dis_total += (double) duration;

        // hop dijkstra shortest path
        begin = std::chrono::high_resolution_clock::now();
        if (yy < 100) 
            graph_v_of_v_hop_constrained_shortest_path(instance_graph, source, terminal, hop_cst, distances, path);
        end = std::chrono::high_resolution_clock::now();
        duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_hop_dijkstra_query_path_total += (double) duration;

        begin = std::chrono::high_resolution_clock::now();
        int q_dis = hop_constrained_extract_distance (LL, source, terminal, hop_cst);
        end = std::chrono::high_resolution_clock::now();
        duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_query_dis_total += (double) duration;

        if (abs(q_dis - distances[terminal]) > 1e-2 && yy < 100) {
            cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
            cout << fixed << setprecision(8) << "dis = " << q_dis << endl;
            cout << fixed << setprecision(8) << "distances[terminal] = " << distances[terminal] << endl;
            cout << endl;
            printf("L[%d]: %d {", source, LL[source].size());
            for (int i = 0; i < LL[source].size(); i ++) {
                printf("(%d, %d, %d), ", LL[source][i].hub_vertex, LL[source][i].distance, LL[source][i].hop);
            }
            printf("};\n");
            printf("L[%d]: %d {", terminal, LL[terminal].size());
            for (int i = 0; i < LL[terminal].size(); i ++) {
                printf("(%d, %d, %d), ", LL[terminal][i].hub_vertex, LL[terminal][i].distance, LL[terminal][i].hop);
            }
            printf("};\n");
            return;
        } else {
            // cout << "correct !!!" << endl;
            // cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
            // cout << fixed << setprecision(5) << "dis = " << q_dis << endl;
            // cout << fixed << setprecision(5) << "distances[terminal] = " << distances[terminal] << endl;
            // cout << endl;
        }

        if (check_path) {
            begin = std::chrono::high_resolution_clock::now();
            vector<pair<int, int>> path = hop_constrained_extract_shortest_path (LL, source, terminal, hop_cst);
            end = std::chrono::high_resolution_clock::now();
            duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
            time_query_path_total += (double) duration;
            
            int path_dis = 0;
            if (path.size() == 0 && source != terminal) {
                path_dis = std::numeric_limits<int>::max();
            }
            for (auto xx : path) {
                path_dis += instance_graph.edge_weight(xx.first, xx.second);
            }
            if (path_dis == std::numeric_limits<int>::max() && q_dis == std::numeric_limits<int>::max()) {
                continue;
            }
            // printf("path_dis, q_dis: %d, %d\n", path_dis, q_dis);
            if (abs(q_dis - path_dis) > 1e-2) {
                // instance_graph.print();
                cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << endl;
                cout << "print_vector_pair_int:" << endl;
                for (int i = 0; i < path.size(); i++) {
                    cout << "item: [" << path[i].first << "," << path[i].second << "], |" 
                                << instance_graph.edge_weight(path[i].first, path[i].second) << "|" << endl;
                }
                cout << "query_dis = " << q_dis << endl;
                cout << "path_dis = " << path_dis << endl;
                cout << "abs(dis - path_dis) > 1e-2!" << endl;
                getchar();
                return;
            }
        }
    }
    printf("checker end.\n");
    printf("query distance time: %.8lf\n", time_query_dis_total);
    printf("query path time: %.8lf\n", time_query_path_total);
    printf("hopDijkstra query distance time: %.8lf\n", time_hop_dijkstra_query_dis_total);
    printf("hopDijkstra query path time: %.8lf\n", time_hop_dijkstra_query_path_total);
    return;
}

// read the graph file and generate csr_graph
void read_graph (int &generate_new_graph, int &V, int &E, string &data_path) {
    if (generate_new_graph) {
        instance_graph = graph_v_of_v_generate_random_graph<int> (V, E, 1, 100, 1, boost_random_time_seed);
        instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph); // sort vertices
        instance_graph.txt_save("../data/simple_iterative_tests.txt");
    } else {
        V = 0, E = 0;
        instance_graph.txt_read(data_path);
        // instance_graph.txt_read_v2(data_path);
        instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph);
        V = instance_graph.size();
        for (int i = 0; i < V; ++ i) {
            E += instance_graph[i].size();
        }
    }

    // Generate CSR_graph from instance_graph
    LDBC<weight_type> graph(V);
    graph_v_of_v_to_LDBC(graph, instance_graph);
    csr_graph = toCSR(graph);
    printf("generation graph successful.\n");
}

inline void sub_graph (int &use_cd, int &V, int &E, int &G_max, int &Distributed_Graph_Num, double &time_cd_total) {
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
        Distributed_Graph_Num = graph_pool.graph_group.size();
    } else {
        Distributed_Graph_Num = 3;
        graph_pool.graph_group = { {0, 3, 7}, {1, 2, 4}, {5, 6} };
    }
}

void set_info (int &algo, int &hop_cst, int &thread_num, int &CPU_Gen_Num, int &GPU_Gen_Num) {
    info_cpu.upper_k = hop_cst;
	info_cpu.use_rank_prune = 1;
	info_cpu.use_2023WWW_generation = 0;
    info_cpu.use_2023WWW_generation_optimized = 1;
    info_cpu.use_GPU_version_generation = 0;
    info_cpu.use_GPU_version_generation_optimized = 0;
	info_cpu.use_canonical_repair = 0;
    info_cpu.thread_num = thread_num;
    printf("init CPU_info successful.\n");

    // gpu info
    info_gpu = new hop_constrained_case_info_v2();
    info_gpu->hop_cst = hop_cst;
    info_gpu->thread_num = thread_num;
    info_gpu->use_2023WWW_GPU_version = 0;
    info_gpu->use_new_algo = 0;
    printf("init GPU_info successful.\n");
    
    // set algo type
    printf("algo: %d\n", algo);
    if (algo == 1) {info_cpu.use_2023WWW_generation = 1, CPU_Gen_Num = 1, GPU_Gen_Num = 0;}
    else if (algo == 2) {info_cpu.use_2023WWW_generation_optimized = 1, CPU_Gen_Num = 1, GPU_Gen_Num = 0;}
    else if (algo == 3) {info_gpu->use_new_algo = 1, CPU_Gen_Num = 0, GPU_Gen_Num = 1;}
    else if (algo == 4) {info_gpu->use_new_algo = 1, CPU_Gen_Num = 0, GPU_Gen_Num = 4;}
    else if (algo == 5) {
        info_cpu.use_2023WWW_generation_optimized = 1, info_gpu->use_new_algo = 1, CPU_Gen_Num = 1, GPU_Gen_Num = 4;
    } else if (algo == 6) {
        info_gpu->use_2023WWW_GPU_version = 1, CPU_Gen_Num = 0, GPU_Gen_Num = 1;
    }
}

inline graph_v_of_v<int> example_graph () {
    graph_v_of_v<int> init_graph(8);
    init_graph.add_edge(0, 1, 5), init_graph.add_edge(0, 2, 3), init_graph.add_edge(0, 3, 12);
    init_graph.add_edge(0, 6, 15), init_graph.add_edge(0, 7, 4);
    init_graph.add_edge(1, 2, 10), init_graph.add_edge(1, 3, 2), init_graph.add_edge(1, 4, 6);
    init_graph.add_edge(2, 4, 3), init_graph.add_edge(2, 5, 4);
    init_graph.add_edge(5, 6, 1);
    return init_graph;
}

// GPU warm-up kernel function
__global__ void gpu_warmup_kernel(float* dummy, int iterations) {
    int idx = threadIdx.x + blockIdx.x * blockDim.x;
    float sum = 0.0f;
    for (int i = 0; i < iterations; ++ i) sum += sqrtf(float(idx) + 0.1f) * cosf(float(i) * 0.5f);
    if (dummy) dummy[idx] = sum;
}
// GPU warm-up
inline void gpu_warmup() {
    const int num_threads = 256, num_blocks = 256, iterations = 100;
    float* d_dummy;
    cudaMalloc(&d_dummy, num_threads * num_blocks * sizeof(float));
    gpu_warmup_kernel<<<num_blocks, num_threads>>>(d_dummy, iterations);
    cudaDeviceSynchronize();
    cudaFree(d_dummy);
}

int main (int argc, char** argv) {

    srand(time(0));
    int iteration_source_times = 2000, iteration_terminal_times = 2000;
    int V = 5000, E = 30000, hop_cst = 5, G_max = 300, Distributed_Graph_Num = 1, thread_num = 50;
    int check_correctness = 1, check_path = 1, use_cd = 1, cpu_type = 0;
    int CPU_Gen_Num = 0, GPU_Gen_Num = 4, CPU_Clean_Num = 0, GPU_Clean_Num = 4;
    string data_path, out_put_path;

    double time_cd_total = 0.0, sort_time_record = 0.0;

    // data_path = "../data/simple_iterative_tests.txt";
    // data_path = "/home/mdnd/dataset/data_exp_1w/as-caida20071105/as-caida20071105.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/Brightkite_edges/Brightkite_edges.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/CA-CondMat/CA-CondMat.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/Email-Enron/Email-Enron.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/git_web_ml/git_web_ml.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/p2p-Gnutella31/p2p-Gnutella31.e";
    // data_path = "/home/mdnd/dataset/data_exp_1w/twitch/twitch.e";
    // data_path = "/home/mdnd/dataset/data_exp_10w/Amazon0302/Amazon0302.e";
    // data_path = "/home/mdnd/dataset/data_exp_10w/Gowalla_edges/Gowalla_edges.e";
    // data_path = "/home/mdnd/dataset/data_exp_10w/web-NotreDame/web-NotreDame.e";
    // data_path = "/home/mdnd/dataset/data_exp_10w/Email-EuAll/Email-EuAll.e";
    // data_path = "/home/mdnd/dataset/data_exp_10w/com-amazon/com-amazon.e";
    // data_path = "/home/mdnd/dataset/data_exp_cit-Patents/cit-Patents/cit-Patents.e";
    // data_path = "/home/mdnd/dataset/data_exp_web-NotreDame/web-NotreDame/web-NotreDame.e";

    // data_path = "/home/mdnd/dataset/data_exp_amazon-meta/amazon-meta/amazon-meta.e";
    // data_path = "/home/mdnd/dataset/data_exp_amazon-meta2/amazon-meta2/amazon-meta2.e";
    // data_path = "/home/mdnd/dataset/data_exp_web-BerkStan/web-BerkStan/web-BerkStan.e";
    data_path = "/home/mdnd/dataset/data_exp_web-Google/web-Google/web-Google.e";
    // data_path = "/home/mdnd/dataset/data_exp_DBLP/DBLP/DBLP.e";
    // data_path = "/home/mdnd/dataset/data_exp_com-youtube/com-youtube/com-youtube.e";
    // data_path = "/home/mdnd/dataset/data_exp_wiki-talk/wiki-talk/wiki-talk.e";
    // data_path = "/home/mdnd/dataset/data_exp_as-skitter/as-skitter/as-skitter.e";
    // data_path = "/home/mdnd/dataset/data_exp_reddit/reddit/reddit.e";

    // data_path = argv[1];
    // hop_cst = std::stoi(argv[2]);
    // out_put_path = argv[3];
    // G_max = std::stoi(argv[4]);
    // cpu_type = std::stoi(argv[5]);

    read_query(data_path.substr(0, data_path.rfind(".e")) + "_queries.txt");


    // instance_graph = graph_v_of_v_generate_random_graph<int> (V, E, 1, 100, 1, boost_random_time_seed);
    // instance_graph.txt_save("../data/simple_iterative_tests.txt");
    // instance_graph = example_graph();
    instance_graph.txt_read(data_path);
    V = instance_graph.vertex_num(), E = instance_graph.edge_num();
    instance_graph = graph_v_of_v_update_vertexIDs_by_degrees_large_to_small(instance_graph);
    sub_graph (use_cd, V, E, G_max, Distributed_Graph_Num, time_cd_total);
    printf("V, E, G_max, Distributed_Graph_Num: %d, %d, %d\n", V, E, G_max, Distributed_Graph_Num);
    
    LDBC<weight_type> graph(V);
    graph_v_of_v_to_LDBC(graph, instance_graph);
    csr_graph = toCSR(graph, &edge_id);

    info_gpu = new hop_constrained_case_info_v2();
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
    
    
    long long *L = (long long *)malloc(1000000000ll * sizeof(long long)), delta_L = 0, tot_L = 0;
    
    priority_queue<Executive_Core> pq_gen; Executive_Core x;
    vector<long long> L_size_before(V, 0);
    for (int i = 0; i < CPU_Gen_Num; ++ i) pq_gen.push(Executive_Core(GPU_Gen_Num + i, 0, 0)); // id, time, cpu/gpu
    for (int i = 0; i < GPU_Gen_Num; ++ i) pq_gen.push(Executive_Core(i, 0, 1)); // id, time, cpu/gpu
    gpu_warmup ();
    for (int i = 0; i < Distributed_Graph_Num; ++ i, delta_L = 0) {
        x = pq_gen.top();
        pq_gen.pop();
        auto begin = std::chrono::high_resolution_clock::now();
        if (x.core_type == 0) { // core type is cpu
            hop_constrained_two_hop_labels_generation(instance_graph, info_cpu, L_hybrid, graph_pool.graph_group[i]);
        } else { // core type is gpu
            label_gen_v4(csr_graph, info_gpu, L + delta_L, delta_L, graph_pool.graph_group[i], i, sort_time_record);
            // label_gen_v3(csr_graph, info_gpu, L + L_size, L_size, graph_pool.graph_group[i], i, sort_time_record);
            for (long long j = 0; j < delta_L; ++ j) {
                long long T = L[j];
                int to_v = get_to_vertex(T);
                L_hybrid[csr_graph.ARRAY_source[to_v]].push_back({
                    get_hub_vertex(T), csr_graph.OUTs_Edges[to_v], get_hop(T), get_distance(T)});
            }
            tot_L += delta_L;
            printf("tot_L, delta_L: %lld, %lld\n", tot_L, delta_L);
        }
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        x.time_use += duration;
        pq_gen.push(x);
        printf("duration time: %.8lf\n", (double)duration);
        
        // long long L_size_add = 0;
        // for (int i = 0; i < V; i ++) {
        //     L_size_add += L_hybrid[i].size() - L_size_before[i];
        //     L_size_before[i] = L_hybrid[i].size();
        // }
        // printf("L_size_add: %lld\n", L_size_add);
    }
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

    // sort
    if (check_correctness) {
        #pragma omp parallel for schedule(dynamic)
        for (int v_k = 0; v_k < V; ++ v_k) {
            sort(L_hybrid[v_k].begin(), L_hybrid[v_k].end(), compare_hop_constrained_two_hop_label);
        }
    }
    printf("finish sort label.\n");

    // clean_L
    size_t free_byte, total_byte;
    if (GPU_Gen_Num) {
        info_gpu->destroy_L_cuda();
    }
    // csr_graph.destroy_csr_graph();
    cudaMemGetInfo(&free_byte, &total_byte);
    printf("Device memory after: total %ld, free %ld\n", total_byte, free_byte);
    info_gpu->init_clean(V, L_hybrid, csr_graph, label_before_clean, edge_id);
    L_hybrid.resize(V);

    priority_queue<Executive_Core> pq_clean;
    long long clean_size = 2000, last_pos = 1;
    for (int i = 0; i < CPU_Clean_Num; ++ i) pq_clean.push(Executive_Core(GPU_Gen_Num + i, 0, 0)); // id, time, cpu/gpu
    for (int i = 0; i < GPU_Clean_Num; ++ i) pq_clean.push(Executive_Core(i, 0, 1)); // id, time, cpu/gpu
    gpu_warmup ();
    for (long long i = 0; i < V; i += clean_size) {
        x = pq_clean.top();
        pq_clean.pop();
        auto begin = std::chrono::high_resolution_clock::now();
        if (x.core_type == 0) {
            hop_constrained_clean_L_distributed (info_cpu, L_hybrid, i, min(i + clean_size, (long long)V), info_cpu.thread_num);
        } else {
            gpu_clean_v4 (csr_graph, i, min(i + clean_size, (long long)V), info_gpu, last_pos);
            for (int j = i; j < min(i + clean_size, (long long)V); j ++) {
                L_hybrid[j].clear();
            }
            // printf("last_pos, last_size - last_pos: %lld, %lld\n", last_pos, info_gpu->last_size - last_pos);
            if (info_gpu->last_size - last_pos > 0) {
                cudaMemPrefetchAsync(info_gpu->L_clean + last_pos, info_gpu->last_size - last_pos, cudaCpuDeviceId, 0);
                cudaDeviceSynchronize();
            }
            for (long long j = last_pos; j < info_gpu->last_size; j ++) {
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
                // printf("csr_graph.ARRAY_source[get_to_vertex(T)]: %lld\n", csr_graph.ARRAY_source[get_to_vertex(T)]);
            }
            last_pos = info_gpu->last_size;
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

    for (int i = 0; i < V; i ++) {
        label_after_clean += L_hybrid[i].size();
    }

    printf("label size before: %lld\n", label_before_clean);
    printf("label size after: %lld\n", label_after_clean);
    printf("total generation time: %.8lf\n", (double)time_generate_labels_total);
    printf("total clean time: %.8lf\n", (double)time_clean_labels_total);

    if (check_correctness) {
        printf("check union correctness.\n");
        GPU_HSDL_checker_query_file(L_hybrid, instance_graph, iteration_source_times, iteration_terminal_times, hop_cst, check_path);
    }

    std::ofstream out(out_put_path, std::ios::app);
    out << fixed << setprecision(8) << data_path << ", " << hop_cst << ", " 
    << time_generate_labels_total << ", " << label_before_clean << ", " 
    << time_clean_labels_total << ", " << label_after_clean << std::endl
    << fixed << setprecision(8) << "algo_query_time: " << time_query_dis_total << ", " << time_query_path_total << std::endl
    << fixed << setprecision(8) << "hopdij_query_time: " << time_hop_dijkstra_query_dis_total << ", " << time_hop_dijkstra_query_path_total << std::endl;
    out.close();

    return 0;
}