# HybridHopHL_v4 多GPU适配改造方案

## 一、问题分析

当前代码仅支持单GPU运行，存在以下主要问题：

| # | 问题描述 | 当前代码 | 改造方案 |
|---|---------|-----------|---------|
| 1 | **类名硬编码** | `hop_constrained_case_info_v2` | 重命名为 `hop_constrained_case_info_gpu` |
| 2 | **文件路径硬编码** | `include/label/gpu_label_manager.cuh` | 移动到 `include/gpu_label_gen/gpu_label_manager.cuh` |
| 3 | **缺少设备ID设置** | `init()` 和 `check_flahash` 等函数 | 添加 `cudaSetDevice(device_id)` 调用 |
| 4 | **清理初始化缺少设备设置** | `init_clean()` 和 `check_flahash` 等函数 | 添加 `cudaSetDevice(device_id)` 调用 |
| 5 | **标签生成缺少设备设置** | `gpu_label_gen()` 和 `check_wb` 等函数 | 添加 `cudaSetDevice(device_id)` 调用 |
| 6 | **严重Bug** | `gpu_gen_worker` 中多个GPU共享写入 `L_global` | 每个GPU独立使用 `L_local` 并行生成标签 |
| 7 | **索引问题** | 多个 `clean_update_labels` 和GPU之间共享 `L_start/L_end` | 每个GPU独立处理不同范围 |
| 8 | **资源释放问题** | `destroy_clean()` 释放所有资源 | 仅GPU 0释放共享资源，其他GPU释放本地资源 |
| 9 | **CSR图拷贝问题** | `copy_to_device` 拷贝了5个GPU指针 | 只拷贝 `in_*` 和 `all_*` 需要的指针，并修改 `destroy_csr_graph` |
| 10 | **显存不足问题** | 在40GB GPU上显存严重不足 | 需要支持 80GB+ GPU 或降低显存使用 |
| 11 | **内存泄漏Bug** | `main.cu` 中 `cudaFreeHost(L)` 导致double free，约202行和385行 | 移除错误的释放调用 |
| 12 | **并发安全问题** | 多GPU共享 `L_clean` 和 `last_pos` 等指针 | 需要确保线程安全 + 适当同步 |

---

## 二、多GPU架构设计

### 1.1 单GPU架构问题

当前代码 `GPU_Gen_Num=4` 但实际只使用1个GPU进行计算，**即GPU数量设置为4但只运行在1个GPU上**。

- **缺少 `cudaSetDevice` 调用**：所有GPU操作都默认在 GPU 0 上执行
- **共享单个 `info_gpu` 结构**：所谓"多GPU并行"实际共享 `T`、`has`、`das` 等哈希表资源
- **缺少同步机制**：`Executive_Core` 调度逻辑未考虑多GPU之间的同步
- **CSR图仅在GPU 0**：`cudaMallocManaged` 分配的内存都在 GPU 0 上

### 1.2 显存需求分析与多GPU扩展

以下为关键数据结构的显存需求，基于 `TABLE_SIZE = 1599999983` 和 `TABLE_SIZE_CLEAN = 2999999929`：

| 数据结构 | 单GPU显存 | 计算方式 | 所属阶段 |
|---------|---------|---------|---------|
| `has` | **~11.9 GB** | 1,599,999,983 × 8B = 12,799,999,864 B ≈ 11.9 GiB | 生成 |
| `das` | **~11.9 GB** | 同 `has` | 生成 |
| `T` | **动态** | 按 `free × 0.40 / 8` 比例分配剩余显存 | 生成 |
| `T_offset_begin/end` | **(hop_cst+1)×(V+1)×16B** | 若 V=10M, hop_cst=5 则 ~960 MB | 生成 |
| `flag` | **动态** | 按 `free × 0.05 / 1` 比例分配 | 生成 |
| `D_sort_temp` | **动态** | 按 `free × 0.35 / 8` 比例分配 | 生成 |
| `nid` + `nid_size` | **~数十MB** | 与图分区数量相关 | 生成 |
| CSR图数据 | **~数百MB** | out_pointer/out_edge/out_edge_weight/source/inv | 生成+清理 |
| `has_clean` | **~22.4 GB** | 2,999,999,929 × 8B = 23,999,999,432 B ≈ 22.4 GiB | 清理 |
| `L_clean` | **~数十GB** | (L_size + 1) × 8B | 清理 |
| `L_start/L_end` | **~数十GB** | (V + 1) × 8B × 2 | 清理 |
| `mark` | **~数GB** | (L_size + 1) × 1B | 清理 |
| `sort_temp` | **~6.0 GB** | 800,000,000 × 8B = 6,400,000,000 B ≈ 6.0 GiB | 清理 |

**生成阶段GPU显存需求**（以 80GB A100 为例）：
- `has` + `das` ≈ 23.8 GB
- `T_offset_begin` + `T_offset_end` ≈ 960 MB（V=10M, hop_cst=5）
- 剩余 `has`/`das`/`T_offset` 之后的可用显存 ≈ 80 - 23.8 - 0.96 ≈ 55.2 GB
- `T` (40%) ≈ 22.1 GB, `flag` (5%) ≈ 2.8 GB, `D_sort_temp` (35%) ≈ 19.3 GB
- CSR图数据 ≈ 数百MB
- **生成阶段总计 ≈ 69 GB/GPU**

**清理阶段GPU显存需求**：
- `has_clean` ≈ 22.4 GB
- `sort_temp` ≈ 6.0 GB
- `L_clean` + `L_start` + `L_end` + `mark` ≈ 数GB ~ 数十GB（取决于图规模）
- **清理阶段总计 ≈ 30-50+ GB/GPU**

> **关键结论**：生成阶段和清理阶段不会同时运行，调用 `destroy_L_cuda()` 后释放生成阶段资源，再进入清理阶段。因此单GPU需要满足两个阶段的较大者。对于 80GB GPU，生成阶段需要约 69GB，可以满足；对于 40GB GPU，仅 `has`+`das` 就需要 23.8GB，剩余空间不足以容纳 `T`+`D_sort_temp`，**必须降低哈希表大小或使用更大显存GPU**。

### 1.3 并行性分析

**生成阶段**：天然可并行
- 每个图分区`graph_group[i]`的标签生成相互独立
- `gpu_label_gen` 内部的 `gen_hash_clear` 在每次调用前后清空哈希表，无跨分区依赖
- 每个GPU拥有独立的CSR图副本和独立的哈希表
- **并行度极高**：属于典型的embarrassingly parallel模式

**清理阶段**：需要协调的并行
- 按顶点范围 `[i, i+clean_size)` 分配 `clean_label_prune` 任务，但 `hub_vertex` 的查找可能跨范围访问 `L_clean`
- `clean_hash_init` 和 `clean_hash_clear` 对 `has_clean` 的操作按范围独立
- `clean_update_labels` 会修改 `L_start/L_end`，多GPU同时修改 `L_start/L_end` 存在数据竞争
- `last_pos` 的更新也需要原子操作，多GPU同时写入存在竞争

---

## 三、多GPU架构设计

### 2.1 架构图

```
┌──────────────────────────────────────────────────────────────────┐
│                      主控端 (Host)                        │
│  - 从argv解析用户指定的GPU ID列表                              │
│  - 读取并预处理CSR图                                   │
│  - 创建GPU资源并分配任务                                │
│  - 收集结果                                            │
│  - 合并标签                                            │
├──────────┬──────────────┬──────────────┬──────────────┤
           │          │          │          │
     ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐
     │gpu_ids[0]│ │gpu_ids[1]│ │gpu_ids[2]│ │gpu_ids[3]│
     │ Thread 0 │ │Thread 1 │ │Thread 2 │ │Thread 3 │
     │          │ │         │ │         │ │         │
     │ info[0]  │ │info[1]  │ │info[2]  │ │info[3]  │
     │ csr[0]   │ │csr[1]   │ │csr[2]   │ │csr[3]   │
     │ L_buf[0] │ │L_buf[1] │ │L_buf[2] │ │L_buf[3] │
     └──────────┘ └──────────┘ └──────────┘ └──────────┘
```

