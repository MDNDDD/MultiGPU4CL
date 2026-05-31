#ifndef CPU_LABEL_MANAGER_HPP
#define CPU_LABEL_MANAGER_HPP
#pragma once

#include <bits/stdc++.h>
#include <core/types.h>
#include <label/label_types.cuh>
#include <graph/graph_v_of_v.hpp>

class hop_constrained_case_info_cpu {
public:
	/*hop bounded*/
	int thread_num = 1;
	int upper_k = 0;
	bool use_rank_prune = false;
	bool use_2023WWW_generation = false;
	bool use_2023WWW_generation_optimized = false;
	bool use_GPU_version_generation = false;
	bool use_GPU_version_generation_optimized = false;
	bool use_canonical_repair = 1;

	/*running time records*/
	double time_initialization = 0;
	double time_generate_labels = 0;
	double time_traverse = 0;
	double time_clear = 0;
	double time_sortL = 0;
	double time_canonical_repair = 0;
	double time_total = 0;
	double label_size = 0;
	
	/*running limits*/
	long long int max_bit_size = 1e12;
	double max_run_time_seconds = 36000;

	/*labels*/
	std::vector<std::vector<hop_constrained_two_hop_label>> L;

	double label_size_before_canonical_repair, label_size_after_canonical_repair, canonical_repair_remove_label_ratio;

	void compute_label_size_per_node(int V) {
		for (auto &xx : L) {
			label_size = label_size + xx.size();
		}
		label_size = label_size / (double) V;
	}

	long long int compute_label_bit_size() {
		long long int size = 0;
		for (auto &xx : L) {
			size = size + xx.size() * sizeof(hop_constrained_two_hop_label);
		}
		return size;
	}

	/*clear labels*/
	void clear_labels() {
		std::vector<std::vector<hop_constrained_two_hop_label>>().swap(L);
	}

	void print_L(std::vector<std::vector<hop_constrained_two_hop_label>> &LL) {
		std::cout << "print_L: (hub_vertex, hop, distance, parent_vertex)" << std::endl;
		for (auto &xx : LL) {
			for (auto &yy : xx) {
				std::cout << "(" << yy.hub_vertex << "," << yy.hop << "," << yy.distance << "," << yy.parent_vertex << ") ";
			}
			std::cout << std::endl;
		}
	}

	/*record_all_details*/
	void record_all_details(std::string save_name) {
		std::ofstream outputFile;
		outputFile.precision(6);
		outputFile.setf(std::ios::fixed);
		outputFile.setf(std::ios::showpoint);
		outputFile.open(save_name + ".txt");

		outputFile << "hop_constrained_case_info:" << std::endl;
		outputFile << "thread_num=" << thread_num << std::endl;
		outputFile << "upper_k=" << upper_k << std::endl;
		// outputFile << "use_2M_prune=" << use_2M_prune << endl;
		outputFile << "use_2023WWW_generation=" << use_2023WWW_generation << std::endl;
		outputFile << "use_canonical_repair=" << use_canonical_repair << std::endl;

		outputFile << "time_initialization=" << time_initialization << std::endl;
		outputFile << "time_generate_labels=" << time_generate_labels << std::endl;
		outputFile << "time_sortL=" << time_sortL << std::endl;
		outputFile << "time_canonical_repair=" << time_canonical_repair << std::endl;
		outputFile << "time_total=" << time_total << std::endl;

		outputFile << "max_bit_size=" << max_bit_size << std::endl;
		outputFile << "max_run_time_seconds=" << max_run_time_seconds << std::endl;

		outputFile << "label_size_before_canonical_repair=" << label_size_before_canonical_repair << std::endl;
		outputFile << "label_size_after_canonical_repair=" << label_size_after_canonical_repair << std::endl;
		outputFile << "canonical_repair_remove_label_ratio=" << canonical_repair_remove_label_ratio << std::endl;

		outputFile << "compute_label_bit_size()=" << compute_label_bit_size() << std::endl;

		outputFile.close();
	}
};

#endif