#!/bin/bash

# Function to display usage
usage() {
    echo "Usage: $0 --cpu <number_of_cores> --load <load_level> --time <duration> --host <remote_host>"
    echo "  --cpu <number_of_cores>   : Number of CPU cores to stress"
    echo "  --load <load_level>       : Load level (1 to 100, 100 for full load)"
    echo "  --time <duration>         : Duration to run stress test (e.g., 60s, 2m, 1h)"
    echo "  --host <remote_host>      : The remote host to SSH into (e.g., node3)"
    exit 1
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --cpu)
            CPU_CORES="$2"
            shift 2
            ;;
        --load)
            LOAD_LEVEL="$2"
            shift 2
            ;;
        --time)
            DURATION="$2"
            shift 2
            ;;
        --host)
            REMOTE_HOST="$2"
            shift 2
            ;;
        *)
            usage
            ;;
    esac
done

# Check if all parameters are set
if [[ -z "$CPU_CORES" || -z "$LOAD_LEVEL" || -z "$DURATION" || -z "$REMOTE_HOST" ]]; then
    usage
fi

# Validate CPU_CORES
if ! [[ "$CPU_CORES" =~ ^[0-9]+$ ]]; then
    echo "Error: CPU cores must be a number."
    exit 1
fi

# Validate LOAD_LEVEL
if ! [[ "$LOAD_LEVEL" =~ ^[0-9]+$ ]] || ((LOAD_LEVEL < 1 || LOAD_LEVEL > 100)); then
    echo "Error: Load level must be an integer between 1 and 100."
    exit 1
fi

# Validate DURATION (must match the format like 60s, 2m, 1h)
if ! [[ "$DURATION" =~ ^[0-9]+[smh]$ ]]; then
    echo "Error: Duration format is invalid. Example: 60s, 2m, 1h"
    exit 1
fi

# SSH into remote host and execute the stress test
echo "SSH into $REMOTE_HOST and starting CPU stress test with $CPU_CORES core(s), load level: $LOAD_LEVEL%, duration: $DURATION"

ssh "$REMOTE_HOST" "stress-ng --cpu $CPU_CORES --cpu-load $LOAD_LEVEL --timeout $DURATION"

echo "Stress test completed on $REMOTE_HOST."
