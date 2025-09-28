#!/bin/bash

# =============================================================================
# System Network Monitor
# Version: 1.0
# Author: DanLin (DanLinX2004X)
# Github author: https://github.com/DanLinX2004X
# Description: Bash script for monitoring system metrics (CPU, memory, disk, network)
# =============================================================================

SCRIPT_NAME="system-monitor.sh"
VERSION="1.0"

#--- COLOR FOR OUTPUT ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

#--- Default variables ---
INTERVAL=0
BRIEF_MODE=false
USE_COLORS=true
EXIT_SIGNAL=false

#--- Help display function ---
show_help() {
    cat <<EOF
${SCRIPT_NAME} - System Monitoring Tool (CPU, Memory, Disk, Network)

Usage: $0 [OPTIONS]

OPTIONS:
  -i N         Update interval in seconds (default: single output)
  --brief      Brief output (machine-readable format)
  --no-color   Disable colored output
  --version    Show version information
  --help       Show this help message

EXAMPLES:
  $0                          # Single output
  $0 -i 5                     # Update every 5 seconds
  $0 --brief                  # Brief output for scripting
  $0 -i 2 --no-color          # No colors, 2-second interval

MONITORED METRICS:
  • CPU load average (1, 5, 15 minutes)
  • Memory usage (RAM utilization)
  • Disk space usage (root partition)
  • Network interface statistics
  • Process count

EXIT CODES:
  0 - Success
  1 - Invalid arguments
  2 - Missing dependencies
EOF
}

#--- Command Line Arguments Parser ---
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -i)
                if [[ ! $2 =~ ^[0-9]+$ ]] || [ "$2" -lt 1 ]; then
                    echo -e "${RED}Error: Interval must be a positive integer${NC}"
                    exit 1
                fi
                INTERVAL=$2
                shift 2
                ;;
            --brief)
                BRIEF_MODE=true
                USE_COLORS=false
                shift
                ;;
            --no-color)
                USE_COLORS=false
                shift
                ;;
            --version)
                echo "${SCRIPT_NAME} version ${VERSION}"
                exit 0
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
}

# --- Signal Handler for Clean Shutdown ---
cleanup() {
    EXIT_SIGNAL=true
    echo -e "\n${YELLOW}Monitoring stopped. Goodbye!${NC}"
    exit 0
}
trap cleanup INT TERM



# --- Colorize Output Based on Thresholds ---
colorize() {
    local value=$1
    local warning=$2
    local critical=$3

    #SKip coloring if disabled
    if [ "$USE_COLORS" = false ]; then
        echo "$value"
        return
    fi

    # Handle empty or N/A values
    if [ -z "$value" ] || [ "$value" = "N/A" ]; then
        echo -e "${YELLOW}N/A${NC}"
     # Check if value exceeds critical threshold (requires bc for float comparison)
    elif [ "$(echo "$value >= $critical" | bc 2>/dev/null)" = "1" ] 2>/dev/null; then
        echo -e "${RED}$value${NC}"
    # Check if value exceeds warning threshold
    elif [ "$(echo "$value >= $warning" | bc 2>/dev/null)" = "1" ] 2>/dev/null; then
        echo -e "${YELLOW}$value${NC}"
    else
        echo -e "${GREEN}$value${NC}"
    fi
}

# --- CPU Metrics Collection ---
get_cpu_metrics() {
    local loadavg=$(cat /proc/loadavg 2>/dev/null)
    if [ -n "$loadavg" ]; then
        CPU_LOAD_1MIN=$(echo "$loadavg" | awk '{print $1}')
        CPU_LOAD_5MIN=$(echo "$loadavg" | awk '{print $2}')
        CPU_LOAD_15MIN=$(echo "$loadavg" | awk '{print $3}')
        CPU_CORES=$(nproc 2>/dev/null || echo "1")

        # Calculate load as percentage of CPU cores
        local load_percent=$(echo "scale=0; ($CPU_LOAD_1MIN * 100) / $CPU_CORES" | bc 2>/dev/null)
        CPU_LOAD_PERCENT=${load_percent:-0}
    else
        CPU_LOAD_1MIN="N/A"
        CPU_LOAD_5MIN="N/A"
        CPU_LOAD_15MIN="N/A"
        CPU_LOAD_PERCENT="N/A"
        CPU_CORES="N/A"
    fi
}

