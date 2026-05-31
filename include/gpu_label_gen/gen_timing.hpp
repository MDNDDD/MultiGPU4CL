#ifndef GEN_TIMING_HPP
#define GEN_TIMING_HPP
#pragma once

struct LabelGenTimings {
    double expand_time = 0.0;
    double sort_time = 0.0;
    double tranverse_time = 0.0;
    double gather_time = 0.0;
    double memcpy_time = 0.0;
    double update_hash_time = 0.0;
    double clear_das_time = 0.0;
    double init_time = 0.0;
    double finalize_time = 0.0;
    double process_result_time = 0.0;
    
    double clean_init_hash_time = 0.0;
    double clean_label_time = 0.0;
    double clean_hash_time = 0.0;
    double clean_gather_time = 0.0;
    double clean_update_L_time = 0.0;
    double clean_convert_time = 0.0;
};

#endif