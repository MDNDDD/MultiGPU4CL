#ifndef GEN_LABEL_CUH
#define GEN_LABEL_CUH
#pragma once

#include <graph/csr_graph.hpp>
#include <gpu_label_gen/gpu_label_manager.cuh>
#include <utils/thread_pool.h>
#include <gpu_label_gen/gen_timing.hpp>

void gpu_label_gen (CSR_graph<weight_type>& input_graph, hop_constrained_case_info_gpu *info, long long *L, long long &L_size, std::vector<int>& nid_vec, int nid_vec_id, double &sort_time_record, LabelGenTimings &timings);

#endif