> **示例**：若用户指定 `argv[6] = "0,2,3,5"`，则 `gpu_ids = {0, 2, 3, 5}`，Thread 0 使用 GPU 0，Thread 1 使用 GPU 2，Thread 2 使用 GPU 3，Thread 3 使用 GPU 5。

### 2.2 设计原则

1. **Per-GPU 独立资源**：每个GPU拥有独立的 `hop_constrained_case_info_gpu` 实例和 CSR 图副本
2. **CPU多线程调度**：每个GPU对应一个 `std::thread` 线程
3. **动态任务分配**：使用互斥锁保护的任务队列，实现GPU间负载均衡
4. **独立输出缓冲**：每个GPU拥有独立的 host 端输出缓冲区
5. **内存优化**：继续使用 `cudaMallocManaged`，配合 `cudaMemAdvise` 设置数据位置

---

## 四、具体改造步骤

### 步骤1：修改 `Executive_Core` 结构体

**文件**: `include/core/types.h`

添加 `device_id` 字段，用于标识当前核心对应的GPU。

```cpp
struct Executive_Core {
    int id = 0;
    double time_use = 0.0;
    int core_type = 0;   // 0=CPU, 1=GPU
    int device_id = -1;  // 当前核心对应的GPU设备ID，-1表示CPU

    Executive_Core() = default;
    Executive_Core(int x, double y, int z) : id(x), time_use(y), core_type(z), device_id(z ? x : -1) {}
    Executive_Core(int x, double y, int z, int dev) : id(x), time_use(y), core_type(z), device_id(dev) {}

    friend bool operator<(const Executive_Core& a, const Executive_Core& b) {
        if (a.time_use == b.time_use) return a.id > b.id;
        return a.time_use > b.time_use;
    }
};
```

> **说明**：`device_id` 用于GPU资源管理，当核心类型为GPU时（`core_type == 1`），默认 `device_id = id`。此修改向后兼容，不影响现有CPU调度逻辑，但为后续多GPU调度提供基础设施。

### 步骤2：创建 `hop_constrained_case_info_gpu` 支持多GPU

**文件**: `include/gpu_label_gen/gpu_label_manager.cuh`

> **注意**：将原有的 `hop_constrained_case_info_v2` 重命名为 `hop_constrained_case_info_gpu`，并将文件从 `include/label/` 移动到 `include/gpu_label_gen/`。

主要修改：
- 添加 `device_id` 成员变量
- 所有 `cudaMallocManaged` / `cudaFree` 调用前添加 `cudaSetDevice(device_id)`
- `init()` 和 `set_nid()` 函数开头添加 `cudaSetDevice` 调用
- 拆分为 `destroy_clean_local()` 和 `destroy_clean_shared()` 分别释放本地和共享资源
- `init_clean()` 拆分为 `init_clean_shared()` 和 `init_clean_local()`

```cpp
class hop_constrained_case_info_gpu {
public:
    int device_id = 0;  // 当前核心对应的GPU设备ID

    // 修改 init，添加 device_id 参数，并在开头设置设备，包括 check_flahash
    __host__ void init(int V, int hop_cst, int G_max, int thread_num,
                       std::vector<std::vector<int>> graph_group, int dev_id = 0) {
        device_id = dev_id;
        cudaSetDevice(device_id);
        // ... 其余初始化逻辑不变 ...
    }

    __host__ void set_nid(int distributed_graph_num,
                          std::vector<std::vector<int>> graph_group) {
        cudaSetDevice(device_id);
        // ... 其余逻辑不变 ...
    }

    __host__ void destroy_L_cuda() {
        cudaSetDevice(device_id);
        // ... 其余释放逻辑不变 ...
    }

    // 初始化共享数据（仅主GPU调用）：L_clean, L_start, L_end, mark
    // 这些数据在主GPU上分配
    __host__ void init_clean_shared(int V,
        std::vector<std::vector<hop_constrained_two_hop_label>> &res,
        CSR_graph<weight_type> &csr_graph, long long L_size,
        std::unordered_map<std::pair<int, int>, int, PairHash> &edge_id, int G_max) {
        cudaSetDevice(device_id);

        last_size = 1;
        cudaMallocManaged(&L_start, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_end, (long long)(V + 1) * sizeof(long long));
        cudaMallocManaged(&L_clean, (long long)(L_size + 1) * sizeof(long long));
        cudaMallocManaged(&mark, (long long)(L_size + 1) * sizeof(char));
        cudaMemset(mark, 1, (long long)(L_size + 1) * sizeof(char));
        cudaDeviceSynchronize();

        L_clean[0] = 0x7FFFFFFFFFFFFFFFLL;
        L_start[0] = 1;
        for (int i = 0; i < V; ++i) {
            L_start[i + 1] = L_start[i] + res[i].size();
        }
        long long pos = L_start[V];

        #pragma omp parallel for schedule(dynamic, 128)
        for (int i = 0; i < V; ++i) {
            long long base = L_start[i];
            for (int j = 0; j < res[i].size(); ++j) {
                auto& lbl = res[i][j];
                if (edge_id.count(std::make_pair(i, lbl.parent_vertex)) == 0) {
                    L_clean[base + j] = get_label(csr_graph.OUTs_Neighbor_start_pointers[i],
                                                   lbl.hub_vertex, lbl.hop, lbl.distance);
                } else {
                    L_clean[base + j] = get_label(edge_id[std::make_pair(i, lbl.parent_vertex)],
                                                   lbl.hub_vertex, lbl.hop, lbl.distance);
                    if (lbl.hop == 0) {
                        lbl.parent_vertex = i;
                    }
                }
            }
            L_end[i] = base + res[i].size();
        }

        // 设置数据访问建议
        cudaMemAdvise(L_clean, (L_size + 1) * sizeof(long long),
                      cudaMemAdviseSetAccessedBy, device_id);
        cudaMemAdvise(L_start, (V + 1) * sizeof(long long),
                      cudaMemAdviseSetAccessedBy, device_id);
        cudaMemAdvise(L_end, (V + 1) * sizeof(long long),
                      cudaMemAdviseSetAccessedBy, device_id);
        cudaMemAdvise(mark, (L_size + 1) * sizeof(char),
                      cudaMemAdviseSetAccessedBy, device_id);
    }

    // 初始化每个GPU本地数据：has_clean, sort_temp
    // 每个GPU独立分配
    __host__ void init_clean_local() {
        cudaSetDevice(device_id);

        cudaMallocManaged(&has_clean, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMemset(has_clean, 0ll, (long long)TABLE_SIZE_CLEAN * sizeof(long long));
        cudaMallocManaged(&sort_temp, 800000000ll * sizeof(long long));
        cudaDeviceSynchronize();

        cudaMemAdvise(has_clean, (long long)TABLE_SIZE_CLEAN * sizeof(long long),
                      cudaMemAdviseSetPreferredLocation, device_id);
        cudaMemAdvise(sort_temp, 800000000ll * sizeof(long long),
                      cudaMemAdviseSetPreferredLocation, device_id);
    }

    // 通知非主GPU设备可以访问主GPU上分配的共享数据 L_clean/L_start/L_end/mark
    __host__ void advise_shared_access(int owner_device) {
        cudaSetDevice(device_id);
        // 将L_clean/L_start/L_end/mark 设置为主GPU上 init_clean_shared 分配的指针
        // 并调用 cudaMemAdviseSetAccessedBy 使当前GPU可以远程访问
        // 具体实现在步骤7的主函数中完成
    }

    // 释放当前GPU的本地资源
    __host__ void destroy_clean_local() {
        cudaSetDevice(device_id);
        cudaFree(has_clean);
        cudaFree(sort_temp);
    }

    // 释放共享资源（仅主GPU调用）
    __host__ void destroy_clean_shared() {
        cudaSetDevice(device_id);
        cudaFree(L_clean);
        cudaFree(L_start);
        cudaFree(L_end);
        cudaFree(mark);
    }
};
```

