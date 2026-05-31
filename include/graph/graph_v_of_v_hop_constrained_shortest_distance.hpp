#ifndef GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_DISTANCE_H
#define GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_DISTANCE_H
#pragma once

#include <vector>
#include <queue>
#include <tuple>
#include <limits>

/* this func get all distances from source with hop constraint using Dijkstra */
template<typename T>
void graph_v_of_v_hop_constrained_shortest_distance(graph_v_of_v<T>& instance_graph, int source, int terminal, int hop_cst, std::vector<T>& distance) {
    int N = instance_graph.size();
    T INF = std::numeric_limits<T>::max();

    distance.assign(N, INF);
    distance[source] = 0;

    std::vector<std::vector<T>> dist_at_hop(N, std::vector<T>(hop_cst + 1, INF));
    dist_at_hop[source][0] = 0;

    using State = std::tuple<T, int, int>;
    std::priority_queue<State, std::vector<State>, std::greater<State>> pq;
    pq.push({0, 0, source});

    /* Dijkstra Loop */
    while (!pq.empty()) {
        auto [d, h, u] = pq.top();
        pq.pop();

        if (u == terminal) {
            return;
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
                pq.push({new_dist, new_hop, v});
                if (new_dist < distance[v]) {
                    distance[v] = new_dist;
                }
            }
        }
    }
}

#endif