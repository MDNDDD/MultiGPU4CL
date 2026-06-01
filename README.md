# MultiGPU4CL

A Multi-GPU system for constructing hop-constrained shortest path 2-hop labeling indexes on large-scale graphs.

> This system implements the algorithms proposed in the paper, achieving **10.6-119.1x speedups** over the state-of-the-art CPU-based method (HBLL), and scaling to large graphs where prior work is too slow to be applied.

## Overview

MultiGPU4CL addresses the problem of **hop-constrained shortest path** querying: given a weighted graph and a hop constraint `h`, find the shortest distance (and path) between two vertices using at most `h` edges. This is a fundamental problem in knowledge networks, social networks, and graph databases, with applications in:

- **Information Retrieval in Knowledge Graphs**: Computing compact subgraphs spanning keyword-associated entities, where hop constraints enforce strong and concise relationships.
- **Reasoning Path Discovery in GraphRAG**: Extracting interpretable reasoning chains between query and answer entities in knowledge graphs, where limiting path lengths enforces concise reasoning.
- **Fraud Detection in Financial Networks**: Identifying suspicious transaction patterns within constrained hops.
- **Data Routing in Communication Networks**: Finding optimal routes with hop constraints.

The system builds a **hop-constrained 2-hop labeling index** -- each vertex `v` stores a set of labels `(hub_vertex, hop, distance)`. A query between `source` and `terminal` is answered by finding common hub vertices and combining their distances, achieving sub-millisecond query times after index construction.

## Key Innovations

### 1. GPU4CL: A GPU-Native Label Generation Algorithm

The state-of-the-art HBLL is inherently **vertex-centric**, causing severe workload imbalance on GPUs. GPU4CL fundamentally redesigns the algorithm with three novel ideas:

- **Label-Centric Paradigm**: Treats individual labels as fine-grained parallel units instead of vertices, decoupling labels from their associated vertices for workload-balanced parallelism aligned with GPU's SIMT model.
- **Synchronized Hop-Incremental Generation**: Employs a **traverse-prune-gather** three-phase iterative process that generates labels in increasing hop order, inherently guaranteeing **label minimality**.
- **Hop-Monotonicity-Based Distance Query**: Incorporates a novel **prefix-min** data structure that reduces distance query complexity from `O(delta*K)` to `O(delta)`, achieving a **smaller overall time complexity** than HBLL.

### 2. GPU Acceleration Techniques: FLaCSR & TravBalance

- **FLaCSR** (Flattened Label Compressed-Sparse-Row): A GPU-native label storage structure that enforces a two-level sorted layout (primary key: hop, secondary key: target vertex) with an offset array for random access. This ensures labels for the same vertex reside contiguously, enabling **coalesced memory accesses** and maximizing GPU bandwidth utilization.
- **TravBalance**: A three-tier, degree-aware scheduling hierarchy that dynamically adapts parallel granularity to vertex degree -- **Block-level** for high-degree vertices (entire GPU block collaborates), **Warp-level** for medium-degree vertices, and **Aggregation-based** for low-degree vertices (packed into a contiguous buffer via prefix sum).

### 3. Multi-GPU Label Generation & Cleaning

Multi-GPU4CL addresses the challenge of **global label dependencies** across GPUs with community-detection-based task decomposition, global-traversal-local-labeling strategy, priority-queue-based scheduling, and asynchronous label offloading. The subsequent GPU4CLEAN eliminates redundant labels produced in the distributed setting using CUDA Unified Memory with FLaCSR format and hop-monotonicity-based pruning, proven to produce `L_can` -- the **minimal** label set satisfying the hop-constrained label cover constraint.

### 4. Compact Label Encoding & Space-Efficient Predecessor Storage

- **64-bit Packed Labels**: Labels packed into 64-bit integers (`to_vertex`: 24 bits, `hub_vertex`: 24 bits, `hop`: 3 bits, `distance`: 10 bits).
- **Edge-ID-Based Predecessor**: Stores edge IDs instead of predecessor vertices, saving ~**20% GPU memory**.

## Project Structure