# --- Memory Metrics Collection ---
get_memory_metrics() {
    local mem_info=$(free -b 2>/dev/null | grep Mem)
    if [ -n "$mem_info" ]; then
        MEM_TOTAL=$(echo "$mem_info" | awk '{printf "%.2f", $2/1024/1024/1024}')
        MEM_USED=$(echo "$mem_info" | awk '{printf "%.2f", $3/1024/1024/1024}')
        MEM_AVAILABLE=$(echo "$mem_info" | awk '{printf "%.2f", $7/1024/1024/1024}')
        MEM_PERCENT=$(echo "scale=1; ($MEM_USED * 100) / $MEM_TOTAL" | bc 2>/dev/null)
    else
        MEM_TOTAL="N/A"
        MEM_USED="N/A"
        MEM_AVAILABLE="N/A"
        MEM_PERCENT="N/A"
    fi
}

# --- Disk Metrics Collection ---
get_disk_metrics() {
    local disk_info=$(df -B1 / 2>/dev/null | awk 'NR==2')
    if [ -n "$disk_info" ]; then
        DISK_USED=$(echo "$disk_info" | awk '{printf "%.1f", $3/1024/1024/1024}')
        DISK_AVAILABLE=$(echo "$disk_info" | awk '{printf "%.1f", $4/1024/1024/1024}')
        DISK_PERCENT=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
        DISK_FILESYSTEM=$(echo "$disk_info" | awk '{print $1}')
        DISK_MOUNT=$(echo "$disk_info" | awk '{print $6}')
    else
        DISK_USED="N/A"
        DISK_AVAILABLE="N/A"
        DISK_PERCENT="N/A"
        DISK_FILESYSTEM="N/A"
        DISK_MOUNT="N/A"
    fi
}

# --- Network Metrics Collection ---
get_network_metrics() {
    # Get primary network interface (route to Google DNS)
    local interface=$(ip route get 8.8.8.8 2>/dev/null | awk '{print $5}' | head -1)
    if [ -n "$interface" ] && [ "$interface" != "dev" ]; then
        NET_INTERFACE="$interface"
        local rx_bytes=$(cat "/sys/class/net/$interface/statistics/rx_bytes" 2>/dev/null)
        local tx_bytes=$(cat "/sys/class/net/$interface/statistics/tx_bytes" 2>/dev/null)

        NET_RX_MB=$(echo "scale=2; ${rx_bytes:-0} / 1024 / 1024" | bc 2>/dev/null)
        NET_TX_MB=$(echo "scale=2; ${tx_bytes:-0} / 1024 / 1024" | bc 2>/dev/null)
    else
        NET_INTERFACE="N/A"
        NET_RX_MB="N/A"
        NET_TX_MB="N/A"
    fi
}

# --- Process Metrics Collection ---
get_process_metrics() {
    PROCESS_COUNT=$(ps -e 2>/dev/null | wc -l)
    PROCESS_COUNT=$((PROCESS_COUNT - 1))  # Subtract header line
    [ -z "$PROCESS_COUNT" ] && PROCESS_COUNT="N/A"
}

# --- Machine-Readable Output Format ---
print_brief_stats() {
    get_cpu_metrics
    get_memory_metrics
    get_disk_metrics
    get_network_metrics
    get_process_metrics

    echo "timestamp=$(date +%s)"
    echo "cpu_load_1min=$CPU_LOAD_1MIN"
    echo "cpu_load_5min=$CPU_LOAD_5MIN"
    echo "cpu_load_15min=$CPU_LOAD_15MIN"
    echo "cpu_cores=$CPU_CORES"
    echo "cpu_load_percent=$CPU_LOAD_PERCENT"
    echo "mem_total_gb=$MEM_TOTAL"
    echo "mem_used_gb=$MEM_USED"
    echo "mem_available_gb=$MEM_AVAILABLE"
    echo "mem_usage_percent=$MEM_PERCENT"
    echo "disk_filesystem=$DISK_FILESYSTEM"
    echo "disk_mount=$DISK_MOUNT"
    echo "disk_used_gb=$DISK_USED"
    echo "disk_available_gb=$DISK_AVAILABLE"
    echo "disk_usage_percent=$DISK_PERCENT"
    echo "network_interface=$NET_INTERFACE"
    echo "network_rx_mb=$NET_RX_MB"
    echo "network_tx_mb=$NET_TX_MB"
    echo "process_count=$PROCESS_COUNT"
}

