#!/bin/bash

SERVICES_FILE="services.txt"
LOG_FILE="/var/log/health_monitor.log"
DRY_RUN=false

# Detect mode (systemctl or service)
if command -v systemctl &> /dev/null && systemctl list-units &> /dev/null; then
    MODE="systemctl"
else
    MODE="service"
fi

# Check for --dry-run flag
if [[ "$1" == "--dry-run" ]]; then
    DRY_RUN=true
fi

# Counters
total=0
healthy=0
recovered=0
failed=0

# Validate services file
if [[ ! -f "$SERVICES_FILE" || ! -s "$SERVICES_FILE" ]]; then
    echo "Error: services.txt missing or empty"
    exit 1
fi

# Create log file if not exists
sudo touch "$LOG_FILE"

# Logging function
log_event() {
    local level=$1
    local service=$2
    local message=$3

    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $service - $message" | sudo tee -a "$LOG_FILE" > /dev/null
}

echo "Monitoring started using $MODE..."

# Function to check service status
check_status() {
    if [[ "$MODE" == "systemctl" ]]; then
        systemctl is-active "$1" &> /dev/null
    else
        service "$1" status &> /dev/null
    fi
    return $?
}

# Function to restart service
restart_service() {
    if [[ "$MODE" == "systemctl" ]]; then
        sudo systemctl restart "$1"
    else
        sudo service "$1" restart
    fi
}

# Main loop
while read -r service || [[ -n "$service" ]]; do

    # Skip empty lines
    [[ -z "$service" ]] && continue

    ((total++))

    if check_status "$service"; then
        ((healthy++))
        log_event "INFO" "$service" "Service is running"
    else
        echo "Service $service is down. Attempting restart..."

        if [[ "$DRY_RUN" == false ]]; then
            restart_service "$service"
        else
            echo "[DRY-RUN] Would restart $service"
        fi

        sleep 5

        if check_status "$service"; then
            ((recovered++))
            log_event "RECOVERED" "$service" "Service restarted successfully"
        else
            ((failed++))
            log_event "FAILED" "$service" "Service restart failed"
        fi
    fi

done < "$SERVICES_FILE"

# Summary Output
echo ""
echo "===== SUMMARY ====="
printf "%-15s : %d\n" "Total Checked" "$total"
printf "%-15s : %d\n" "Healthy" "$healthy"
printf "%-15s : %d\n" "Recovered" "$recovered"
printf "%-15s : %d\n" "Failed" "$failed"
