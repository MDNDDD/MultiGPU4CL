cmake_minimum_required(VERSION 3.17)

project(MultiGPU4CL LANGUAGES CXX CUDA)

find_package(CUDA REQUIRED)
find_package(Boost 1.74 REQUIRED)

set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fopenmp -O3")
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(GPU_ARCH 86 CACHE STRING "GPU compute capability (e.g., 86 for RTX 3090, 89 for RTX 4090)")
set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} -O3 --generate-code=arch=compute_${GPU_ARCH},code=sm_${GPU_ARCH} -rdc=true")

set(EXECUTABLE_OUTPUT_PATH ${PROJECT_SOURCE_DIR}/build/bin)
include_directories(include ${CUDA_INCLUDE_DIRS} ${Boost_INCLUDE_DIRS})
aux_source_directory(src DIR_SRCS)

add_definitions(-w)

add_executable(${PROJECT_NAME} ${DIR_SRCS})

target_link_libraries(${PROJECT_NAME} ${CUDA_LIBRARIES})
target_link_libraries(${PROJECT_NAME} nvidia-ml)

set_target_properties(${PROJECT_NAME} PROPERTIES CUDA_SEPARABLE_COMPILATION ON)