# --- Human-Readable Colored Output ---
print_detailed_stats() {
    get_cpu_metrics
    get_memory_metrics
    get_disk_metrics
    get_network_metrics
    get_process_metrics

    # Header section
    echo -e "${CYAN}==== SYSTEM MONITOR ====${NC}"
    echo -e "Time: $(date)"
    echo -e "Uptime: $(uptime -p | sed 's/up //')"
    echo

    # CPU Information
    echo -e "${BLUE}==== CPU LOAD ====${NC}"
    echo -e "CPU Cores: $CPU_CORES"
    echo -e "Load Average: 1min: $(colorize $CPU_LOAD_1MIN 1 2) | 5min: $(colorize $CPU_LOAD_5MIN 1 2) | 15min: $(colorize $CPU_LOAD_15MIN 1 2)"
    echo -e "System Load: $(colorize ${CPU_LOAD_PERCENT}% 70 90)"
    echo

    # Memory Information
    echo -e "${BLUE}==== MEMORY USAGE ====${NC}"
    echo -e "Total: ${MEM_TOTAL} GB"
    echo -e "Used: $(colorize "${MEM_USED} GB" $(echo "scale=0; $MEM_TOTAL * 0.7" | bc 2>/dev/null) $(echo "scale=0; $MEM_TOTAL * 0.9" | bc 2>/dev/null))"
    echo -e "Available: ${MEM_AVAILABLE} GB"
    echo -e "Usage: $(colorize "${MEM_PERCENT}%" 70 90)"
    echo

    # Disk Information
    echo -e "${BLUE}==== DISK SPACE ====${NC}"
    echo -e "Filesystem: $DISK_FILESYSTEM ($DISK_MOUNT)"
    echo -e "Used: ${DISK_USED} GB"
    echo -e "Available: ${DISK_AVAILABLE} GB"
    echo -e "Usage: $(colorize "${DISK_PERCENT}%" 80 90)"
    echo

    # Network Information
    echo -e "${BLUE}==== NETWORK STATISTICS ====${NC}"
    echo -e "Interface: $NET_INTERFACE"
    echo -e "Received: ${NET_RX_MB} MB"
    echo -e "Transmitted: ${NET_TX_MB} MB"
    echo

    # Process Information
    echo -e "${BLUE}==== PROCESSES ====${NC}"
    echo -e "Total Processes: $PROCESS_COUNT"
}

# --- Check System Dependencies ---
check_dependencies() {
    local missing_deps=()

    # Check for essential commands
    for cmd in awk grep free df ps; do
        if ! command -v "$cmd" &> /dev/null; then
            missing_deps+=("$cmd")
        fi
    done

    # Check for bc (optional but recommended)
    if ! command -v bc &> /dev/null; then
        echo -e "${YELLOW}Warning: 'bc' not installed. Some calculations will be simplified.${NC}"
        echo -e "Install with: sudo apt install bc"
    fi

    if [ ${#missing_deps[@]} -ne 0 ]; then
        echo -e "${RED}Error: Missing required dependencies: ${missing_deps[*]}${NC}"
        exit 2
    fi
}

# --- Main Application Logic ---
main() {
    parse_arguments "$@"
    check_dependencies

    # Brief mode for machine consumption
    if [ "$BRIEF_MODE" = true ]; then
        print_brief_stats
        exit 0
    fi

    # Single output mode
    if [ "$INTERVAL" -eq 0 ]; then
        print_detailed_stats
    else
        # Continuous monitoring mode
        echo -e "${GREEN}Starting system monitor with ${INTERVAL}s interval...${NC}"
        echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
        echo

        while [ "$EXIT_SIGNAL" = false ]; do
            print_detailed_stats
            echo -e "${CYAN}————————————————————————————————————————${NC}"
            echo -e "Next update in ${INTERVAL}s... ($(date -d "+${INTERVAL} seconds" '+%H:%M:%S'))"
            echo

            # Sleep with interrupt checking
            for ((i=0; i<INTERVAL && EXIT_SIGNAL==false; i++)); do
                sleep 1
            done
        done
    fi
}

# --- Script Entry Point ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi

