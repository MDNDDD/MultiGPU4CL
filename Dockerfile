FROM nvidia/cuda:11.8.0-cudnn8-devel-ubuntu22.04

ARG GPU_ARCH=86

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y \
    build-essential \
    cmake \
    git \
    wget \
    libboost-all-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /workspace/MultiGPU4CL

COPY CMakeLists.txt .
COPY src/ src/
COPY include/ include/

RUN rm -rf build && mkdir build && cd build && \
    cmake -DGPU_ARCH=${GPU_ARCH} .. && \
    make -j$(nproc)

COPY data/ data/

RUN mkdir -p output

WORKDIR /workspace/MultiGPU4CL/build/bin

ENTRYPOINT ["./MultiGPU4CL"]
