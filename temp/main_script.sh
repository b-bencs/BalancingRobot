#!/bin/bash

# Function to display help message
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo
    echo "Options:"
    echo "  --timeout <value>          Set timeout for robot deployment (e.g., 30)"
    echo "  --fps <value>              Set FPS for robot deployment (e.g., 60)"
    echo "  --cpu <value>              Number of CPU cores to stress (e.g., 4)"
    echo "  --load <value>             CPU load level to stress (1-100, e.g., 80)"
    echo "  --stress-time <value>      Duration for stress test (e.g., 60s, 2m)"
    echo "  --host <host>              Remote host to perform CPU stress test (e.g., node3)"
    echo "  --server-yaml <path>       Path to the server YAML file for deployment"
    echo "  --mode <edf|gd|be>         Specify the mode (edf, gd, or be)"
    echo "  --runtime <value>          Runtime for EDF mode (e.g., 5)"
    echo "  --deadline <value>         Deadline for EDF mode (e.g., 100)"
    echo "  --period <value>           Period for EDF mode (e.g., 100)"
    echo "  --cpu-limit <value>        CPU limit for GD mode (e.g., 200m)"
    echo "  --help                     Show this help message"
    echo
    echo "Example usage:"
    echo "  ./main_script.sh --timeout 40 --fps 30 --cpu 4 --load 80 --stress-time 2m --host node4 --server-yaml V4/Balancing-.../functions/pidserver_gd.yaml --mode gd --cpu-limit 200m"
}

# If no arguments are passed, show help
if [ "$#" -eq 0 ]; then
    show_help
    echo "No arguments"
    exit 0
fi

# Default values for parameters
LIMIT=10
TIMEOUT=30
FPS=60
CPU_CORES=1
LOAD_LEVEL=50
STRESS_TIME="60s"
REMOTE_HOST="node3"
SERVER_YAML_PATH="/users/szefoka/Dec/BalancingRobot/functions/pidserver_edf.yaml"  # Default YAML path
MODE="be"
RUNTIME="5"
DEADLINE="100"
PERIOD="100"
CPU_LIMIT="100m"

# Parse command-line arguments
while [[ "$#" -gt 0 ]]; do
    case $1 in
        --help) show_help; exit 0 ;;
        --timeout) TIMEOUT="$2"; shift ;;
        --fps) FPS="$2"; shift ;;
        --cpu) CPU_CORES="$2"; shift ;;
        --load) LOAD_LEVEL="$2"; shift ;;
        --stress-time) STRESS_TIME="$2"; shift ;;
        --host) REMOTE_HOST="$2"; shift ;;
        --server-yaml) SERVER_YAML_PATH="/users/szefoka/Dec/BalancingRobot/functions/" + "$2"; shift ;;
        --mode) MODE="$2"; shift ;;
        --runtime) RUNTIME="$2"; shift ;;
        --deadline) DEADLINE="$2"; shift ;;
        --period) PERIOD="$2"; shift ;;
        --cpu-limit) CPU_LIMIT="$2"; shift ;;
        *) echo "Unknown parameter passed: $1"; show_help; exit 1 ;;
    esac
    shift
done

# Debug print to show the parsed parameters
echo "Parsed parameters:"
echo "  --timeout $TIMEOUT"
echo "  --fps $FPS"
echo "  --cpu $CPU_CORES"
echo "  --load $LOAD_LEVEL"
echo "  --stress-time $STRESS_TIME"
echo "  --host $REMOTE_HOST"
echo "  --server-yaml $SERVER_YAML_PATH"
echo "  --mode $MODE"
echo "  --runtime $RUNTIME"
echo "  --deadline $DEADLINE"
echo "  --period $PERIOD"
echo "  --cpu-limit $CPU_LIMIT"

# Modify the server YAML based on mode
if [ "$MODE" == "edf" ]; then
    # Modify the EDF YAML with runtime, deadline, and period
    echo "Modifying pidserver_edf.yaml for EDF mode with runtime=$RUNTIME, deadline=$DEADLINE, period=$PERIOD"
    echo "$SERVER_YAML_PATH"
    sed -i "s/\(runtime:\s*\).*/\1\"$RUNTIME\"/" "$SERVER_YAML_PATH"
    sed -i "s/\(deadline:\s*\).*/\1\"$DEADLINE\"/" "$SERVER_YAML_PATH"
    sed -i "s/\(period:\s*\).*/\1\"$PERIOD\"/" "$SERVER_YAML_PATH"
