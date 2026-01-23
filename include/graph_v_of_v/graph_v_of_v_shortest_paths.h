// #ifndef GRAPH_V_OF_V_SHORTEST_PATHS_H
// #define GRAPH_V_OF_V_SHORTEST_PATHS_H
// #pragma once

// #include <vector>
// #include <numeric>
// #include <iostream>
// #include <unordered_map>
// #include <boost/heap/fibonacci_heap.hpp> 
// #include <graph_v_of_v/graph_v_of_v.h>

// using namespace std;


// struct graph_v_of_v_node_for_sp {
// 	int index;
// 	double priority_value;
// }; // define the node in the queue
// bool static operator <(graph_v_of_v_node_for_sp const& x, graph_v_of_v_node_for_sp const& y) {
// 	return x.priority_value > y.priority_value; // < is the max-heap; > is the min heap
// }
// typedef typename boost::heap::fibonacci_heap<graph_v_of_v_node_for_sp>::handle_type handle_t_for_graph_v_of_v_sp;


// template<typename T> // T is float or double
// void graph_v_of_v_shortest_paths(graph_v_of_v<T>& input_graph, int source, std::vector<T>& distances, std::vector<int>& predecessors) {

// 	/*Dijkstra's shortest path algorithm: https://www.geeksforgeeks.org/dijkstras-shortest-path-algorithm-greedy-algo-7/
// 	time complexity: O(|E|+|V|log|V|);
// 	the output distances and predecessors only contain vertices connected to source*/

// 	T inf = std::numeric_limits<T>::max();

// 	int N = input_graph.ADJs.size();
// 	distances.resize(N, inf); // initial distance from source is inf
// 	predecessors.resize(N);
// 	std::iota(std::begin(predecessors), std::end(predecessors), 0); // initial predecessor of each vertex is itself

// 	graph_v_of_v_node_for_sp node;
// 	boost::heap::fibonacci_heap<graph_v_of_v_node_for_sp> Q;
// 	std::vector<T> Q_keys(N, inf); // if the key of a vertex is inf, then it is not in Q yet
// 	std::vector<handle_t_for_graph_v_of_v_sp> Q_handles(N);

// 	/*initialize the source*/
// 	Q_keys[source] = 0;
// 	node.index = source;
// 	node.priority_value = 0;
// 	Q_handles[source] = Q.push(node);

// 	/*time complexity: O(|E|+|V|log|V|) based on fibonacci_heap, not on pairing_heap, which is O((|E|+|V|)log|V|)*/
// 	while (Q.size() > 0) {

// 		int top_v = Q.top().index;
// 		T top_key = Q.top().priority_value;

// 		Q.pop();

// 		distances[top_v] = top_key; // top_v is touched

// 		for (auto it = input_graph.ADJs[top_v].begin(); it != input_graph.ADJs[top_v].end(); it++) {
// 			int adj_v = it->first;
// 			T ec = it->second;
// 			if (Q_keys[adj_v] == inf) { // adj_v is not in Q yet
// 				Q_keys[adj_v] = top_key + ec;
// 				node.index = adj_v;
// 				node.priority_value = Q_keys[adj_v];
// 				Q_handles[adj_v] = Q.push(node);
// 				predecessors[adj_v] = top_v;
// 			}
// 			else { // adj_v is in Q
// 				if (Q_keys[adj_v] > top_key + ec) { // needs to update key
// 					Q_keys[adj_v] = top_key + ec;
// 					node.index = adj_v;
// 					node.priority_value = Q_keys[adj_v];
// 					Q.update(Q_handles[adj_v], node);
// 					predecessors[adj_v] = top_v;
// 				}
// 			}
// 		}

// 	}

// }

// #endif
#ifndef GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_PATH_H
#define GRAPH_V_OF_V_HOP_CONSTRAINED_SHORTEST_PATH_H
#pragma once

#include <vector>
#include <queue>
#include <tuple>
#include <limits>
#include <algorithm> // for std::reverse

/* 
 * 基于 Dijkstra 的带跳数限制最短路算法
 * 优化点：
 * 1. 找到 terminal 后立即退出 (Early Exit)，大幅提高点对点查询效率。
 * 2. 只有在需要更新时才写入 distance 数组。
 */

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

    // 1. 初始化
    // 注意：由于是点对点查询，如果提前退出，distance 数组可能不会包含所有节点的最终最短路，
    // 只保证 source 到 terminal 路径上的和已探索节点的距离是最新的。
    distance.assign(N, INF);
    distance[source] = 0;

    // dist_at_hop[u][h] 表示到达 u 恰好用 h 跳的最短距离
    std::vector<std::vector<T>> dist_at_hop(N, std::vector<T>(hop_cst + 1, INF));
    dist_at_hop[source][0] = 0;

    // parent[u][h] 记录前驱节点，用于回溯
    std::vector<std::vector<int>> parent(N, std::vector<int>(hop_cst + 1, -1));

    // Priority Queue State: (cost, hops, u)
    // std::tuple 比较是按顺序比较的，所以优先按 cost 排序，cost 相同按 hops 小的优先
    using State = std::tuple<T, int, int>;
    std::priority_queue<State, std::vector<State>, std::greater<State>> pq;

    pq.push({0, 0, source});

    int final_hop_at_terminal = -1; // 用于记录找到终点时的跳数
    bool found = false;

    /* Dijkstra Main Loop */
    while (!pq.empty()) {
        auto [d, h, u] = pq.top();
        pq.pop();

        // 优化：如果在堆中取出的节点是终点，说明找到了满足条件的最短路径
        if (u == terminal) {
            final_hop_at_terminal = h;
            found = true;
            break; // 核心优化：立即退出
        }

        // 剪枝：如果当前路径比已记录的同跳数路径更长，跳过
        if (d > dist_at_hop[u][h]) {
            continue;
        }
        
        // 剪枝：跳数耗尽，无法再向外扩展
        if (h >= hop_cst) {
            continue;
        }

        // 遍历邻居
        for (auto& edge : instance_graph[u]) {
            int v = edge.first;
            T weight = edge.second;
            
            T new_dist = d + weight;
            int new_hop = h + 1;

            // 松弛操作
            if (new_dist < dist_at_hop[v][new_hop]) {
                dist_at_hop[v][new_hop] = new_dist;
                parent[v][new_hop] = u; 
                
                // 更新全局最短距离（用于调试或参考，注意提前退出时可能不完整）
                if (new_dist < distance[v]) {
                    distance[v] = new_dist;
                }

                pq.push({new_dist, new_hop, v});
            }
        }
    }

    /* 
     * 路径回溯 (Backtracking)
     */
    path.clear();

    if (found) {
        int curr = terminal;
        int curr_hop = final_hop_at_terminal;

        // 从终点倒推回起点
        while (curr_hop > 0) { 
            path.push_back(curr);
            int pre = parent[curr][curr_hop];
            
            curr = pre;
            curr_hop--;
        }
        path.push_back(source); // 加入源点
        std::reverse(path.begin(), path.end()); // 反转
    }
}

#endif