> **关键设计决策**：`init_clean` 拆分为 `init_clean_shared` 和 `init_clean_local`。共享数据（`L_clean`、`L_start`、`L_end`、`mark`）在主GPU（`gpu_ids[0]`）上分配，通过`cudaMemAdviseSetAccessedBy`让其他GPU可以远程访问；本地数据（`has_clean`、`sort_temp`）在每个GPU上独立分配。`mark` 数组在阶段1中被多个GPU并行写入，每个GPU写入 `mark[L_clean_start + tid]`，其中 `L_clean_start` 互不重叠。

### 步骤3：创建 `CSR_graph` 的多GPU拷贝

**文件**: `include/graph/csr_graph.hpp`

> **注意**：原有的 `copy_to_device` 硬编码拷贝了5个GPU指针（`out_pointer`、`out_edge`、`out_edge_weight`、`source`、`inv`），而 `destroy_csr_graph` 会释放 `in_pointer`、`in_edge`、`all_edge`、`in_edge_weight`、`out_edge_weight` 等未拷贝的指针，导致释放空指针或 `cudaFree` 出错。

新增方法 `copy_to_device(int target_device, CSR_graph<weight_type>& dst)`，将CSR图拷贝到指定GPU。

```cpp
template <typename weight_type>
class CSR_graph {
public:
    // ... 现有成员 ...

    __host__ void copy_to_device(int target_device, CSR_graph<weight_type>& dst) const {
        cudaSetDevice(target_device);

        int V = OUTs_Neighbor_start_pointers.size() - 1;
        int E_out = OUTs_Edges.size();
        int E_in = INs_Edges.size();
        int E_all_local = E_in + E_out;

        // 拷贝CPU端数据（std::vector 始终在CPU端）
        dst.INs_Neighbor_start_pointers = INs_Neighbor_start_pointers;
        dst.OUTs_Neighbor_start_pointers = OUTs_Neighbor_start_pointers;
        dst.ALL_start_pointers = ALL_start_pointers;
        dst.INs_Edges = INs_Edges;
        dst.OUTs_Edges = OUTs_Edges;
        dst.all_Edges = all_Edges;
        dst.ARRAY_source = ARRAY_source;
        dst.ARRAY_inv = ARRAY_inv;
        dst.pointer = pointer;
        dst.INs_Edge_weights = INs_Edge_weights;
        dst.OUTs_Edge_weights = OUTs_Edge_weights;
        dst.E_all = E_all_local;

        // 初始化所有GPU指针为 nullptr，防止 destroy_csr_graph 释放未分配的指针
        dst.in_pointer = nullptr;
        dst.out_pointer = nullptr;
        dst.in_edge = nullptr;
        dst.out_edge = nullptr;
        dst.all_pointer = nullptr;
        dst.all_edge = nullptr;
        dst.source = nullptr;
        dst.inv = nullptr;
        dst.in_edge_weight = nullptr;
        dst.out_edge_weight = nullptr;

        // 仅拷贝GPU标签生成所需的指针，gpu_label_gen 需要: out_pointer, out_edge, out_edge_weight, source, inv
        cudaMallocManaged(&dst.out_pointer, (V + 1) * sizeof(int));
        cudaMallocManaged(&dst.out_edge, E_out * sizeof(int));
        cudaMallocManaged(&dst.out_edge_weight, E_out * sizeof(int));
        cudaMallocManaged(&dst.source, E_out * sizeof(int));
        cudaMallocManaged(&dst.inv, E_out * sizeof(int));

        cudaMemcpy(dst.out_pointer, OUTs_Neighbor_start_pointers.data(),
                   (V + 1) * sizeof(int), cudaMemcpyDefault);
        cudaMemcpy(dst.out_edge, OUTs_Edges.data(),
                   E_out * sizeof(int), cudaMemcpyDefault);
        cudaMemcpy(dst.out_edge_weight, OUTs_Edge_weights.data(),
                   E_out * sizeof(int), cudaMemcpyDefault);
        cudaMemcpy(dst.source, ARRAY_source.data(),
                   E_out * sizeof(int), cudaMemcpyDefault);
        cudaMemcpy(dst.inv, ARRAY_inv.data(),
                   E_out * sizeof(int), cudaMemcpyDefault);

        // gpu_label_clean 需要: source, inv（已在上方拷贝）
        // 暂不拷贝 in_* / all_* 相关指针
        // 若 gpu_label_gen 和 gpu_label_clean 都需要 out_* / source / inv
        // 则上述拷贝已满足需求
        // cudaMallocManaged(&dst.in_pointer, (V + 1) * sizeof(int));
        // cudaMallocManaged(&dst.in_edge, E_in * sizeof(int));
        // cudaMallocManaged(&dst.all_pointer, (V + 1) * sizeof(int));
        // cudaMallocManaged(&dst.all_edge, E_all_local * sizeof(int));
        // cudaMallocManaged(&dst.in_edge_weight, E_in * sizeof(int));
        // cudaMemcpy(dst.in_pointer, INs_Neighbor_start_pointers.data(), ...);
        // cudaMemcpy(dst.in_edge, INs_Edges.data(), ...);
        // ...

        cudaDeviceSynchronize();

        // 设置数据位置建议
        cudaMemAdvise(dst.out_pointer, (V + 1) * sizeof(int),
                      cudaMemAdviseSetPreferredLocation, target_device);
        cudaMemAdvise(dst.out_edge, E_out * sizeof(int),
                      cudaMemAdviseSetPreferredLocation, target_device);
        cudaMemAdvise(dst.out_edge_weight, E_out * sizeof(int),
                      cudaMemAdviseSetPreferredLocation, target_device);
        cudaMemAdvise(dst.source, E_out * sizeof(int),
                      cudaMemAdviseSetPreferredLocation, target_device);
        cudaMemAdvise(dst.inv, E_out * sizeof(int),
                      cudaMemAdviseSetPreferredLocation, target_device);
    }

    // 修改 destroy_csr_graph，添加 nullptr 检查
    __host__ void destroy_csr_graph() {
        if (in_pointer) cudaFree(in_pointer);
        if (out_pointer) cudaFree(out_pointer);
        if (in_edge) cudaFree(in_edge);
        if (out_edge) cudaFree(out_edge);
        if (all_pointer) cudaFree(all_pointer);
        if (all_edge) cudaFree(all_edge);
        if (source) cudaFree(source);
        if (inv) cudaFree(inv);
        if (in_edge_weight) cudaFree(in_edge_weight);
        if (out_edge_weight) cudaFree(out_edge_weight);
        // 重置为 nullptr，防止 double free
        in_pointer = out_pointer = in_edge = out_edge = nullptr;
        all_pointer = all_edge = source = inv = nullptr;
        in_edge_weight = out_edge_weight = nullptr;
    }
};
```

> **注意**：`cudaMemcpy` 使用 `cudaMemcpyDefault` 而非 `cudaMemcpyHostToDevice`，因为源数据在 CPU `std::vector` 中，而目标为 `cudaMallocManaged` 分配的内存。使用`cudaMemcpyDefault` 可以自动判断传输方向。修改后的 `destroy_csr_graph` 添加了 nullptr 检查，防止释放未分配的指针。

### 步骤4：修改 `gpu_label_gen` 支持多GPU

