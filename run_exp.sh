#!/bin/bash

rm -rf build
mkdir build
cd build
cmake ..
make -j$(nproc)
cd ..

declare -A data_set
data_set[0]="as-caida20071105"
data_set[1]="p2p-Gnutella31"
data_set[2]="web-Google"
data_set[3]="DBLP"
data_set[4]="com-youtube"
data_set[5]="as-skitter"
data_set[6]="wiki-talk"
data_set[7]="reddit"
data_set[8]="wiki_category"
echo ${data_set[*]}

declare -A data_dir
data_dir['as-caida20071105']="/home/nongda/dataset/data_exp_1w/as-caida20071105"
data_dir['p2p-Gnutella31']="/home/nongda/dataset/data_exp_1w/p2p-Gnutella31"
data_dir['web-Google']="/home/nongda/dataset/data_exp_web-Google/web-Google"
data_dir['DBLP']="/home/nongda/dataset/data_exp_DBLP/DBLP"
data_dir['com-youtube']="/home/nongda/dataset/data_exp_com-youtube/com-youtube"
data_dir['wiki-talk']="/home/nongda/dataset/data_exp_wiki-talk/wiki-talk"
data_dir['as-skitter']="/home/nongda/dataset/data_exp_as-skitter/as-skitter"
data_dir['reddit']="/home/nongda/dataset/data_exp_reddit/reddit"
data_dir['wiki_category']="/home/nongda/dataset/data_exp_wiki_category/wiki_category"
echo ${data_dir[*]}

output="/home/nongda/HybridHopHL_v4/exp_record/result_Hybrid_GPU_data_exp_no_wb.csv"
gpu_id=7

# gmax=(100 500 2000)
gmax=(500)
# exp_dataset=("0" "1" "2" "3" "4" "5" "6" "7")
exp_dataset=("1")

# for data_set_name in $(seq 6 7); do
for data_set_name in "${exp_dataset[@]}"; do
    if [[ " ${!data_set[@]}" =~ "$data_set_name" ]]; then
        data_dir_1=${data_dir[${data_set[$data_set_name]}]}
        dataset_file="$data_dir_1/*.e"
        if [ -d "$data_dir_1" ]; then
            if ls $dataset_file 1> /dev/null 2>&1; then
                dataset=$(ls $dataset_file)
                echo "Success: The appropriate dataset file or query file has been found."
                for ((upper_k=5;upper_k<=5;upper_k++)) do  # upper_k from 2 to 5
                    for ((i=0;i<${#gmax[@]};i++)); do
                        # CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/HybridHopHL "$dataset" "$upper_k" "$output" "${gmax[i]}" "1"
                        CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/HybridHopHL "$dataset" "$upper_k" "$output" "${gmax[i]}" "0"
                    done
                done
            else
                echo "Warning: No suitable dataset file or query file was found in the directory $data_dir_1. Skip this directory."
            fi
        fi
    else
        echo "Error: Index $index not existed"
    fi
done

echo "The test is completed and the results have been written to the $output file."