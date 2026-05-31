#ifndef CLEAN_LABEL_CUH
#define CLEAN_LABEL_CUH
#pragma once

#include <cuda_runtime.h>
#include <device_launch_parameters.h>
#include <graph/csr_graph.hpp>
#include <gpu_label_gen/gpu_label_manager.cuh>
#include <gpu_label_gen/gpu_label_gen.cuh>

void gpu_label_clean(CSR_graph<weight_type>& input_graph, long long L_clean_start, long long L_clean_end, hop_constrained_case_info_gpu* info_gpu, long long& last_pos, LabelGenTimings& timings);

#endif