**文件**: `src/gpu_label_gen.cu`

> **注意**：将原有的类型引用从 `hop_constrained_case_info_v2` 改为 `hop_constrained_case_info_gpu`。
> ```cpp
> void gpu_label_gen(CSR_graph<weight_type>& input_graph, hop_constrained_case_info_gpu *info,
>     long long *L, long long &L_size, std::vector<int>& nid_vec,
>     int nid_vec_id, double &sort_time_record, LabelGenTimings &timings)
> ```

在函数开头添加设备设置，确保所有操作在正确的GPU上执行。

```cpp
void gpu_label_gen(CSR_graph<weight_type>& input_graph, hop_constrained_case_info_gpu *info,
    long long *L, long long &L_size, std::vector<int>& nid_vec,
    int nid_vec_id, double &sort_time_record, LabelGenTimings &timings) {

    cudaSetDevice(info->device_id);  // 设置当前线程操作的GPU
    // ... 其余逻辑不变 ...
}
```

> **重要**：函数内部所有的 `cudaMalloc`、`cudaStreamCreate` 等CUDA调用都会作用于当前设备，因此必须在开头调用 `cudaSetDevice`，确保CUDA资源分配在正确的GPU上。

### 步骤5：修改 `gpu_label_clean` 支持多GPU

**文件**: `src/gpu_label_clean.cu`

> **注意**：将原有的 `hop_constrained_case_info_v2` 改为 `hop_constrained_case_info_gpu`。

在函数开头添加设备设置。

```cpp
void gpu_label_clean(CSR_graph<weight_type>& input_graph, long long L_clean_start,
    long long L_clean_end, hop_constrained_case_info_gpu *info_gpu,
    long long &last_pos, LabelGenTimings &timings) {

    cudaSetDevice(info_gpu->device_id);  // 设置当前线程操作的GPU
    // ... 其余逻辑不变 ...
}
```

> **额外注意**：当前 `gpu_label_clean` 中存在 `cudaMallocManaged(&d_num_selected, sizeof(long long))` 的临时分配，这会在当前GPU上分配但未在对应位置 `cudaFree`，可能导致内存泄漏。应在使用后立即 `cudaFree`，或改为在 `init_clean_local` 中预分配，使用后 `cudaFree`。

### 步骤6：修改 `gpu_warmup` 支持多GPU

**文件**: `include/core/gpu_warmup.cuh`

添加设备ID参数。

```cpp
inline void gpu_warmup(int device_id = 0) {
    cudaSetDevice(device_id);
    const int num_threads = 256, num_blocks = 256, iterations = 100;
    float* d_dummy;
    cudaMalloc(&d_dummy, num_threads * num_blocks * sizeof(float));
    gpu_warmup_kernel<<<num_blocks, num_threads>>>(d_dummy, iterations);
    cudaDeviceSynchronize();
    cudaFree(d_dummy);
}
```

### 步骤7：修改 `main.cu` 主函数

**文件**: `src/main.cu`

主要修改包括以下方面：

1. **从argv解析用户指定的GPU ID列表**
2. **验证指定GPU的可用性**
3. **为每个指定GPU创建独立的资源和CSR图副本**
4. **使用 `std::thread` 启动多GPU并行生成**
5. **合并生成结果**
6. **多GPU并行清理**

> **重要设计变更**：GPU ID 不再通过 `cudaGetDeviceCount` 自动检测并顺序分配（0,1,2,...），而是由用户通过命令行参数 `argv` 自定义指定。例如用户可以指定 `0,2,3` 来使用 GPU 0、GPU 2 和 GPU 3，跳过 GPU 1。这在多用户共享GPU集群时特别有用。

#### 7.1 全局变量和任务分配器

```cpp
std::vector<int> gpu_ids;  // 用户指定的GPU ID列表，通过argv输入

std::vector<hop_constrained_case_info_gpu*> info_gpu_vec;
std::vector<CSR_graph<weight_type>> csr_graph_vec;

std::mutex partition_mtx;
int next_partition_idx = 0;

int get_next_partition(int total) {
    std::lock_guard<std::mutex> lock(partition_mtx);
    if (next_partition_idx < total) {
        return next_partition_idx++;
    }
    return -1;
}
```

> **说明**：`gpu_ids` 存储用户指定的GPU设备ID列表。例如 `gpu_ids = {0, 2, 3}` 表示使用3个GPU，其设备ID分别为0、2、3。后续代码中 `gpu_ids[g]` 表示第 `g` 个工作线程对应的实际GPU设备ID。

#### 7.2 生成阶段：多GPU并行标签生成

> **注意**：原有的 `gpu_gen_worker` 存在**严重Bug**——所有GPU写入 `L_global + gpu_L_offsets[gpu_id]` 的偏移量 `gpu_L_offsets` 初始全为0，导致多个GPU的输出重叠写入同一块内存。后续通过 `gpu_L_offsets[gpu_id] = my_tot_L` 累加偏移量，但这存在数据竞争。
>
> **修复方案**：每个GPU独立分配 `L_local` 缓冲区，使用 `cudaMallocHost` 分配pinned memory，GPU各自写入独立的 `L_local`，最后合并到 `L_hybrid`。

```cpp
void gpu_gen_worker(int thread_idx,
                    std::vector<long long>& gpu_L_totals,
                    std::vector<LabelGenTimings>& gpu_timings,
                    std::vector<double>& gpu_gen_times,
                    int Distributed_Graph_Num,
                    double& sort_time_record) {
    int dev_id = gpu_ids[thread_idx];  // 获取该线程对应的实际GPU设备ID
    cudaSetDevice(dev_id);
    hop_constrained_case_info_gpu* my_info = info_gpu_vec[thread_idx];
    CSR_graph<weight_type>& my_csr = csr_graph_vec[thread_idx];

    // 每个GPU独立的 L 缓冲区
    long long* L_local;
    cudaMallocHost(&L_local, 10000000000ll * sizeof(long long));
    long long my_tot_L = 0;
    double my_time = 0.0;
    LabelGenTimings my_timings;

    while (true) {
        int part_id = get_next_partition(Distributed_Graph_Num);
        if (part_id < 0) break;

        auto begin = std::chrono::high_resolution_clock::now();
        long long current_delta = 0;
        gpu_label_gen(my_csr, my_info, L_local + my_tot_L,
                      current_delta, graph_pool.graph_group[part_id],
                      part_id, sort_time_record, my_timings);
        my_tot_L += current_delta;
        auto end = std::chrono::high_resolution_clock::now();
        my_time += std::chrono::duration<double>(end - begin).count();
    }

    gpu_L_totals[thread_idx] = my_tot_L;
    gpu_timings[thread_idx] = my_timings;
    gpu_gen_times[thread_idx] = my_time;

    // 将 L_local 保留到外部缓冲区
    // 由主线程负责合并，见 7.4 主函数
}
```

> **内存警告**：每个GPU的 `L_local` 需要 10B × 8 = 80GB 的 pinned host 内存，4 GPU 总共需要 320GB 的 host 内存。如果 host 内存不足，需要考虑以下方案：
> - 降低每个缓冲区大小
> - 使用 `mmap` 映射大文件作为缓冲区
> - 分批处理 `L` 缓冲区 + 定期合并到最终数据结构

#### 7.3 清理阶段：多GPU并行标签清理

> **注意**：清理阶段的多GPU并行化需要特别关注以下问题：
> 1. `clean_update_labels` kernel 会修改 `L_start[cur_src]` 和 `L_end[cur_src]`，多GPU同时修改存在数据竞争，且 `cur_src` 可能跨范围访问
> 2. `last_pos` 的更新需要原子操作，存在竞争
> 3. `gpu_clean_ranges` 的划分需要保证无重叠
>
> **解决方案**：采用**两阶段并行**策略：
> - **阶段1（并行剪枝）**：多GPU并行执行 `clean_label_prune`，只修改 `mark` 数组标记需要保留的标签，不修改 `L_start/L_end`
> - **阶段2（串行压缩）**：在 GPU 0 上串行执行 `DeviceSelect::Flagged` + `clean_update_labels`，统一更新 `L_start/L_end` 指针

