rm -rf build
mkdir build
cd build
cmake3 ..
make
gpu_id=0
CUDA_VISIBLE_DEVICES=$gpu_id ./bin/Test