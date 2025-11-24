# NVMe Benchmark Guide

## Quick Start

### Prerequisites

Install dependencies:

**Ubuntu:**
```bash
sudo apt update && sudo apt install -y fio nvme-cli smartmontools jq
```

**Arch Linux:**
```bash
sudo pacman -S fio nvme-cli smartmontools jq
```

### Make Script Executable

```bash
chmod +x benchmark-nvme.sh
```

## Your Specific Setup

### Ubuntu Server (2 Identical NVMe Drives)

Since your 2nd drive has potentially more aggressive performance settings, here's how to compare them:

#### 1. First, inspect the performance settings of both drives:

```bash
# View settings for both drives (no benchmark)
sudo ./benchmark-nvme.sh -i -d nvme0n1,nvme1n1
```

This will show you the key performance parameters:
- I/O Scheduler (none/mq-deadline/kyber)
- nr_requests (queue depth)
- read_ahead_kb
- Power management settings
- Write cache settings

#### 2. Benchmark the 2nd drive (with aggressive settings):

```bash
# Benchmark just the 2nd drive
sudo ./benchmark-nvme.sh -d nvme1n1

# Or with custom settings for faster results
sudo ./benchmark-nvme.sh -d nvme1n1 -s 2G -t 30
```

#### 3. Then benchmark the 1st drive to compare:

```bash
sudo ./benchmark-nvme.sh -d nvme0n1
```

#### 4. Compare results:

```bash
sudo ./benchmark-nvme.sh -c
```

### Arch Linux Servers (2nd Drive 85% Full)

When you're ready to benchmark the Arch servers:

#### Important: Drive utilization affects performance

NVMe drives can show different performance based on how full they are due to:
- Garbage collection overhead
- Over-provisioning reduction
- Write amplification

#### Recommended approach for 85% full drive:

```bash
# First check both drives
sudo ./benchmark-nvme.sh -i -d nvme0n1,nvme1n1

# Benchmark both to compare (fuller drive may be slower)
sudo ./benchmark-nvme.sh -d nvme0n1,nvme1n1 -s 1G -t 30
```

Use smaller test size (`-s 1G`) to:
- Avoid filling the 85% drive further
- Reduce benchmark time
- Still get meaningful results

## Understanding Performance Settings

### Key Parameters to Compare

| Setting | Conservative | Aggressive |
|---------|-------------|------------|
| I/O Scheduler | mq-deadline | none |
| nr_requests | 64 | 256+ |
| read_ahead_kb | 128 | 256-2048 |
| Power Management | Enabled | Disabled |
| Write Cache | Standard | Enabled |

### Common Aggressive Settings

To apply aggressive settings to a drive (for reference):

```bash
# Set scheduler to none (lowest latency for NVMe)
echo none | sudo tee /sys/block/nvme1n1/queue/scheduler

# Increase queue depth
echo 256 | sudo tee /sys/block/nvme1n1/queue/nr_requests

# Increase read-ahead
echo 2048 | sudo tee /sys/block/nvme1n1/queue/read_ahead_kb

# Disable adding to entropy pool
echo 0 | sudo tee /sys/block/nvme1n1/queue/add_random
```

## Benchmark Metrics Explained

### Sequential Performance (MB/s)
- **Sequential Read/Write**: Large file transfers
- Higher is better
- Typical NVMe: 2000-7000 MB/s

### Random IOPS
- **Random 4K Read/Write**: Database, VM workloads
- Higher is better
- Typical NVMe: 100K-1M IOPS

### Latency (QD1)
- **Queue Depth 1**: Single operation latency
- Lower is better
- Typical NVMe: 50-200 µs

### Mixed Workload
- **70/30 R/W**: Real-world mix
- Reflects actual application behavior

## Full Usage Reference

```bash
./benchmark-nvme.sh [OPTIONS]

Options:
  -d, --drive DRIVE     Drives to benchmark (comma-separated)
  -s, --size SIZE       Test file size (default: 4G)
  -t, --time SECONDS    Runtime per test (default: 60)
  -o, --output DIR      Output directory (default: ./benchmark_results)
  -i, --info            Show info only, no benchmark
  -c, --compare         Compare existing results
  -h, --help            Show help

Examples:
  ./benchmark-nvme.sh                      # Interactive mode
  ./benchmark-nvme.sh -d nvme1n1           # Specific drive
  ./benchmark-nvme.sh -d nvme0n1,nvme1n1   # Multiple drives
  ./benchmark-nvme.sh -i -d nvme1n1        # Info only
  ./benchmark-nvme.sh -s 1G -t 30          # Quick benchmark
```

## Expected Results Comparison

After running benchmarks, you'll see output like:

```
=== Performance Comparison ===

Metric                        nvme0n1             nvme1n1
--------------------------    -----------------   -----------------
Sequential Read               3200.5 MB/s         3450.2 MB/s
Sequential Write              2800.3 MB/s         3100.8 MB/s
Random Read 4K (QD32)         450000 IOPS         520000 IOPS
Random Write 4K (QD32)        380000 IOPS         420000 IOPS
```

The drive with aggressive settings (nvme1n1) should show:
- 5-15% better sequential speeds
- 10-20% better random IOPS
- Lower latency at QD1