```cpp
// 阶段1：并行剪枝
void gpu_clean_prune_worker(int thread_idx, long long V, long long clean_size,
                            hop_constrained_case_info_gpu* shared_info,
                            LabelGenTimings& total_timings) {
    int dev_id = gpu_ids[thread_idx];  // 获取该线程对应的实际GPU设备ID
    cudaSetDevice(dev_id);
    hop_constrained_case_info_gpu* my_info = info_gpu_vec[thread_idx];
    CSR_graph<weight_type>& my_csr = csr_graph_vec[thread_idx];

    while (true) {
        int range_start;
        {
            std::lock_guard<std::mutex> lock(partition_mtx);
            if (next_partition_idx >= V) break;
            range_start = next_partition_idx;
            next_partition_idx += clean_size;
        }
        long long range_end = min((long long)range_start + clean_size, V);

        long long L_clean_start_idx = shared_info->L_start[range_start];
        long long L_clean_end_idx = shared_info->L_end[range_end - 1];
        long long clean_num = L_clean_end_idx - L_clean_start_idx;
        if (clean_num <= 0) continue;

        long long BLOCKS_NUM = (clean_num - 1) / 256 + 1;

        // 初始化哈希表
        clean_hash_init<<<BLOCKS_NUM, 256>>>(
            shared_info->L_clean + L_clean_start_idx,
            my_info->has_clean, my_csr.source, clean_num, my_info->hop_cst);
        cudaDeviceSynchronize();

        // 并行剪枝，只修改 mark 数组（各GPU写入不重叠的区域）
        clean_label_prune<<<BLOCKS_NUM, 256>>>(
            shared_info->L_clean + L_clean_start_idx,
            shared_info->L_clean, shared_info->L_start, shared_info->L_end,
            my_info->has_clean, shared_info->mark, my_csr.source,
            clean_num, L_clean_start_idx);
        cudaDeviceSynchronize();

        // 清空哈希表
        clean_hash_clear<<<BLOCKS_NUM, 256>>>(
            my_info->has_clean, shared_info->L_clean + L_clean_start_idx,
            my_csr.source, clean_num, my_info->hop_cst);
        cudaDeviceSynchronize();
    }
}

// 阶段2：串行压缩（在 GPU 0 上执行）
void gpu_clean_compress(hop_constrained_case_info_gpu* info_gpu,
                        CSR_graph<weight_type>& csr_graph,
                        long long V, long long clean_size,
                        long long& last_pos, LabelGenTimings& timings) {
    cudaSetDevice(info_gpu->device_id);

    last_pos = 1;
    for (long long i = 0; i < V; i += clean_size) {
        long long range_end = min(i + clean_size, V);
        long long L_clean_start = info_gpu->L_start[i];
        long long L_clean_end = info_gpu->L_end[range_end - 1];
        long long clean_num = L_clean_end - L_clean_start;
        if (clean_num <= 0) continue;

        // Flagged select，根据 mark 数组筛选保留的标签
        long long* d_num_selected;
        cudaMallocManaged(&d_num_selected, sizeof(long long));
        void* d_temp_storage = nullptr;
        size_t temp_storage_bytes = 0;
        cub::DeviceSelect::Flagged(d_temp_storage, temp_storage_bytes,
            info_gpu->L_clean + L_clean_start,
            info_gpu->mark + L_clean_start,
            info_gpu->L_clean + last_pos,
            d_num_selected, clean_num);
        cudaDeviceSynchronize();
        cub::DeviceSelect::Flagged(info_gpu->sort_temp, temp_storage_bytes,
            info_gpu->L_clean + L_clean_start,
            info_gpu->mark + L_clean_start,
            info_gpu->L_clean + last_pos,
            d_num_selected, clean_num);
        cudaDeviceSynchronize();

        // 更新 L_start/L_end
        long long BLOCKS_NUM = (*d_num_selected - 1) / 256 + 1;
        clean_update_labels<<<BLOCKS_NUM, 256>>>(
            info_gpu->L_clean + last_pos,
            info_gpu->L_start, info_gpu->L_end,
            csr_graph.source, last_pos, *d_num_selected);
        cudaDeviceSynchronize();

        info_gpu->last_size += (*d_num_selected);
        last_pos += (*d_num_selected);
        cudaFree(d_num_selected);
    }
}
```

> **设计权衡**：阶段2虽然是串行的，但实际开销很小——`DeviceSelect::Flagged` 和 `clean_update_labels` 都是轻量级操作。真正的计算密集型操作（`clean_label_prune`）已在阶段1中并行化。如果未来需要进一步优化，可以考虑将阶段2也并行化，但需要更复杂的 `L_start/L_end` 指针更新策略。

#### 7.4 主函数整合

