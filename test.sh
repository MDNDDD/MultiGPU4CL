rm -rf build
mkdir build
cd build
cmake ..
make -j$(nproc)
gpu_id=7
CUDA_VISIBLE_DEVICES=$gpu_id ./bin/HybridHopHL