```
MultiGPU4CL/
+-- CMakeLists.txt              # Build configuration (CUDA + C++17)
+-- Dockerfile                  # Docker build file
+-- src/
|   +-- main.cu                 # Main entry point
|   +-- gpu_label_gen.cu        # GPU label generation kernels (GPU4CL)
|   +-- gpu_label_clean.cu      # GPU label cleaning kernels (GPU4CLEAN)
+-- include/
|   +-- core/                   # Core utilities (types, CUDA error handling, cache flush)
|   +-- graph/                  # Graph data structures (CSR, LDBC, adjacency list)
|   +-- label/                  # Label types and query functions
|   +-- gpu_label_gen/          # GPU label generation headers
|   +-- cpu_label_gen/          # CPU label generation (multi-threaded HSDL)
|   +-- partition/              # Graph partitioning (CDLP, graph pool)
|   +-- checker/                # Correctness verification
|   +-- utils/                  # Utility headers (thread pool, I/O, string parser)
+-- data/                       # Graph datasets (.e format)
```

## Datasets

The `data/` directory contains real-world graph datasets in edge-list (`.e`) format. Each dataset may have a corresponding `_queries.txt` file containing query triples `(source, terminal, hop_constraint)`.

| Dataset | Vertices | Edges | Description |
|---------|----------|-------|-------------|
| `as-caida20071105.e` | 26,475 | 183,831 | Internet Topology |
| `p2p-Gnutella31.e` | 62,586 | 147,892 | Communication Network |
| `web-Google.e` | 875,713 | 4,322,051 | Web Graph |
| `DBLP.e` | 1,094,552 | 6,911,318 | Citation Network |
| `com-youtube.e` | 1,134,890 | 2,987,624 | Social Network |
| `soc-lastfm.e` | 1,191,805 | 4,519,330 | Social Network |
| `as-skitter.e` | 1,695,659 | 11,095,298 | Internet Topology |
| `wiki-talk.e` | 2,369,181 | 5,021,410 | Social Network |

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

1. **Graph Loading**: Read the edge-list graph and reorder vertices by degree (descending), following the canonical labeling idea where higher-degree vertices serve as hubs for lower-degree ones.
2. **Graph Partitioning**: Partition vertices into balanced, weakly-coupled communities using GPU-accelerated CDLP with a strict size bound `G_max`, ensuring groups fit within GPU memory and maintain balanced workloads.
3. **Label Generation (Multi-GPU4CL)**: For each community, generate hop-constrained labels using GPU and/or CPU workers via the label-centric, hop-incremental traverse-prune-gather process. GPU uses hash-based expansion with CSR graph; CPU uses multi-threaded BFS (HSDL / WWW optimized). A priority queue balances workload across devices. Asynchronous label offloading transfers completed labels from GPU to CPU memory.
4. **Label Cleaning (Multi-GPU4CLEAN)**: Remove redundant labels via canonical repair using CUDA Unified Memory with FLaCSR format. GPU cleaning uses hash-based deduplication with hop-monotonicity-based distance queries; CPU cleaning uses multi-threaded canonical repair. The result is a **minimal** label set satisfying the hop-constrained label cover constraint.
5. **Correctness Check**: Validate the index by comparing query results against hop-constrained Dijkstra.

## Experimental Results

Experiments on 8 real-world datasets demonstrate that:

- **Speed**: Multi-GPU4CL+CLEAN achieves **10.6-119.1x speedups** over the state-of-the-art HBLL across all datasets and parameter settings (K=2~5). Even with a single GPU, it consistently ranks as the second-fastest approach.
- **Scalability**: HBLL fails to complete label generation for DBLP within 10,000 seconds, whereas Multi-GPU4CL+CLEAN finishes in just a few hundred seconds using 4 GPUs.
- **Index Size**: Multi-GPU4CL+CLEAN consistently generates a **minimal** label set, producing more compact indexes than HBLL and ImprovedHBLL whose parallel execution yields non-minimal label sets with redundant entries.
- **Query Efficiency**: The minimal label set of Multi-GPU4CL+CLEAN achieves slightly higher query efficiency than HBLL and ImprovedHBLL, since redundant entries in their label sets degrade query performance.
- **GPU Suitability**: A direct GPU implementation of HBLL underperforms its CPU counterpart due to vertex-centric architectural mismatch with GPU's SIMT model. In contrast, GPU4CL's label-centric design is explicitly aligned with GPU parallelism.