```cpp
int main(int argc, char** argv) {
    // ... 现有初始化逻辑 ...

    // ===== 从argv解析用户指定的GPU ID列表 =====
    // 命令行格式: ./program <data_path> <hop_cst> <output_path> <G_max> <cpu_type> <gpu_ids>
    // gpu_ids 格式: 逗号分隔的GPU设备ID，例如 "0,2,3" 表示使用GPU 0、2、3
    // 示例: ./program data.txt 5 output.txt 400 0 0,2,3
    if (argc < 7) {
        fprintf(stderr, "Usage: %s <data_path> <hop_cst> <output_path> <G_max> <cpu_type> <gpu_ids>\n", argv[0]);
        fprintf(stderr, "  gpu_ids: comma-separated GPU device IDs, e.g., \"0,2,3\"\n");
        return 1;
    }

    data_path = argv[1];
    hop_cst = std::stoi(argv[2]);
    out_put_path = argv[3];
    G_max = std::stoi(argv[4]);
    cpu_type = std::stoi(argv[5]);

    // 解析GPU ID列表
    std::string gpu_ids_str = argv[6];
    std::stringstream ss(gpu_ids_str);
    std::string token;
    while (std::getline(ss, token, ',')) {
        gpu_ids.push_back(std::stoi(token));
    }
    int num_gpus = gpu_ids.size();
    printf("User specified %d GPUs: ", num_gpus);
    for (int i = 0; i < num_gpus; i++) printf("%d ", gpu_ids[i]);
    printf("\n");

    // 验证指定GPU的可用性
    int device_count;
    cudaGetDeviceCount(&device_count);
    for (int i = 0; i < num_gpus; i++) {
        if (gpu_ids[i] < 0 || gpu_ids[i] >= device_count) {
            fprintf(stderr, "Error: GPU ID %d is invalid (available: 0-%d)\n", gpu_ids[i], device_count - 1);
            return 1;
        }
        cudaDeviceProp prop;
        cudaGetDeviceProperties(&prop, gpu_ids[i]);
        printf("GPU %d: %s (%.0f MB)\n", gpu_ids[i], prop.name, prop.totalGlobalMem / 1e6);
    }

    // ... 现有的CSR图读取和预处理逻辑 ...

    // ===== 为每个指定GPU创建独立的资源和CSR图副本 =====
    info_gpu_vec.resize(num_gpus);
    csr_graph_vec.resize(num_gpus);

    for (int g = 0; g < num_gpus; g++) {
        int dev_id = gpu_ids[g];
        cudaSetDevice(dev_id);
        csr_graph.copy_to_device(dev_id, csr_graph_vec[g]);

        info_gpu_vec[g] = new hop_constrained_case_info_gpu();
        info_gpu_vec[g]->hop_cst = hop_cst;
        info_gpu_vec[g]->set_nid(Distributed_Graph_Num, graph_pool.graph_group);
        info_gpu_vec[g]->init(V, hop_cst, G_max, thread_num,
                              graph_pool.graph_group, dev_id);  // 传入实际 device_id
        gpu_warmup(dev_id);
    }

    // ===== 生成阶段：多GPU并行标签生成 =====
    std::vector<long long*> gpu_L_buffers(num_gpus, nullptr);
    std::vector<long long> gpu_L_totals(num_gpus, 0);
    std::vector<LabelGenTimings> gpu_gen_timings(num_gpus);
    std::vector<double> gpu_gen_times(num_gpus, 0.0);

    next_partition_idx = 0;
    std::vector<std::thread> gen_threads;
    for (int g = 0; g < num_gpus; g++) {
        gen_threads.emplace_back([g, &gpu_L_totals, &gpu_gen_timings,
                                  &gpu_gen_times, Distributed_Graph_Num,
                                  &sort_time_record]() {
            int dev_id = gpu_ids[g];  // 获取该线程对应的实际GPU设备ID
            cudaSetDevice(dev_id);
            hop_constrained_case_info_gpu* my_info = info_gpu_vec[g];
            CSR_graph<weight_type>& my_csr = csr_graph_vec[g];

            long long* L_local;
            cudaMallocHost(&L_local, 10000000000ll * sizeof(long long));
            gpu_L_buffers[g] = L_local;

            long long my_tot_L = 0;
            double my_time = 0.0;
            LabelGenTimings my_timings;

            while (true) {
                int part_id = get_next_partition(Distributed_Graph_Num);
                if (part_id < 0) break;

                auto begin = std::chrono::high_resolution_clock::now();
                long long current_delta = 0;
                gpu_label_gen(my_csr, my_info, L_local + my_tot_L,
                              current_delta, graph_pool.graph_group[part_id],
                              part_id, sort_time_record, my_timings);
                my_tot_L += current_delta;
                auto end = std::chrono::high_resolution_clock::now();
                my_time += std::chrono::duration<double>(end - begin).count();
            }

            gpu_L_totals[g] = my_tot_L;
            gpu_gen_timings[g] = my_timings;
            gpu_gen_times[g] = my_time;
        });
    }
    for (auto& t : gen_threads) t.join();

    // 合并所有GPU的生成结果到 L_hybrid
    long long tot_L = 0;
    for (int g = 0; g < num_gpus; g++) tot_L += gpu_L_totals[g];
    printf("Total labels generated: %lld\n", tot_L);

    auto t_process_start = std::chrono::high_resolution_clock::now();
    printf("Start batch converting %lld labels to L_hybrid.\n", tot_L);

    // 将GPU结果转为L_hybrid
    long long offset = 0;
    for (int g = 0; g < num_gpus; g++) {
        #pragma omp parallel for schedule(dynamic, 1024)
        for (long long j = 0; j < gpu_L_totals[g]; ++j) {
            long long T = gpu_L_buffers[g][j];
            int to_v = get_to_vertex(T);
            L_hybrid[csr_graph.ARRAY_source[to_v]].push_back(
                {get_hub_vertex(T), csr_graph.OUTs_Edges[to_v],
                 get_hop(T), get_distance(T)});
        }
        cudaFreeHost(gpu_L_buffers[g]);
        gpu_L_buffers[g] = nullptr;
    }

    auto t_process_end = std::chrono::high_resolution_clock::now();
    // ... timing 输出 ...

    // 释放生成阶段的GPU资源
    for (int g = 0; g < num_gpus; g++) {
        cudaSetDevice(gpu_ids[g]);
        info_gpu_vec[g]->destroy_L_cuda();
    }

    // ... 排序 L_hybrid ...

    // ===== 清理阶段：多GPU并行标签清理 =====
    // 第一个指定GPU（gpu_ids[0]）分配共享数据
    int primary_dev = gpu_ids[0];
    cudaSetDevice(primary_dev);
    info_gpu_vec[0]->init_clean_shared(V, L_hybrid, csr_graph_vec[0],
                                        label_before_clean, edge_id, G_max);

    // 每个GPU初始化本地数据，并设置共享数据的远程访问
    for (int g = 0; g < num_gpus; g++) {
        int dev_id = gpu_ids[g];
        cudaSetDevice(dev_id);
        info_gpu_vec[g]->init_clean_local();

        if (g != 0) {
            // 让主GPU上分配的共享数据可被当前GPU访问
            cudaMemAdvise(info_gpu_vec[0]->L_clean,
                          (label_before_clean + 1) * sizeof(long long),
                          cudaMemAdviseSetAccessedBy, dev_id);
            cudaMemAdvise(info_gpu_vec[0]->L_start,
                          (V + 1) * sizeof(long long),
                          cudaMemAdviseSetAccessedBy, dev_id);
            cudaMemAdvise(info_gpu_vec[0]->L_end,
                          (V + 1) * sizeof(long long),
                          cudaMemAdviseSetAccessedBy, dev_id);
            cudaMemAdvise(info_gpu_vec[0]->mark,
                          (label_before_clean + 1) * sizeof(char),
                          cudaMemAdviseSetAccessedBy, dev_id);

            // 将共享数据指针复制到当前GPU的 info 结构体中
            info_gpu_vec[g]->L_clean = info_gpu_vec[0]->L_clean;
            info_gpu_vec[g]->L_start = info_gpu_vec[0]->L_start;
            info_gpu_vec[g]->L_end = info_gpu_vec[0]->L_end;
            info_gpu_vec[g]->mark = info_gpu_vec[0]->mark;
        }
    }

    // 阶段1：并行剪枝
    next_partition_idx = 0;
    std::vector<std::thread> clean_threads;
    for (int g = 0; g < num_gpus; g++) {
        clean_threads.emplace_back(gpu_clean_prune_worker, g, V,
                                   (long long)G_max, info_gpu_vec[0],
                                   std::ref(total_timings));
    }
    for (auto& t : clean_threads) t.join();

    // 阶段2：串行压缩（在主GPU上执行）
    long long last_pos = 1;
    gpu_clean_compress(info_gpu_vec[0], csr_graph_vec[0], V, G_max,
                       last_pos, total_timings);

    // ... 从 L_hybrid 中提取清理后的结果 ...

    // 释放清理阶段资源
    for (int g = 0; g < num_gpus; g++) {
        cudaSetDevice(gpu_ids[g]);
        info_gpu_vec[g]->destroy_clean_local();
    }
    cudaSetDevice(primary_dev);
    info_gpu_vec[0]->destroy_clean_shared();

    // ... 其余后处理和输出逻辑 ...

    // 注意：移除原有的 cudaFreeHost(L) 调用（约202行和385行）
    // L 已通过 gpu_L_buffers 逐个释放，无需再次释放
}
```

> **命令行参数说明**：
> - 原有参数保持不变：`<data_path> <hop_cst> <output_path> <G_max> <cpu_type>`
> - 新增参数 `<gpu_ids>`：逗号分隔的GPU设备ID列表
> - 示例：`./program data.txt 5 output.txt 400 0 0,2,3` 表示使用GPU 0、2、3
> - 示例：`./program data.txt 5 output.txt 400 0 1` 表示仅使用GPU 1
> - 示例：`./program data.txt 5 output.txt 400 0 0,1,2,3` 表示使用GPU 0-3
>
> **关键区别**：`g` 是线程索引（0, 1, 2, ...），`gpu_ids[g]` 是实际的GPU设备ID。例如 `gpu_ids = {0, 2, 3}` 时，线程0使用GPU 0，线程1使用GPU 2，线程2使用GPU 3。所有 `cudaSetDevice`、`copy_to_device`、`init` 等调用都使用 `gpu_ids[g]` 作为实际设备ID。

---

