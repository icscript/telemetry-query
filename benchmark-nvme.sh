#!/bin/bash

# NVMe Drive Benchmark Script
# Benchmarks NVMe drives using fio and displays performance settings
# Works on Ubuntu and Arch Linux

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
TEST_SIZE="4G"
RUNTIME="60"
OUTPUT_DIR="./benchmark_results"
SELECTED_DRIVES=""
RANDREAD_ONLY=false

print_header() {
    echo -e "\n${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}\n"
}

print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_dependencies() {
    print_header "Checking Dependencies"

    local missing_deps=()

    for cmd in fio nvme lsblk smartctl bc jq; do
        if ! command -v $cmd &> /dev/null; then
            missing_deps+=($cmd)
        else
            print_info "$cmd found: $(which $cmd)"
        fi
    done

    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        echo "Install on Ubuntu:"
        echo "  sudo apt update && sudo apt install -y fio nvme-cli smartmontools bc jq"
        echo ""
        echo "Install on Arch Linux:"
        echo "  sudo pacman -S fio nvme-cli smartmontools bc jq"
        echo ""
        exit 1
    fi

    print_info "All dependencies satisfied"
}

detect_nvme_drives() {
    print_header "Detecting NVMe Drives"

    # Get list of NVMe devices
    NVME_DRIVES=($(lsblk -d -n -o NAME | grep "^nvme"))

    if [ ${#NVME_DRIVES[@]} -eq 0 ]; then
        print_error "No NVMe drives detected"
        exit 1
    fi

    print_info "Found ${#NVME_DRIVES[@]} NVMe drive(s):"
    echo ""

    for i in "${!NVME_DRIVES[@]}"; do
        local drive="${NVME_DRIVES[$i]}"
        local size=$(lsblk -d -n -o SIZE /dev/$drive)
        local model=$(lsblk -d -n -o MODEL /dev/$drive | sed 's/^ *//;s/ *$//')
        echo "  [$((i+1))] /dev/$drive - $model ($size)"
    done
    echo ""
}

show_drive_info() {
    local drive=$1

    print_header "Drive Information: /dev/$drive"

    # Basic info
    echo -e "${YELLOW}=== Basic Information ===${NC}"
    lsblk -o NAME,SIZE,MODEL,SERIAL,ROTA,DISC-MAX /dev/$drive
    echo ""

    # NVMe specific info
    echo -e "${YELLOW}=== NVMe Controller Info ===${NC}"
    sudo nvme id-ctrl /dev/$drive -H 2>/dev/null | head -50 || echo "Could not get controller info"
    echo ""

    # SMART info
    echo -e "${YELLOW}=== SMART Health Information ===${NC}"
    sudo nvme smart-log /dev/$drive 2>/dev/null || echo "Could not get SMART info"
    echo ""
}

show_performance_settings() {
    local drive=$1
    local base_drive=$(echo $drive | sed 's/p[0-9]*$//' | sed 's/[0-9]*$//')

    print_header "Performance Settings: /dev/$drive"

    # I/O Scheduler
    echo -e "${YELLOW}=== I/O Scheduler ===${NC}"
    local scheduler_file="/sys/block/$drive/queue/scheduler"
    if [ -f "$scheduler_file" ]; then
        echo "Current scheduler: $(cat $scheduler_file)"
    else
        echo "Scheduler info not available"
    fi
    echo ""

    # Queue depth
    echo -e "${YELLOW}=== Queue Settings ===${NC}"
    local queue_path="/sys/block/$drive/queue"
    if [ -d "$queue_path" ]; then
        echo "nr_requests: $(cat $queue_path/nr_requests 2>/dev/null || echo 'N/A')"
        echo "read_ahead_kb: $(cat $queue_path/read_ahead_kb 2>/dev/null || echo 'N/A')"
        echo "max_sectors_kb: $(cat $queue_path/max_sectors_kb 2>/dev/null || echo 'N/A')"
        echo "rotational: $(cat $queue_path/rotational 2>/dev/null || echo 'N/A')"
        echo "hw_sector_size: $(cat $queue_path/hw_sector_size 2>/dev/null || echo 'N/A')"
        echo "logical_block_size: $(cat $queue_path/logical_block_size 2>/dev/null || echo 'N/A')"
        echo "physical_block_size: $(cat $queue_path/physical_block_size 2>/dev/null || echo 'N/A')"
        echo "nomerges: $(cat $queue_path/nomerges 2>/dev/null || echo 'N/A')"
        echo "add_random: $(cat $queue_path/add_random 2>/dev/null || echo 'N/A')"
        echo "iostats: $(cat $queue_path/iostats 2>/dev/null || echo 'N/A')"
    else
        echo "Queue settings not available"
    fi
    echo ""

    # Power management
    echo -e "${YELLOW}=== Power Management ===${NC}"
    sudo nvme get-feature /dev/$drive -f 0x02 -H 2>/dev/null || echo "Power management info not available"
    echo ""

    # NVMe features
    echo -e "${YELLOW}=== NVMe Features ===${NC}"
    echo "Checking write cache..."
    sudo nvme get-feature /dev/$drive -f 0x06 2>/dev/null || echo "Volatile write cache info not available"
    echo ""
}

get_mount_point() {
    local drive=$1

    # Check if any partition is mounted
    local mount_point=$(lsblk -n -o MOUNTPOINT /dev/${drive}* 2>/dev/null | grep -v "^$" | head -1)

    if [ -n "$mount_point" ]; then
        echo "$mount_point"
    else
        echo ""
    fi
}

run_fio_benchmark() {
    local drive=$1
    local test_path=$2
    local result_file=$3

    print_header "Running FIO Benchmark on /dev/$drive"
    print_info "Test path: $test_path"
    print_info "Test size: $TEST_SIZE"
    print_info "Runtime per test: ${RUNTIME}s"
    echo ""

    # Create test directory if needed
    local test_dir="$test_path/fio_benchmark_test"
    mkdir -p "$test_dir"

    # Results array
    declare -A results

    # Test 1: Sequential Read
    echo -e "${YELLOW}[1/10] Sequential Read (1M block)${NC}"
    local seq_read=$(fio --name=seq_read --directory=$test_dir --rw=read --bs=1M --size=$TEST_SIZE \
        --numjobs=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.bw_bytes / 1048576' 2>/dev/null || echo "0")
    echo "  Bandwidth: ${seq_read} MB/s"
    results["seq_read"]=$seq_read

    # Test 2: Sequential Write
    echo -e "${YELLOW}[2/10] Sequential Write (1M block)${NC}"
    local seq_write=$(fio --name=seq_write --directory=$test_dir --rw=write --bs=1M --size=$TEST_SIZE \
        --numjobs=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].write.bw_bytes / 1048576' 2>/dev/null || echo "0")
    echo "  Bandwidth: ${seq_write} MB/s"
    results["seq_write"]=$seq_write

    # Test 3: Random Read 4K
    echo -e "${YELLOW}[3/10] Random Read 4K (QD32)${NC}"
    local rand_read_4k=$(fio --name=rand_read_4k --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=32 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_4k}"
    results["rand_read_4k"]=$rand_read_4k

    # Test 4: Random Write 4K
    echo -e "${YELLOW}[4/10] Random Write 4K (QD32)${NC}"
    local rand_write_4k=$(fio --name=rand_write_4k --directory=$test_dir --rw=randwrite --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=32 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].write.iops' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_write_4k}"
    results["rand_write_4k"]=$rand_write_4k

    # Test 5: Random Read 4K (QD256) - Manufacturer spec comparison
    echo -e "${YELLOW}[5/10] Random Read 4K (QD256) - MFG Spec Comparison${NC}"
    echo "  (Micron spec: 800,000 IOPS at QD256)"
    local rand_read_qd256=$(fio --name=rand_read_qd256 --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=256 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    local pct_of_spec=$(echo "scale=1; $rand_read_qd256 / 8000" | bc 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_qd256} (${pct_of_spec}% of spec)"
    results["rand_read_qd256"]=$rand_read_qd256

    # Test 6: Random Write 4K (QD256)
    echo -e "${YELLOW}[6/10] Random Write 4K (QD256)${NC}"
    local rand_write_qd256=$(fio --name=rand_write_qd256 --directory=$test_dir --rw=randwrite --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=256 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].write.iops' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_write_qd256}"
    results["rand_write_qd256"]=$rand_write_qd256

    # Test 7: Random Read 4K (QD1)
    echo -e "${YELLOW}[7/10] Random Read 4K (QD1) - Latency test${NC}"
    local rand_read_qd1=$(fio --name=rand_read_qd1 --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=1 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null)
    local rand_read_qd1_iops=$(echo "$rand_read_qd1" | jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    local rand_read_qd1_lat=$(echo "$rand_read_qd1" | jq -r '.jobs[0].read.lat_ns.mean / 1000' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_qd1_iops}, Latency: ${rand_read_qd1_lat} µs"
    results["rand_read_qd1_iops"]=$rand_read_qd1_iops
    results["rand_read_qd1_lat"]=$rand_read_qd1_lat

    # Test 8: Random Write 4K (QD1)
    echo -e "${YELLOW}[8/10] Random Write 4K (QD1) - Latency test${NC}"
    local rand_write_qd1=$(fio --name=rand_write_qd1 --directory=$test_dir --rw=randwrite --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=1 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null)
    local rand_write_qd1_iops=$(echo "$rand_write_qd1" | jq -r '.jobs[0].write.iops' 2>/dev/null || echo "0")
    local rand_write_qd1_lat=$(echo "$rand_write_qd1" | jq -r '.jobs[0].write.lat_ns.mean / 1000' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_write_qd1_iops}, Latency: ${rand_write_qd1_lat} µs"
    results["rand_write_qd1_iops"]=$rand_write_qd1_iops
    results["rand_write_qd1_lat"]=$rand_write_qd1_lat

    # Test 9: Mixed Random R/W (70/30)
    echo -e "${YELLOW}[9/10] Mixed Random R/W 4K (70/30, QD32)${NC}"
    local mixed_rw=$(fio --name=mixed_rw --directory=$test_dir --rw=randrw --rwmixread=70 --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=32 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null)
    local mixed_read_iops=$(echo "$mixed_rw" | jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    local mixed_write_iops=$(echo "$mixed_rw" | jq -r '.jobs[0].write.iops' 2>/dev/null || echo "0")
    echo "  Read IOPS: ${mixed_read_iops}, Write IOPS: ${mixed_write_iops}"
    results["mixed_read_iops"]=$mixed_read_iops
    results["mixed_write_iops"]=$mixed_write_iops

    # Test 10: Multi-threaded Sequential
    echo -e "${YELLOW}[10/10] Multi-threaded Sequential Read (4 jobs)${NC}"
    local mt_seq_read=$(fio --name=mt_seq_read --directory=$test_dir --rw=read --bs=1M --size=$TEST_SIZE \
        --numjobs=4 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.bw_bytes / 1048576' 2>/dev/null || echo "0")
    echo "  Bandwidth: ${mt_seq_read} MB/s"
    results["mt_seq_read"]=$mt_seq_read

    # Cleanup test files
    rm -rf "$test_dir"

    # Save results to file
    {
        echo "Drive: /dev/$drive"
        echo "Test Date: $(date)"
        echo "Test Size: $TEST_SIZE"
        echo "Runtime: ${RUNTIME}s per test"
        echo ""
        echo "Results:"
        echo "  Sequential Read: ${results[seq_read]} MB/s"
        echo "  Sequential Write: ${results[seq_write]} MB/s"
        echo "  Random Read 4K (QD32): ${results[rand_read_4k]} IOPS"
        echo "  Random Write 4K (QD32): ${results[rand_write_4k]} IOPS"
        echo "  Random Read 4K (QD256): ${results[rand_read_qd256]} IOPS (MFG spec: 800,000)"
        echo "  Random Write 4K (QD256): ${results[rand_write_qd256]} IOPS"
        echo "  Random Read 4K (QD1): ${results[rand_read_qd1_iops]} IOPS, ${results[rand_read_qd1_lat]} µs"
        echo "  Random Write 4K (QD1): ${results[rand_write_qd1_iops]} IOPS, ${results[rand_write_qd1_lat]} µs"
        echo "  Mixed R/W 70/30 (QD32): ${results[mixed_read_iops]} / ${results[mixed_write_iops]} IOPS"
        echo "  Multi-threaded Seq Read (4 jobs): ${results[mt_seq_read]} MB/s"
    } > "$result_file"

    print_info "Results saved to: $result_file"
    echo ""
}

compare_results() {
    print_header "Benchmark Comparison"

    local result_files=("$OUTPUT_DIR"/*.txt)

    if [ ${#result_files[@]} -lt 2 ]; then
        print_warn "Need at least 2 benchmark results to compare"
        return
    fi

    echo -e "${YELLOW}Results found:${NC}"
    for file in "${result_files[@]}"; do
        echo "  - $(basename $file)"
    done
    echo ""

    # Create comparison table
    echo -e "${YELLOW}=== Performance Comparison ===${NC}"
    echo ""

    printf "%-30s" "Metric"
    for file in "${result_files[@]}"; do
        printf "%-20s" "$(basename $file .txt)"
    done
    echo ""

    printf "%-30s" "------------------------------"
    for file in "${result_files[@]}"; do
        printf "%-20s" "-------------------"
    done
    echo ""

    # Extract and compare each metric
    for metric in "Sequential Read" "Sequential Write" "Random Read 4K (QD32)" "Random Write 4K (QD32)"; do
        printf "%-30s" "$metric"
        for file in "${result_files[@]}"; do
            local value=$(grep "$metric:" "$file" | awk '{print $(NF-1)" "$NF}')
            printf "%-20s" "$value"
        done
        echo ""
    done
}

run_randread_benchmark() {
    local drive=$1
    local test_path=$2
    local result_file=$3

    print_header "4K Random Read Benchmark on /dev/$drive"
    print_info "Test path: $test_path"
    print_info "Test size: $TEST_SIZE"
    print_info "Runtime per test: ${RUNTIME}s"
    echo ""
    echo -e "${YELLOW}Testing methodology: FIO 4K random read at QD1, QD32, QD256${NC}"
    echo ""

    # Create test directory if needed
    local test_dir="$test_path/fio_benchmark_test"
    mkdir -p "$test_dir"

    # Results array
    declare -A results

    # Test 1: Random Read 4K (QD1) - Latency
    echo -e "${YELLOW}[1/3] Random Read 4K (QD1) - Latency test${NC}"
    local rand_read_qd1=$(fio --name=rand_read_qd1 --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=1 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null)
    local rand_read_qd1_iops=$(echo "$rand_read_qd1" | jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    local rand_read_qd1_lat=$(echo "$rand_read_qd1" | jq -r '.jobs[0].read.lat_ns.mean / 1000' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_qd1_iops}, Latency: ${rand_read_qd1_lat} µs"
    results["rand_read_qd1_iops"]=$rand_read_qd1_iops
    results["rand_read_qd1_lat"]=$rand_read_qd1_lat

    # Test 2: Random Read 4K (QD32) - Typical workload
    echo -e "${YELLOW}[2/3] Random Read 4K (QD32) - Typical workload${NC}"
    local rand_read_qd32=$(fio --name=rand_read_qd32 --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=32 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_qd32}"
    results["rand_read_qd32"]=$rand_read_qd32

    # Test 3: Random Read 4K (QD256) - Manufacturer spec
    echo -e "${YELLOW}[3/3] Random Read 4K (QD256) - MFG Spec Comparison${NC}"
    echo "  (Micron spec: 800,000 IOPS at QD256)"
    local rand_read_qd256=$(fio --name=rand_read_qd256 --directory=$test_dir --rw=randread --bs=4k --size=$TEST_SIZE \
        --numjobs=1 --iodepth=256 --ioengine=libaio --direct=1 --time_based --runtime=$RUNTIME --group_reporting --output-format=json 2>/dev/null | \
        jq -r '.jobs[0].read.iops' 2>/dev/null || echo "0")
    local pct_of_spec=$(echo "scale=1; $rand_read_qd256 / 8000" | bc 2>/dev/null || echo "0")
    echo "  IOPS: ${rand_read_qd256} (${pct_of_spec}% of spec)"
    results["rand_read_qd256"]=$rand_read_qd256

    # Cleanup test files
    rm -rf "$test_dir"

    # Save results to file
    {
        echo "Drive: /dev/$drive"
        echo "Test Date: $(date)"
        echo "Test Size: $TEST_SIZE"
        echo "Runtime: ${RUNTIME}s per test"
        echo ""
        echo "4K Random Read Results:"
        echo "  QD1:   ${results[rand_read_qd1_iops]} IOPS, ${results[rand_read_qd1_lat]} µs latency"
        echo "  QD32:  ${results[rand_read_qd32]} IOPS"
        echo "  QD256: ${results[rand_read_qd256]} IOPS (MFG spec: 800,000)"
        echo ""
        echo "Testing Methodology:"
        echo "  Tool: FIO (Flexible I/O Tester)"
        echo "  Block size: 4K"
        echo "  Queue depths: QD1, QD32, QD256"
        echo "  I/O pattern: Random read"
        echo "  Runtime: ${RUNTIME}s per test"
        echo "  Test location: Filesystem-level"
    } > "$result_file"

    print_info "Results saved to: $result_file"
    echo ""

    # Print summary
    echo -e "${GREEN}=== Summary ===${NC}"
    echo "  QD1 (latency):    ${results[rand_read_qd1_iops]} IOPS @ ${results[rand_read_qd1_lat]} µs"
    echo "  QD32 (typical):   ${results[rand_read_qd32]} IOPS"
    echo "  QD256 (max):      ${results[rand_read_qd256]} IOPS (${pct_of_spec}% of 800K spec)"
    echo ""
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -d, --drive DRIVE     Specify drive(s) to benchmark (e.g., nvme0n1,nvme1n1)"
    echo "  -s, --size SIZE       Test file size (default: 4G)"
    echo "  -t, --time SECONDS    Runtime per test in seconds (default: 60)"
    echo "  -o, --output DIR      Output directory for results (default: ./benchmark_results)"
    echo "  -r, --randread        4K random read only (QD1, QD32, QD256) - quick test"
    echo "  -i, --info            Show drive info and settings only (no benchmark)"
    echo "  -c, --compare         Compare existing benchmark results"
    echo "  -h, --help            Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                           # Interactive mode - select drives"
    echo "  $0 -d nvme1n1                # Benchmark specific drive"
    echo "  $0 -d nvme0n1,nvme1n1        # Benchmark multiple drives"
    echo "  $0 -r -d nvme1n1             # Quick 4K random read test only"
    echo "  $0 -i -d nvme1n1             # Show info only for drive"
    echo "  $0 -s 1G -t 30               # Quick benchmark with 1G file, 30s tests"
    echo "  $0 -c                        # Compare previous results"
}

main() {
    local info_only=false
    local compare_only=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -d|--drive)
                SELECTED_DRIVES="$2"
                shift 2
                ;;
            -s|--size)
                TEST_SIZE="$2"
                shift 2
                ;;
            -t|--time)
                RUNTIME="$2"
                shift 2
                ;;
            -o|--output)
                OUTPUT_DIR="$2"
                shift 2
                ;;
            -r|--randread)
                RANDREAD_ONLY=true
                shift
                ;;
            -i|--info)
                info_only=true
                shift
                ;;
            -c|--compare)
                compare_only=true
                shift
                ;;
            -h|--help)
                show_usage
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done

    # Compare mode
    if [ "$compare_only" = true ]; then
        compare_results
        exit 0
    fi

    # Check dependencies
    check_dependencies

    # Detect drives
    detect_nvme_drives

    # Select drives
    local drives_to_test=()

    if [ -n "$SELECTED_DRIVES" ]; then
        IFS=',' read -ra drives_to_test <<< "$SELECTED_DRIVES"
    else
        # Interactive selection
        echo "Select drives to benchmark (comma-separated numbers, or 'all'):"
        read -p "> " selection

        if [ "$selection" = "all" ]; then
            drives_to_test=("${NVME_DRIVES[@]}")
        else
            IFS=',' read -ra indices <<< "$selection"
            for idx in "${indices[@]}"; do
                idx=$((idx - 1))
                if [ $idx -ge 0 ] && [ $idx -lt ${#NVME_DRIVES[@]} ]; then
                    drives_to_test+=("${NVME_DRIVES[$idx]}")
                fi
            done
        fi
    fi

    if [ ${#drives_to_test[@]} -eq 0 ]; then
        print_error "No drives selected"
        exit 1
    fi

    print_info "Selected drives: ${drives_to_test[*]}"

    # Create output directory
    mkdir -p "$OUTPUT_DIR"

    # Process each drive
    for drive in "${drives_to_test[@]}"; do
        # Show drive info
        show_drive_info "$drive"
        show_performance_settings "$drive"

        # Run benchmark if not info-only mode
        if [ "$info_only" = false ]; then
            # Get mount point or use raw device path
            local mount_point=$(get_mount_point "$drive")

            if [ -z "$mount_point" ]; then
                print_warn "Drive /dev/$drive is not mounted"
                print_warn "For accurate filesystem benchmarks, mount the drive first"
                echo ""
                read -p "Skip benchmark for this drive? [y/N] " skip
                if [[ "$skip" =~ ^[Yy]$ ]]; then
                    continue
                fi
                # Use /tmp as fallback
                mount_point="/tmp"
                print_info "Using /tmp for benchmark (not ideal for raw drive performance)"
            fi

            # Check disk space
            local available_space=$(df -BG "$mount_point" | tail -1 | awk '{print $4}' | sed 's/G//')
            local required_space=$(echo "$TEST_SIZE" | sed 's/G//')

            if [ "$available_space" -lt "$required_space" ]; then
                print_error "Not enough space on $mount_point (available: ${available_space}G, required: ${required_space}G)"
                continue
            fi

            local result_file="$OUTPUT_DIR/${drive}_$(date +%Y%m%d_%H%M%S).txt"

            if [ "$RANDREAD_ONLY" = true ]; then
                run_randread_benchmark "$drive" "$mount_point" "$result_file"
            else
                run_fio_benchmark "$drive" "$mount_point" "$result_file"
            fi
        fi
    done

    # Compare results if multiple drives were benchmarked
    if [ "$info_only" = false ] && [ ${#drives_to_test[@]} -gt 1 ]; then
        compare_results
    fi

    print_header "Benchmark Complete"
    print_info "Results saved in: $OUTPUT_DIR"
}

main "$@"
