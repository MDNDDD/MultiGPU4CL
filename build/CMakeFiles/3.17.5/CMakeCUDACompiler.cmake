set(CMAKE_CUDA_COMPILER "/usr/local/cuda-11.8/bin/nvcc")
set(CMAKE_CUDA_HOST_COMPILER "")
set(CMAKE_CUDA_HOST_LINK_LAUNCHER "/opt/rh/devtoolset-11/root/usr/bin/g++")
set(CMAKE_CUDA_COMPILER_ID "NVIDIA")
set(CMAKE_CUDA_COMPILER_VERSION "11.8.89")
set(CMAKE_CUDA_STANDARD_COMPUTED_DEFAULT "17")
set(CMAKE_CUDA_COMPILE_FEATURES "cuda_std_03;cuda_std_11;cuda_std_14")
set(CMAKE_CUDA03_COMPILE_FEATURES "cuda_std_03")
set(CMAKE_CUDA11_COMPILE_FEATURES "cuda_std_11")
set(CMAKE_CUDA14_COMPILE_FEATURES "cuda_std_14")
set(CMAKE_CUDA17_COMPILE_FEATURES "")
set(CMAKE_CUDA20_COMPILE_FEATURES "")

set(CMAKE_CUDA_PLATFORM_ID "Linux")
set(CMAKE_CUDA_SIMULATE_ID "")
set(CMAKE_CUDA_COMPILER_FRONTEND_VARIANT "")
set(CMAKE_CUDA_SIMULATE_VERSION "")


set(CMAKE_CUDA_COMPILER_ENV_VAR "CUDACXX")
set(CMAKE_CUDA_HOST_COMPILER_ENV_VAR "CUDAHOSTCXX")

set(CMAKE_CUDA_COMPILER_LOADED 1)
set(CMAKE_CUDA_COMPILER_ID_RUN 1)
set(CMAKE_CUDA_SOURCE_FILE_EXTENSIONS cu)
set(CMAKE_CUDA_LINKER_PREFERENCE 15)
set(CMAKE_CUDA_LINKER_PREFERENCE_PROPAGATES 1)

set(CMAKE_CUDA_SIZEOF_DATA_PTR "8")
set(CMAKE_CUDA_COMPILER_ABI "ELF")
set(CMAKE_CUDA_LIBRARY_ARCHITECTURE "")

if(CMAKE_CUDA_SIZEOF_DATA_PTR)
  set(CMAKE_SIZEOF_VOID_P "${CMAKE_CUDA_SIZEOF_DATA_PTR}")
endif()

if(CMAKE_CUDA_COMPILER_ABI)
  set(CMAKE_INTERNAL_PLATFORM_ABI "${CMAKE_CUDA_COMPILER_ABI}")
endif()

if(CMAKE_CUDA_LIBRARY_ARCHITECTURE)
  set(CMAKE_LIBRARY_ARCHITECTURE "")
endif()

set(CMAKE_CUDA_TOOLKIT_INCLUDE_DIRECTORIES "/usr/local/cuda-11.8/targets/x86_64-linux/include")

set(CMAKE_CUDA_HOST_IMPLICIT_LINK_LIBRARIES "rt;pthread;dl")
set(CMAKE_CUDA_HOST_IMPLICIT_LINK_DIRECTORIES "/usr/local/cuda-11.8/targets/x86_64-linux/lib/stubs;/usr/local/cuda-11.8/targets/x86_64-linux/lib")
set(CMAKE_CUDA_HOST_IMPLICIT_LINK_FRAMEWORK_DIRECTORIES "")

set(CMAKE_CUDA_IMPLICIT_INCLUDE_DIRECTORIES "/usr/local/tbb/include;/opt/rh/devtoolset-11/root/usr/include/c++/11;/opt/rh/devtoolset-11/root/usr/include/c++/11/x86_64-redhat-linux;/opt/rh/devtoolset-11/root/usr/include/c++/11/backward;/opt/rh/devtoolset-11/root/usr/lib/gcc/x86_64-redhat-linux/11/include;/usr/local/include;/opt/rh/devtoolset-11/root/usr/include;/usr/include")
set(CMAKE_CUDA_IMPLICIT_LINK_LIBRARIES "rt;pthread;dl;stdc++;m;gcc_s;gcc;c;gcc_s;gcc")
set(CMAKE_CUDA_IMPLICIT_LINK_DIRECTORIES "/usr/local/cuda-11.8/targets/x86_64-linux/lib/stubs;/usr/local/cuda-11.8/targets/x86_64-linux/lib;/opt/rh/devtoolset-11/root/usr/lib/gcc/x86_64-redhat-linux/11;/opt/rh/devtoolset-11/root/usr/lib64;/lib64;/usr/lib64;/usr/local/openmpi/lib;/opt/rh/devtoolset-11/root/usr/lib")
set(CMAKE_CUDA_IMPLICIT_LINK_FRAMEWORK_DIRECTORIES "")

set(CMAKE_CUDA_RUNTIME_LIBRARY_DEFAULT "STATIC")

set(CMAKE_LINKER "/opt/rh/devtoolset-11/root/usr/bin/ld")
set(CMAKE_MT "")
