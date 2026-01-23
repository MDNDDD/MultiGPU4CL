// #ifndef GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_DISTANCE_H
// #define GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_DISTANCE_H
// #pragma once

// /* this func get all distances from source with hop constraint */

// template<typename T>
// void graph_v_of_v_hop_constrained_shortest_distance(graph_v_of_v<T>& instance_graph, int source, int terminal, int hop_cst, vector<T>& distance) {

// 	int N = instance_graph.size();

// 	vector<vector<pair<int, T>>> Q(hop_cst + 2);
// 	Q[0].push_back({ source, 0 });

// 	distance.resize(N); // distance.resize(N, std::numeric_limits<T>::max()) does not work here, since the type of the second parametter of resize should be specified
// 	for (int i = 0; i < N; i++) {
// 		distance[i] = std::numeric_limits<int>::max();
// 	}
// 	distance[source] = 0;

// 	int h = 0;

// 	/* BFS */
// 	while (h <= hop_cst) {
// 		for (auto& xx : Q[h]) {
// 			int v = xx.first;
// 			T distance_v = xx.second;

// 			if (v == source || distance[v] > distance_v) {
// 				distance[v] = distance_v;
// 				for (auto& yy : instance_graph[v]) {
// 					if (distance_v + yy.second < distance[yy.first]) {
// 						Q[h + 1].push_back({ yy.first, distance_v + yy.second });
// 					}
// 				}
// 			}
// 		}
// 		h++;
// 	}
// }

// #endif
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
	
    // 1. 初始化输出的 distance 向量
    // 注意：原代码中 resize 第二个参数类型如果是 int 可能会导致 T 为 double 时精度丢失或溢出，
    // 这里显式使用 T 类型的 max()，并使用 assign 重新初始化。
    distance.assign(N, INF);
    distance[source] = 0;

    // 2. 内部距离表：min_dist[u][h] 表示到达节点 u 且恰好经过 h 跳的最短距离
    // 这是必须的，因为有时候经过更多跳数但权重更小的路径是扩展所必需的。
    std::vector<std::vector<T>> dist_at_hop(N, std::vector<T>(hop_cst + 1, INF));
    dist_at_hop[source][0] = 0;

    // 3. 优先队列，存储元组 (当前距离 cost, 当前跳数 hops, 当前节点 u)
    // 使用 std::greater 实现小顶堆
    using State = std::tuple<T, int, int>;
    std::priority_queue<State, std::vector<State>, std::greater<State>> pq;

    // 初始状态入队
    pq.push({0, 0, source});

    /* Dijkstra Loop */
    while (!pq.empty()) {
        auto [d, h, u] = pq.top();
        pq.pop();

        // 【优化点】：如果当前弹出的节点就是终点，说明找到了满足跳数限制的最短路径
        // 因为是优先队列（小顶堆），第一次从堆中弹出终点时，d 必定是全局最小值。
        if (u == terminal) {
            return;
        }
        
        // 剪枝 1: 如果当前取出的路径比已知到达该节点该跳数的路径更长，则忽略（过期状态）
        if (d > dist_at_hop[u][h]) {
            continue;
        }

        // 剪枝 2: 如果已经达到跳数限制，无法再向外扩展
        if (h >= hop_cst) {
            continue;
        }

        // 遍历邻居
        for (auto& edge : instance_graph[u]) {
            int v = edge.first;
            T weight = edge.second;
            
            T new_dist = d + weight;
            int new_hop = h + 1;

            // 松弛操作：如果发现了到达 v 且跳数为 new_hop 的更短路径
            if (new_dist < dist_at_hop[v][new_hop]) {
                dist_at_hop[v][new_hop] = new_dist;
                pq.push({new_dist, new_hop, v});

                // 更新全局最短距离（不区分跳数，只要在限制内取最小值）
                if (new_dist < distance[v]) {
                    distance[v] = new_dist;
                }
            }
        }
    }
}

#endif