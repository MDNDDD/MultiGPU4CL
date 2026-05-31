#ifndef HUB_DEF_H
#define HUB_DEF_H
#pragma once

#define hub_type hop_constrained_two_hop_label_v3
#define hub_type_v2 hop_constrained_two_hop_label
#define hub_type_v4 hop_constrained_two_hop_label_v4
#define disType int
typedef disType weight_type;

struct Executive_Core {
    int id = 0;
    double time_use = 0.0;
    int core_type = 0;

    Executive_Core() = default;
    Executive_Core(int x, double y, int z) : id(x), time_use(y), core_type(z) {}

    friend bool operator<(const Executive_Core& a, const Executive_Core& b) {
        if (a.time_use == b.time_use) return a.id > b.id;
        return a.time_use > b.time_use;
    }
};

#endif