#ifndef GRAPHPOOL_HPP
#define GRAPHPOOL_HPP
#pragma once

#include <thread>
#include <unistd.h>
// #include <definition/mmpool_size.h>
#include <iostream>
#include <mutex>

using std::vector;

template <typename T> class Graph_pool {
public:
    vector<vector<T> > graph_group;
    vector<vector<T> > graph_group_bfs;
    
    int next_graph = 0;
    std::mutex mtx;

    // Constructor
    Graph_pool();
    Graph_pool(int Group_Num);
    int get_next_graph();
    int size();
};

// Constructor
template <typename T> Graph_pool<T>::Graph_pool() {
    next_graph = 0;
}

// Constructor
template <typename T> Graph_pool<T>::Graph_pool(int Group_Num) {
    graph_group.resize(Group_Num);
    next_graph = 0;
}

// Find empty block
template <typename T> int Graph_pool<T>::get_next_graph() {
    // Use lock for protection
    // Acquire lock
    mtx.lock(); // Acquire lock
    int ret = -1;
    if (next_graph >= graph_group.size()) {
        ret = -1;
    }else{
        ret = next_graph;
        next_graph ++;
    }
    mtx.unlock(); // Release lock
    return ret;
}

// Query the size of graphpool
template <typename T> int Graph_pool<T>::size() {
    // Use lock for protection
    // Acquire lock
    mtx.lock(); // Acquire lock
    int ret = graph_group.size() - next_graph;
    mtx.unlock(); // Release lock
    return ret;
}

#endif