## 五、资源需求评估

### 4.1 显存需求（4 GPU配置）

每个GPU需要独立分配以下资源：

| 数据结构 | 单GPU显存 | 4 GPU总计 | 所属阶段 |
|---------|----------|----------|------|
| `has` | ~11.9 GB | ~47.6 GB | 生成 |
| `das` | ~11.9 GB | ~47.6 GB | 生成 |
| `T` (40%剩余显存) | ~22 GB (80GB GPU) | ~88 GB | 生成 |
| `T_offset_begin/end` | ~960 MB (V=10M) | ~3.8 GB | 生成 |
| `flag` | ~2.8 GB (80GB GPU) | ~11.2 GB | 生成 |
| `D_sort_temp` | ~19.3 GB (80GB GPU) | ~77.2 GB | 生成 |
| CSR图数据 | ~数百MB | ~数GB | 生成+清理 |
| `has_clean` | ~22.4 GB | ~89.6 GB | 清理 |
| `sort_temp` | ~6.0 GB | ~24.0 GB | 清理 |
| `L_clean` (共享) | ~数十GB | ~数十GB (仅1份) | 清理 |
| `L_start/L_end` (共享) | ~数十GB | ~数十GB (仅1份) | 清理 |
| `mark` (共享) | ~数GB | ~数GB (仅1份) | 清理 |

> **注意**：清理阶段的 `L_clean`、`L_start`、`L_end`、`mark` 为共享数据，仅在主GPU（`gpu_ids[0]`）上分配一份。

### 4.2 不同GPU型号兼容性

| GPU型号 | 显存 | 生成阶段可行性 | 清理阶段可行性 | 建议 |
|---------|------|--------------|--------------|------|
| A100 40GB | 40 GB | ? `has`+`das` 需 23.8GB，仅剩16.2GB，无法容纳 `T`+`D_sort_temp` | ? `has_clean` 需 22.4GB，空间不足 | 需降低哈希表大小或使用更大显存GPU |
| A100 80GB | 80 GB | ? 总需求约69GB，可行 | ? 总需求约30GB+，可行 | 推荐 |
| H100 80GB | 80 GB | ? 同A100 80GB | ? 同A100 80GB | 推荐 |
| H200 141GB | 141 GB | ? 充裕 | ? 充裕 | 最佳 |

### 4.3 优化策略

**方案A：统一内存 + 数据位置提示（推荐，适用于 80GB+ GPU）**

- 继续使用 `cudaMallocManaged` 分配所有GPU内存
- 使用 `cudaMemAdviseSetPreferredLocation` 将数据绑定到对应GPU
- 使用 `cudaMemPrefetchAsync` 预取数据到对应GPU
- 优点：实现简单，无需修改数据结构

```cpp
cudaMallocManaged(&has, TABLE_SIZE * sizeof(long long));
cudaMemAdvise(has, TABLE_SIZE * sizeof(long long), cudaMemAdviseSetPreferredLocation, device_id);
cudaMemPrefetchAsync(has, TABLE_SIZE * sizeof(long long), device_id, 0);
```

**方案B：降低哈希表大小（适用于 40GB GPU）**

- 需要评估降低哈希表大小对正确性的影响
- 可将 `TABLE_SIZE` 减半至 799,999,983，约减少50%显存
- `TABLE_SIZE_CLEAN` 也可相应降低至 1,499,736,851
- **风险**：哈希冲突率上升，可能影响结果正确性

**方案C：流水线式GPU处理（适用于显存不足的情况）**

- 将生成阶段拆分为多个批次，每个批次只使用部分GPU
- 例如：批次0使用GPU 0和GPU 1，批次1使用GPU 2和GPU 3
- GPU 0 完成后释放资源，GPU 1 继续处理，GPU 2 接管下一批
- 缺点：无法充分利用所有GPU资源

### 4.4 推荐方案

推荐使用 80GB+ 显存的GPU，如 A100-80GB / H100 / H200，并采用**方案A**：
- 生成阶段：`has` + `das` ≈ 23.8 GB，`T` + `T_offset` + `flag` + `D_sort_temp` ≈ 45 GB，CSR ≈ 数百MB，总计约 69 GB/GPU，80GB GPU 可以满足
- 清理阶段：`has_clean` ≈ 22.4 GB，`sort_temp` ≈ 6.0 GB，其他约 ~数GB，总计约 30-35 GB/GPU，80GB GPU 充裕

若只有 40GB GPU，建议采用**方案B**降低哈希表大小，或采用**方案C**流水线式处理，但需要仔细评估正确性影响。

---

## 六、标签清理的多GPU并行化

### 5.1 问题分析

当前 `clean_label_prune` kernel 的核心逻辑如下：

```cpp
long long begin = L_start[hub_vertex];  // hub_vertex 可能跨范围访问
long long end = L_end[hub_vertex];
for (long long i = begin; i < end; i++) {
    long long label_L = L[i];  // 读取其他范围的 L_clean 数据，存在依赖
    ...
}
```

同时，`clean_update_labels` kernel 会修改 `L_start/L_end`：

```cpp
if (cur_src != get_source(L[tid - 1], source)) {
    L_start[cur_src] = pos;  // 修改指针值
}
if (cur_src != get_source(L[tid + 1], source)) {
    L_end[cur_src] = pos + 1;  // 修改指针值
}
```

### 5.2 两阶段并行剪枝 + 串行压缩

> **核心挑战**：多GPU并行执行剪枝时，不能修改 `L_start/L_end` 指针和 `last_pos` 索引，否则会产生数据竞争。

```
阶段1：并行剪枝
┌──────────────────────────────────────────────────────────────────┐
│ gpu_ids[0]: clean_hash_init → clean_label_prune → clean_hash_clear│
│   处理顶点范围 [0, G_max)                                        │
│   修改 mark[0..G_max对应范围)                                    │
│   使用独立的 has_clean[0]                                       │
├──────────────────────────────────────────────────────────────────┤
│ gpu_ids[1]: clean_hash_init → clean_label_prune → clean_hash_clear│
│   处理顶点范围 [G_max, 2*G_max)                                  │
│   修改 mark[G_max对应范围..2*G_max对应范围)                      │
│   使用独立的 has_clean[1]                                       │
├──────────────────────────────────────────────────────────────────┤
│ ...                                                              │
└──────────────────────────────────────────────────────────────────┘
         ↓ 阶段1完成                ↓ 阶段2
         ↓                          ↓
┌──────────────────────────────────────────────────────────┐
│    L_clean / L_start / L_end (共享数据，仅主GPU分配)     │
└──────────────────────────────────────────────────────────┘

阶段2：串行压缩（在主GPU上执行）
┌──────────────────────────────────────────────────────────────────┐
│ for each vertex range:                                           │
│   DeviceSelect::Flagged (根据 mark 筛选)                         │
│   clean_update_labels (更新 L_start/L_end)                       │
└──────────────────────────────────────────────────────────────────┘
```

关键点：
1. `L_clean`、`L_start`、`L_end`、`mark` 在主GPU（`gpu_ids[0]`）上分配，通过统一内存共享
2. 其他GPU通过 `cudaMemAdviseSetAccessedBy` 获取远程访问权限
3. 其他GPU独立拥有 `has_clean`、`sort_temp`
4. 阶段1中各GPU并行剪枝，只修改 `mark` 数组（写入`mark[L_clean_start + tid]`，各GPU写入不重叠）
5. 阶段1中`L_clean`、`L_start`、`L_end` 为只读访问，不修改
6. 阶段2在主GPU（`gpu_ids[0]`）上串行执行，统一修改 `L_start/L_end` 指针

### 5.3 共享数据访问机制

在主GPU（`gpu_ids[0]`）上分配共享数据后，将 `hop_constrained_case_info_gpu` 中的 `L_clean`、`L_start`、`L_end`、`mark` 指针复制到其他GPU的 info 结构体中。

