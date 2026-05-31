#ifndef CHECKER_H
#define CHECKER_H
#pragma once

#include <bits/stdc++.h>
#include <boost/random.hpp>
#include <iomanip>
#include <core/flush_cache.hpp>

#include <label/label_types.cuh>
#include <graph/graph_v_of_v.hpp>
#include <graph/graph_v_of_v_hop_constrained_shortest_distance.hpp>
#include <graph/graph_v_of_v_hop_constrained_shortest_path.hpp>

extern boost::random::mt19937 boost_random_time_seed;

struct Query {
    int u, v, h;
};

extern std::vector<Query> queries;
extern double time_query_dis_total, time_query_path_total;
extern double time_hop_dijkstra_query_dis_total, time_hop_dijkstra_query_path_total;

inline void read_query(std::string query_path) {
    std::ifstream infile(query_path);
    int u, v, h;
    while (infile >> u >> v >> h) {
        queries.push_back({u, v, h});
    }
    infile.close();
}

inline void HybridHopHL_checker(std::vector<std::vector<hub_type_v2>>& LL, graph_v_of_v<int>& instance_graph,
                        int iteration_source_times, int iteration_terminal_times, int hop_bounded, int check_path) {

    boost::random::uniform_int_distribution<> vertex_range{ static_cast<int>(0), static_cast<int>(instance_graph.size() - 1) };
    boost::random::uniform_int_distribution<> hop_range{ static_cast<int>(0), static_cast<int>(hop_bounded) };

    printf("checker start random.\n");

    double local_time_query_dis_total = 0.0, local_time_query_path_total = 0.0, time_increase = 0.0;
    for (int yy = 0; yy < iteration_source_times; yy++) {

        int source = vertex_range(boost_random_time_seed);
        std::vector<weight_type> distances;
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
            local_time_query_dis_total += (double) duration;

            if (abs(q_dis - distances[terminal]) > 1e-2 ) {
                std::cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << std::endl;
                std::cout << std::fixed << std::setprecision(5) << "dis = " << q_dis << std::endl;
                std::cout << std::fixed << std::setprecision(5) << "distances[terminal] = " << distances[terminal] << std::endl;
                std::cout << std::endl;
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
            }
            if (check_path) {
                auto begin = std::chrono::high_resolution_clock::now();
                std::vector<std::pair<int, int>> path = hop_constrained_extract_shortest_path(LL, source, terminal, hop_cst);
                auto end = std::chrono::high_resolution_clock::now();
                auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
                local_time_query_path_total += (double) duration;

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
                if (abs(q_dis - path_dis) > 1e-2) {
                    std::cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << std::endl;
                    std::cout << "print_vector_pair_int:" << std::endl;
                    for (int i = 0; i < path.size(); i++) {
                        std::cout << "item: [" << path[i].first << "," << path[i].second << "], |"
                                  << instance_graph.edge_weight(path[i].first, path[i].second) << "|" << std::endl;
                    }
                    std::cout << "query_dis = " << q_dis << std::endl;
                    std::cout << "path_dis = " << path_dis << std::endl;
                    std::cout << "abs(dis - path_dis) > 1e-2!" << std::endl;
                    getchar();
                    return;
                }
            }
        }
    }
    printf("checker end.\n");
    printf("query distance time: %.8lf\n", local_time_query_dis_total);
    printf("query path time: %.8lf\n", local_time_query_path_total);
    printf("query time increase: %.8lf\n", time_increase);
    time_query_dis_total += local_time_query_dis_total;
    time_query_path_total += local_time_query_path_total;
    return;
}

inline void HybridHopHL_checker_query_file(std::vector<std::vector<hub_type_v2>>& LL, graph_v_of_v<int>& instance_graph,
                        int iteration_source_times, int iteration_terminal_times, int hop_bounded, int check_path) {
    printf("checker start query file.\n");

    for (int yy = 0; yy < queries.size(); yy ++) {
        std::vector<weight_type> distances;
        std::vector<int> path;

        distances.resize(instance_graph.size());
        int source = queries[yy].u;
        int terminal = queries[yy].v;
        int hop_cst = queries[yy].h;
        hop_cst = std::min(hop_cst, hop_bounded);

        auto begin = std::chrono::high_resolution_clock::now();
        if (yy < 100)
            graph_v_of_v_hop_constrained_shortest_distance(instance_graph, source, terminal, hop_cst, distances);
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_hop_dijkstra_query_dis_total += (double) duration;

        begin = std::chrono::high_resolution_clock::now();
        if (yy < 100)
            graph_v_of_v_hop_constrained_shortest_path(instance_graph, source, terminal, hop_cst, distances, path);
        end = std::chrono::high_resolution_clock::now();
        duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_hop_dijkstra_query_path_total += (double) duration;

        flush_vector_cache(LL[source]);
        flush_vector_cache(LL[terminal]);
        begin = std::chrono::high_resolution_clock::now();
        int q_dis = hop_constrained_extract_distance(LL, source, terminal, hop_cst);
        end = std::chrono::high_resolution_clock::now();
        duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
        time_query_dis_total += (double) duration;

        if (abs(q_dis - distances[terminal]) > 1e-2 && yy < 100) {
            std::cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << std::endl;
            std::cout << std::fixed << std::setprecision(8) << "dis = " << q_dis << std::endl;
            std::cout << std::fixed << std::setprecision(8) << "distances[terminal] = " << distances[terminal] << std::endl;
            std::cout << std::endl;
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
        }

        if (check_path) {
            flush_vector_cache(LL[source]);
            flush_vector_cache(LL[terminal]);
            begin = std::chrono::high_resolution_clock::now();
            std::vector<std::pair<int, int>> path_result = hop_constrained_extract_shortest_path(LL, source, terminal, hop_cst);
            end = std::chrono::high_resolution_clock::now();
            duration = std::chrono::duration_cast<std::chrono::nanoseconds>(end - begin).count() / 1e9;
            time_query_path_total += (double) duration;

            int path_dis = 0;
            if (path_result.size() == 0 && source != terminal) {
                path_dis = std::numeric_limits<int>::max();
            }
            for (auto xx : path_result) {
                path_dis += instance_graph.edge_weight(xx.first, xx.second);
            }
            if (path_dis == std::numeric_limits<int>::max() && q_dis == std::numeric_limits<int>::max()) {
                continue;
            }
            if (abs(q_dis - path_dis) > 1e-2) {
                std::cout << "source, terminal, hopcst = " << source << ", "<< terminal << ", " << hop_cst << std::endl;
                std::cout << "print_vector_pair_int:" << std::endl;
                for (int i = 0; i < path_result.size(); i++) {
                    std::cout << "item: [" << path_result[i].first << "," << path_result[i].second << "], |"
                                << instance_graph.edge_weight(path_result[i].first, path_result[i].second) << "|" << std::endl;
                }
                std::cout << "query_dis = " << q_dis << std::endl;
                std::cout << "path_dis = " << path_dis << std::endl;
                std::cout << "abs(dis - path_dis) > 1e-2!" << std::endl;
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

#endif