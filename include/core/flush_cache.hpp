#ifndef FLUSH_CACHE_HPP
#define FLUSH_CACHE_HPP
#pragma once

#include <vector>
#include <emmintrin.h>

inline void flush_vector_cache(const vector<hub_type_v2>& vec) {
    const char* ptr = reinterpret_cast<const char*>(vec.data());
    size_t size = vec.size() * sizeof(hub_type_v2);
    for (size_t i = 0; i < size; i += 64) {
        _mm_clflush(ptr + i);
    }
}

#endif