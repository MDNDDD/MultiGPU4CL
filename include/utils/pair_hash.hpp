#ifndef PAIR_HASH_H
#define PAIR_HASH_H
#pragma once

struct PairHash {
    size_t operator()(const std::pair<int, int>& p) const {
        return ((size_t)p.first << 32) | p.second;
    }
};

#endif