# MultiGPU4CL

A Multi GPUs system for constructing hop-constrained shortest path 2-hop labeling indexes on large-scale graphs.

## Overview

MultiGPU4CL addresses the problem of **hop-constrained shortest path** querying: given a weighted graph and a hop constraint `h`, find the shortest distance (and path) between two vertices using at most `h` edges. This is a fundamental problem in knowledge networks, social networks, and graph databases.

The system builds a **hop-constrained 2-hop labeling index** — each vertex `v` stores a set of labels `(hub_vertex, parent_vertex, hop, distance)`. A query between `source` and `terminal` is answered by finding common hub vertices and combining their distances, achieving sub-millisecond query times after index construction.

### Key Features

- **Multi GPUs Label Generation**: Labels are generated in parallel using both GPU (CUDA) and CPU (multi-threaded) workers, scheduled via a priority queue that balances workload across devices.
- **GPU-Accelerated Label Cleaning**: Redundant labels are pruned on GPU using hash-based canonical repair, significantly reducing index size.
- **Graph Partitioning via CDLP**: The input graph is partitioned into groups using GPU-accelerated Community Detection via Label Propagation (CDLP), enabling distributed label generation across partitions.
- **Compact Label Encoding**: Labels are packed into 64-bit integers (`to_vertex`: 24 bits, `hub_vertex`: 24 bits, `hop`: 3 bits, `distance`: 10 bits) for efficient GPU memory usage.
- **Correctness Verification**: Built-in checker validates index correctness against hop-constrained Dijkstra results.

## Project Structure

```
MultiGPU4CL/
├── CMakeLists.txt              # Build configuration (CUDA + C++17)
├── Dockerfile                  # Docker build file
├── src/
│   ├── main.cu                 # Main entry point
│   ├── gpu_label_gen.cu        # GPU label generation kernels
│   └── gpu_label_clean.cu      # GPU label cleaning kernels
├── include/
│   ├── core/                   # Core utilities (types, CUDA error handling, cache flush)
│   ├── graph/                  # Graph data structures (CSR, LDBC, adjacency list)
│   ├── label/                  # Label types and query functions
│   ├── gpu_label_gen/          # GPU label generation headers
│   ├── cpu_label_gen/          # CPU label generation (multi-threaded HSDL)
│   ├── partition/              # Graph partitioning (CDLP, graph pool)
│   ├── checker/                # Correctness verification
│   └── utils/                  # Utility headers (thread pool, I/O, string parser)
└── data/                       # Graph datasets (.e format)
```

## Datasets

The `data/` directory contains real-world graph datasets in edge-list (`.e`) format. Each dataset may have a corresponding `_queries.txt` file containing query triples `(source, terminal, hop_constraint)`.

| Dataset | Description |
|---------|-------------|
| `CA-CondMat.e` | Condense Matter collaboration network |
| `DBLP.e` | DBLP co-authorship network |
| `Email-Enron.e` | Enron email communication network |
| `Email-EuAll.e` | EU email network |
| `com-amazon.e` | Amazon product co-purchasing network |
| `com-youtube.e` | YouTube social network |
| `web-Google.e` | Google web graph |
| `web-NotreDame.e` | Notre Dame web graph |
| `as-skitter.e` | Internet AS-level topology (Skitter) |
| `as-caida20071105.e` | CAIDA AS-level topology |
| `Amazon0302.e` | Amazon product network (2003) |
| `p2p-Gnutella31.e` | Gnutella P2P network |
| `wiki-talk.e` | Wikipedia talk network |
| `Gowalla_edges.e` | Gowalla location-based social network |
| `Brightkite_edges.e` | Brightkite location-based social network |
| `git_web_ml.e` | Git web machine learning graph |
| `twitch.e` | Twitch social network |

## Build & Run

### Prerequisites

- NVIDIA GPU with Compute Capability 8.6+ (e.g., RTX 3090, A100)
- NVIDIA Driver + CUDA Toolkit 11.8+
- CMake 3.17+
- GCC with C++17 support
- Boost library (1.85.0 or compatible)
- Docker + NVIDIA Container Toolkit (for Docker build)

### Option 1: Build Docker Image

```bash
cd /path/to/MultiGPU4CL
docker build -t multigpu4cl .
```

Run with a dataset:

```bash
docker run --gpus all --rm \
  -v /path/to/MultiGPU4CL/data:/workspace/MultiGPU4CL/data \
  -v /path/to/MultiGPU4CL/output:/workspace/MultiGPU4CL/output \
  multigpu4cl \
  /workspace/MultiGPU4CL/data/CA-CondMat.e 5 /workspace/MultiGPU4CL/output/result.txt 400 0
```

Interactive shell inside the container:

```bash
docker run --gpus all --rm -it \
  -v /path/to/MultiGPU4CL/data:/workspace/MultiGPU4CL/data \
  --entrypoint /bin/bash \
  multigpu4cl
```

### Option 2: Compile Codes using CMake

```bash
cd /path/to/MultiGPU4CL
rm -rf build && mkdir build && cd build
cmake ..
make -j$(nproc)
```

The compiled binary is at `build/bin/MultiGPU4CL`.

> **Note**: If Boost is not installed at the default path, modify the `include_directories` in `CMakeLists.txt` to point to your Boost installation. If your GPU has a different compute capability, update `--generate-code=arch=compute_86,code=sm_86` accordingly.

### Option 3: Run Experiments

```bash
cd /path/to/MultiGPU4CL/build/bin
CUDA_VISIBLE_DEVICES=0 ./MultiGPU4CL <data_path> <hop_cst> <output_path> <G_max> <cpu_type>
```

**Parameters:**

| Parameter | Description | Example |
|-----------|-------------|---------|
| `data_path` | Path to the graph `.e` file | `../../data/CA-CondMat.e` |
| `hop_cst` | Hop constraint (max number of edges) | `5` |
| `output_path` | Path for the output result file | `../../output/result.txt` |
| `G_max` | Maximum group size for graph partitioning | `400` |
| `cpu_type` | CPU generation algorithm: `0` = optimized BFS, `1` = original WWW | `0` |

**Examples:**

```bash
# Small graph
CUDA_VISIBLE_DEVICES=0 ./MultiGPU4CL ../../data/CA-CondMat.e 5 ../../output/result.txt 400 0

# Medium graph
CUDA_VISIBLE_DEVICES=0 ./MultiGPU4CL ../../data/DBLP.e 5 ../../output/result.txt 400 0

# Large graph
CUDA_VISIBLE_DEVICES=0 ./MultiGPU4CL ../../data/web-Google.e 5 ../../output/result.txt 400 0
```

## Output

The program outputs:

1. **Console**: Detailed timing breakdown for label generation and cleaning stages, label sizes, and correctness verification results.
2. **Result file**: A single line per run with key metrics including generation time, cleaning time, label sizes, and query times.


## Algorithm Pipeline

1. **Graph Loading**: Read the edge-list graph and reorder vertices by degree (descending).
2. **Graph Partitioning**: Partition vertices into groups using GPU-accelerated CDLP, with group sizes bounded by `G_max`.
3. **Label Generation**: For each partition, generate hop-constrained labels using GPU and/or CPU workers. GPU uses hash-based expansion with CSR graph; CPU uses multi-threaded BFS (HSDL / WWW optimized).
4. **Label Cleaning**: Remove redundant labels via canonical repair. GPU cleaning uses hash-based deduplication; CPU cleaning uses multi-threaded canonical repair.
5. **Correctness Check**: Validate the index by comparing query results against hop-constrained Dijkstra.
