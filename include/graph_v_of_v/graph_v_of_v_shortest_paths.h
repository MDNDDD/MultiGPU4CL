#ifndef GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_PATH_H
#define GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_PATH_H
#pragma once

#include <vector>
#include <queue>
#include <tuple>
#include <limits>
#include <algorithm>

template<typename T>
void graph_v_of_v_hop_constrained_shortest_path(
    graph_v_of_v<T>& instance_graph, 
    int source, 
    int terminal, 
    int hop_cst, 
    std::vector<T>& distance, 
    std::vector<int>& path) { 

    int N = instance_graph.size();
    T INF = std::numeric_limits<T>::max();

    distance.assign(N, INF);
    distance[source] = 0;

    std::vector<std::vector<T>> dist_at_hop(N, std::vector<T>(hop_cst + 1, INF));
    dist_at_hop[source][0] = 0;

    std::vector<std::vector<int>> parent(N, std::vector<int>(hop_cst + 1, -1));

    using State = std::tuple<T, int, int>;
    std::priority_queue<State, std::vector<State>, std::greater<State>> pq;

    pq.push({0, 0, source});

    int final_hop_at_terminal = -1;
    bool found = false;

    /* Dijkstra Main Loop */
    while (!pq.empty()) {
        auto [d, h, u] = pq.top();
        pq.pop();

        if (u == terminal) {
            final_hop_at_terminal = h;
            found = true;
            break; // 核心优化：立即退出
        }
        if (d > dist_at_hop[u][h]) {
            continue;
        }
        if (h >= hop_cst) {
            continue;
        }

        for (auto& edge : instance_graph[u]) {
            int v = edge.first;
            T weight = edge.second;
            
            T new_dist = d + weight;
            int new_hop = h + 1;

            if (new_dist < dist_at_hop[v][new_hop]) {
                dist_at_hop[v][new_hop] = new_dist;
                parent[v][new_hop] = u; 
                if (new_dist < distance[v]) {
                    distance[v] = new_dist;
                }
                pq.push({new_dist, new_hop, v});
            }
        }
    }

    /* 
     * Backtracking
     */
    path.clear();

    if (found) {
        int curr = terminal;
        int curr_hop = final_hop_at_terminal;
        while (curr_hop > 0) { 
            path.push_back(curr);
            int pre = parent[curr][curr_hop];
            
            curr = pre;
            curr_hop--;
        }
        path.push_back(source);
        std::reverse(path.begin(), path.end());
    }
}

#endif