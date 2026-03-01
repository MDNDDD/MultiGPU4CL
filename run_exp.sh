#!/bin/bash
echo "test"

rm -rf build
mkdir build
cd build
cmake3 ..
make
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
echo ${data_set[*]}

declare -A data_dir
data_dir['as-caida20071105']="/home/mdnd/dataset/data_exp_1w/as-caida20071105"
data_dir['p2p-Gnutella31']="/home/mdnd/dataset/data_exp_1w/p2p-Gnutella31"
data_dir['web-Google']="/home/mdnd/dataset/data_exp_web-Google/web-Google"
data_dir['DBLP']="/home/mdnd/dataset/data_exp_DBLP/DBLP"
data_dir['com-youtube']="/home/mdnd/dataset/data_exp_com-youtube/com-youtube"
data_dir['wiki-talk']="/home/mdnd/dataset/data_exp_wiki-talk/wiki-talk"
data_dir['as-skitter']="/home/mdnd/dataset/data_exp_as-skitter/as-skitter"
data_dir['reddit']="/home/mdnd/dataset/data_exp_reddit/reddit"
echo ${data_dir[*]}

output="/home/mdnd/HybridHopHL/exp_record/result_Hybrid_GPU_data_exp_no_csr.csv"
gpu_id=0

# gmax=(100, 500, 2000)
gmax=(400)

for data_set_name in $(seq 0 7); do
    if [[ " ${!data_set[@]}" =~ "$data_set_name" ]]; then
        data_dir_1=${data_dir[${data_set[$data_set_name]}]}
        dataset_file="$data_dir_1/*.e"
        if [ -d "$data_dir_1" ]; then
            if ls $dataset_file 1> /dev/null 2>&1; then
                dataset=$(ls $dataset_file)
                echo "Success: The appropriate dataset file or query file has been found."
                for ((upper_k=2;upper_k<=5;upper_k++)) do  # upper_k from 2 to 5
                    for ((i=0;i<${#gmax[@]};i++)); do
                        # CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/Test "$dataset" "$upper_k" "$output" "${gmax[i]}" "1"
                        CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/Test "$dataset" "$upper_k" "$output" "${gmax[i]}" "0"
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