elif [ "$MODE" == "gd" ]; then
    # Modify the GD YAML with cpu-limit
    SERVER_YAML_PATH="/V4/BalancingRobot-main/functions/pidserver_gd.yaml"  # GD mode YAML path
    echo "Modifying pidserver_gd.yaml for GD mode with cpu-limit=$CPU_LIMIT"
    sed -i "s/\(cpu:\s*\).*/\1$CPU_LIMIT/" "$SERVER_YAML_PATH"
elif [ "$MODE" == "be" ]; then
    # Do nothing for Best Effort mode
    echo "Best Effort mode selected, no modifications made to the YAML."
else
    echo "Invalid mode: $MODE. Please choose from 'edf', 'gd', or 'be'."
    exit 1
fi

# Kubernetes pod details
POD_NAME="influxdb-0"
NAMESPACE="default"  # Change if needed

# Labels for directory naming
LABEL1="robot_test"
LABEL2="angle_data"

# Fixed paths
ROBOT_YAML_PATH="/users/szefoka/Dec/BalancingRobot/Robot/deployment.yaml"
SERVER_FAASTCLI_URL="localhost:31112"  # Default faas-cli URL

# Get current timestamp
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")
DIR_NAME="${TIMESTAMP}_${LABEL1}_${LABEL2}"

# Define paths
BASE_PATH="/var/lib/influxdb/export"
LOCAL_SAVE_PATH="./exported_data"

# Ensure local save directory exists
mkdir -p "${LOCAL_SAVE_PATH}"

#!/bin/bash

# Define timeout and fps variables (these will be passed as arguments to your script)
# YAML file path
#ROBOT_YAML_PATH="/path/to/your/deployment.yaml"

# Use echo with sed to create the YAML content from scratch
echo "apiVersion: apps/v1
kind: Deployment
metadata:
  name: robot
  labels:
    app: robot
spec:
  replicas: 2
  selector:
    matchLabels:
      app: robot
  template:
    metadata:
      labels:
        app: robot
    spec:
      containers:
      - name: robot
        image: mmarci98/edfrobotcontainer_2
        command: [\"./myapp\",\"$TIMEOUT\",\"$FPS\"]  # Substitute timeout and fps here
      nodeSelector:
        job: \"robot\"" > "$ROBOT_YAML_PATH"

# Display the created YAML file
echo "YAML file created with timeout=$TIMEOUT and fps=$FPS:"
#cat "$ROBOT_YAML_PATH"

# After modification, display the file contents
#echo "After modification:"
#cat "$ROBOT_YAML_PATH"

# After modification, display the file contents
#echo "After modification:"
#cat "$ROBOT_YAML_PATH"
# Modify the replicas value
#echo "Modifying replicas in $ROBOT_YAML_PATH"
#sed -i "s/replicas: [0-9]\+/replicas: 2/" "$ROBOT_YAML_PATH"

# Confirm the change
#echo "File after modification:"
#cat "$ROBOT_YAML_PATH"

# Apply the modified robot deployment YAML
echo "Applying robot deployment with timeout=$TIMEOUT and fps=$FPS"
kubectl apply -f "$ROBOT_YAML_PATH"


# Run the CPU stress test remotely
echo "Starting CPU stress test on $REMOTE_HOST"
./STRESS/stress_cpu_remote.sh --cpu "$CPU_CORES" --load "$LOAD_LEVEL" --time "$STRESS_TIME" --host "$REMOTE_HOST"

# Wait 10 seconds before querying InfluxDB
echo "Waiting 10 seconds before fetching data..."
sleep 10

# Calculate time range (past 20 seconds)
CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
START_TIME=$(date -u -d "-20 seconds" +"%Y-%m-%dT%H:%M:%SZ")

# Command to execute inside the pod
CMD="
mkdir -p ${BASE_PATH}/${DIR_NAME} &&
influx -database robot -execute \"SELECT * FROM angle WHERE time >= '${START_TIME}' AND time <= '${CURRENT_TIME}'\" -format csv > ${BASE_PATH}/${DIR_NAME}/output.csv &&
echo \"Data exported to ${BASE_PATH}/${DIR_NAME}/output.csv\"
"

# Execute the command inside the pod
kubectl exec -it "${POD_NAME}" -- /bin/bash -c "${CMD}"

# Ensure the local directory with the same timestamp exists
LOCAL_DIR="${LOCAL_SAVE_PATH}/${DIR_NAME}"
mkdir -p "$LOCAL_DIR"

# Copy the folder from the pod to the local machine
kubectl cp "${POD_NAME}:${BASE_PATH}/${DIR_NAME}" "$LOCAL_DIR"

# Confirm completion
echo "Folder copied to ${LOCAL_DIR}"
