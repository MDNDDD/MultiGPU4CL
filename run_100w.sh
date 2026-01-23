#!/bin/bash
echo "test"

rm -rf build
mkdir build
cd build
cmake3 ..
make
cd ..

declare -A data_set
data_set[0]="amazon-meta"
data_set[1]="web-BerkStan"
data_set[2]="web-Google"
data_set[3]="com-youtube"
data_set[4]="DBLP"
data_set[5]="wiki-talk"
data_set[6]="as-skitter"
data_set[7]="reddit"
echo ${data_set[*]}

declare -A data_dir
data_dir['amazon-meta']="/home/mdnd/dataset/data_exp_amazon-meta/amazon-meta"
data_dir['web-BerkStan']="/home/mdnd/dataset/data_exp_web-BerkStan/web-BerkStan"
data_dir['web-Google']="/home/mdnd/dataset/data_exp_web-Google/web-Google"
data_dir['com-youtube']="/home/mdnd/dataset/data_exp_com-youtube/com-youtube"
data_dir['as-skitter']="/home/mdnd/dataset/data_exp_as-skitter/as-skitter"
data_dir['DBLP']="/home/mdnd/dataset/data_exp_DBLP/DBLP"
data_dir['wiki-talk']="/home/mdnd/dataset/data_exp_wiki-talk/wiki-talk"
data_dir['reddit']="/home/mdnd/dataset/data_exp_reddit/reddit"
echo ${data_dir[*]}

output="/home/mdnd/Hybrid_Generation_Clean_EXP/exp_record/graph0/result_Hybrid_GPU_data_exp_100w.csv"
gpu_id=0

gmax=(1000)

for data_set_name in $(seq 7 7); do
    if [[ " ${!data_set[@]}" =~ "$data_set_name" ]]; then
        data_dir_1=${data_dir[${data_set[$data_set_name]}]}
        dataset_file="$data_dir_1/*.e"
        if [ -d "$data_dir_1" ]; then
            if ls $dataset_file 1> /dev/null 2>&1; then
                dataset=$(ls $dataset_file)
                echo "Success: The appropriate dataset file or query file has been found."
                for ((upper_k=5;upper_k<=5;upper_k++)) do  # upper_k from 2 to 5
                    echo "Error 1 !!!!"
                    for ((i=0;i<${#gmax[@]};i++)); do
                        echo "Error 2 !!!!"
                        CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/Test "$dataset" "$upper_k" "$output" "${gmax[i]}" "1"
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