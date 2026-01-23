#!/bin/bash
echo "Test"

rm -rf build
mkdir build
cd build
cmake3 ..
make
cd ..

declare -A data_set
data_set[0]="as-caida20071105"
data_set[1]="Brightkite_edges"
data_set[2]="CA-CondMat"
data_set[3]="Email-Enron"
data_set[4]="git_web_ml"
data_set[5]="p2p-Gnutella31"
data_set[6]="twitch"
data_set[7]="Amazon0302"
data_set[8]="com-amazon"
data_set[9]="Email-EuAll"
data_set[10]="Gowalla_edges"
data_set[11]="web-NotreDame"
echo ${data_set[*]}

declare -A data_dir
data_dir['as-caida20071105']="/home/mdnd/dataset/data_exp_1w/as-caida20071105"
data_dir['Brightkite_edges']="/home/mdnd/dataset/data_exp_1w/Brightkite_edges"
data_dir['CA-CondMat']="/home/mdnd/dataset/data_exp_1w/CA-CondMat"
data_dir['Email-Enron']="/home/mdnd/dataset/data_exp_1w/Email-Enron"
data_dir['git_web_ml']="/home/mdnd/dataset/data_exp_1w/git_web_ml"
data_dir['p2p-Gnutella31']="/home/mdnd/dataset/data_exp_1w/p2p-Gnutella31"
data_dir['twitch']="/home/mdnd/dataset/data_exp_1w/twitch"
data_dir['Amazon0302']="/home/mdnd/dataset/data_exp_10w/Amazon0302"
data_dir['com-amazon']="/home/mdnd/dataset/data_exp_10w/com-amazon"
data_dir['Email-EuAll']="/home/mdnd/dataset/data_exp_10w/Email-EuAll"
data_dir['Gowalla_edges']="/home/mdnd/dataset/data_exp_10w/Gowalla_edges"
data_dir['web-NotreDame']="/home/mdnd/dataset/data_exp_10w/web-NotreDame"
echo ${data_dir[*]}

# data_dir="/home/mdnd/data_exp_10"
output="/home/mdnd/Hybrid_Generation_Clean_EXP/exp_record/graph0/result_Hybrid_GPU_data_exp.csv"
gpu_id=2

for data_set_name in $(seq 0 11); do
    if [[ " ${!data_set[@]}" =~ "$data_set_name" ]]; then
        data_dir_1=${data_dir[${data_set[$data_set_name]}]}
        dataset_file="$data_dir_1/*.e"
        if [ -d "$data_dir_1" ]; then
            if ls $dataset_file 1> /dev/null 2>&1; then
                dataset=$(ls $dataset_file)
                echo "Success: The appropriate dataset file or query file has been found."
                for ((upper_k=2;upper_k<=5;upper_k++)) do  # upper_k from 2 to 5
                   CUDA_VISIBLE_DEVICES=$gpu_id ./build/bin/Test "$dataset" "$upper_k" "$output"
                done
            else
                echo "Warning: No suitable dataset file or query file was found in the directory $data_dir_1. Skip this directory."
            fi
        fi
    else
        echo "Error: Index $index not existed."
    fi
done

echo "The test is completed and the results have been written to the $output file."