```cpp
// 在调用 init_clean_shared 和 init_clean_local 之后
for (int g = 1; g < (int)gpu_ids.size(); g++) {
    info_gpu_vec[g]->L_clean = info_gpu_vec[0]->L_clean;
    info_gpu_vec[g]->L_start = info_gpu_vec[0]->L_start;
    info_gpu_vec[g]->L_end = info_gpu_vec[0]->L_end;
    info_gpu_vec[g]->mark = info_gpu_vec[0]->mark;
}
```

> **说明**：由于使用统一内存，通过`cudaMemAdviseSetAccessedBy` 设置后，其他GPU可以直接通过指针访问主GPU上分配的数据，无需显式数据传输。注意主GPU不一定是 GPU 0，而是用户通过 `argv` 指定的第一个GPU（`gpu_ids[0]`）。

---

## 七、实施阶段与优先级

### Phase 1：单GPU多设备支持（生成阶段）

1. 修改 `types.h`，为 `Executive_Core` 添加 `device_id` 字段
2. 修改 `gpu_label_manager.cuh`：
   - 添加 `device_id` 字段
   - 所有分配/释放操作添加 `cudaSetDevice`
   - `init()` 添加 `dev_id` 参数
3. 修改 `csr_graph.hpp`：
   - 添加 `copy_to_device` 方法
   - 修改 `destroy_csr_graph` 添加空指针检查
4. 修改 `gpu_label_gen.cu`，函数开头添加 `cudaSetDevice(info->device_id)`
5. 修改 `gpu_warmup.cuh`，添加 `device_id` 参数
6. 修改 `main.cu`：
   - 从 `argv[6]` 解析用户指定的GPU ID列表（逗号分隔格式，如 `"0,2,3"`）
   - 验证指定GPU的可用性（`cudaGetDeviceCount` + ID范围检查）
   - 实现多GPU资源初始化和并行调度，使用 `gpu_ids[g]` 作为实际设备ID
7. 修复 `main.cu` 中 `cudaFreeHost(L)` 的 double free 问题

### Phase 2：清理阶段多GPU并行

8. 拆分 `init_clean` 为 `init_clean_shared` + `init_clean_local`
9. 实现 `gpu_clean_prune_worker`，并行剪枝逻辑
10. 实现 `gpu_clean_compress`，串行压缩逻辑
11. 添加 `destroy_clean_local` + `destroy_clean_shared` 释放逻辑
12. 修复 `gpu_label_clean` 中 `d_num_selected` 的内存泄漏

### Phase 3：性能优化

13. 添加 `cudaMemAdvise` 数据位置提示
14. 添加 `cudaMemPrefetchAsync` 预取逻辑
15. 实现动态负载均衡策略
16. 添加多GPU性能统计（per-GPU timing）
17. 添加多GPU错误处理和恢复机制
18. 优化生成阶段的标签合并，减少 `L_start/L_end` 指针更新开销

---

## 八、潜在风险与注意事项

1. **统一内存页面迁移开销**：多GPU通过统一内存访问数据时，页面迁移粒度为 4KB（10次访问/页 = 4KB），频繁迁移会降低性能。使用 `cudaMemAdvise` 和 `cudaMemPrefetchAsync` 可以减少迁移开销。对于 `L_clean` 的跨GPU访问，建议将 `L_clean` 预取到访问GPU。

2. **哈希表大小限制**：每个GPU独立分配`has`/`das` 哈希表，总显存需求随GPU数量线性增长。对于 80GB+ 显存的GPU，方案A可行；否则需考虑方案B降低哈希表大小。

3. **清理阶段 `L_clean` 的跨GPU访问**：多GPU并行访问 `L_clean` 时，由于 `clean_label_prune` 需要读取其他顶点的标签，存在跨GPU页面迁移：
   - 使用 `cudaMemAdviseSetReadMostly` 将 `L_clean` 标记为只读
   - 或使用 `cudaMemPrefetchAsync` 将 `L_clean` 预取到各GPU

4. **错误处理**：多GPU环境下需要为每个GPU添加 `CHECK_CUDA_KERNEL()` 错误检查，建议使用 `std::exception_ptr` 跨线程传播错误。

5. **`cudaMallocHost` 分配 `L` 缓冲区**：每个GPU独立的 `L_local` 缓冲区需要 80GB，4 GPU 总共需要 320GB 的 host 内存。如果 host 内存不足，需要考虑：
   - 降低缓冲区大小（分批处理）
   - 使用 `mmap` 映射大文件作为缓冲区
   - 分批处理 `L` 缓冲区 + 定期合并到最终数据结构

6. **CUB临时存储**：CUB的 `DeviceRadixSort` 和 `DeviceSelect` 需要临时存储空间，对应 `D_sort_temp`。每个GPU独立分配临时存储，确保CUB操作在正确的GPU上执行。

7. **`gpu_label_gen` 中的 `cudaMemcpyAsync`**：当前使用 `cudaMemcpyAsync(L + last_pos, T + last_pos, ...)` 将数据从 GPU 拷贝到 host 端 `L` 缓冲区。多GPU环境下，每个GPU的 `L_local` 为 pinned memory，`cudaMemcpyAsync` 可以正确执行异步拷贝。

8. **`gpu_label_clean` 中 `d_num_selected` 的内存泄漏**：当前 `gpu_label_clean` 中 `cudaMallocManaged(&d_num_selected, ...)` 的临时分配未在使用后释放，导致内存泄漏。应在使用后立即 `cudaFree(d_num_selected)`。

9. **`source` 数组的跨GPU访问**：`gpu_label_clean` 中 `clean_label_prune` kernel 需要 `source[get_to_vertex(label_clean)]`，而 `source` 数组在每个GPU上独立分配。`source` 数组已在 `copy_to_device` 中拷贝到每个GPU，而 `L_clean` 中的 `to_vertex` 索引对应CSR图中的边，各GPU的 `source` 数组内容一致，因此跨GPU访问 `source` 不存在问题。

---

## 九、预期加速比

假设 N 个GPU处理 M 个图分区（M >> N）：

- **生成阶段加速比**：接近线性 ≈ N（任务间无依赖，负载均衡良好）
- **清理阶段加速比**：
  - 阶段1（并行剪枝）：加速比 ≈ N
  - 阶段2（串行压缩）：无加速
  - 综合加速比取决于阶段1和阶段2的耗时比，通常约 0.5N ~ 0.8N
- **整体加速比**：受限于清理阶段，通常约 0.7N ~ 0.95N

影响加速比的因素：
- 哈希表大小导致的显存限制
- 统一内存页面迁移开销（特别是 `L_clean` 的跨GPU访问）
- PCIe带宽限制（生成阶段的数据传输）
- 负载不均衡

---

## 十、已知需要修复的Bug

以下Bug在多GPU改造前就需要修复，否则多GPU版本无法正确运行。

| # | 文件 | 行号 | Bug描述 | 修复方案 |
|---|------|------|---------|---------|
| 1 | `main.cu` | 202, 385 | `cudaFreeHost(L)` 释放了生成阶段的缓冲区，导致 double free | 移除385行的调用 |
| 2 | `gpu_label_clean.cu` | 203 | `cudaMallocManaged(&d_num_selected, ...)` 未在使用后释放 | 添加 `cudaFree(d_num_selected)` |
| 3 | `csr_graph.hpp` | 33-37 | `destroy_csr_graph` 中 `cudaFree(out_edge)` 等可能释放未分配的指针，如 `all_pointer` 和 `source` 等 | 添加空指针检查 |
| 4 | `csr_graph.hpp` | 33-37 | `destroy_csr_graph` 释放后未重置为 nullptr | 添加 nullptr 赋值 |
