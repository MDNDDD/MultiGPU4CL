FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/MultiGPU4CL

COPY . .

RUN sed -i 's|include_directories("/home/mdnd/boost_1_85_0")|include_directories("/usr/include")|g' CMakeLists.txt

RUN rm -rf build && mkdir build && cd build && cmake .. && make -j$(nproc)

WORKDIR /workspace/MultiGPU4CL/build/bin

ENTRYPOINT ["./MultiGPU4CL"]
