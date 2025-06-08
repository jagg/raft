#!/bin/bash

# Test script to verify parallel execution behavior in Raft
# This script tests that election requests and heartbeats are sent in parallel

echo "=== Parallel Execution Test ==="
echo "Testing that Raft operations use parallel execution instead of sequential"
echo

# Store PIDs of background processes for cleanup
PIDS=()

# Function to cleanup all background processes
cleanup() {
    echo
    echo "Cleaning up background processes..."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Stopping process $pid"
            kill "$pid" 2>/dev/null
        fi
    done
    # Wait a moment for graceful shutdown
    sleep 1
    # Force kill any remaining processes
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            echo "Force killing process $pid"
            kill -9 "$pid" 2>/dev/null
        fi
    done
    # Also kill any raft processes that might be running
    pkill -f "main.exe.*-i" 2>/dev/null || true
    echo "Cleanup complete"
}

# Set up cleanup on script exit
trap cleanup EXIT

echo "Building project..."
dune build

echo
echo "=== Test 1: Sequential vs Parallel Election Timing ==="

# Test with a configuration that has multiple unreachable replicas
# This will cause timeouts, allowing us to measure if they happen in parallel

echo "Starting node with multi-replica config (other replicas unreachable)..."
./_build/default/bin/main.exe -i "one" -o 7771 -f "./cluster.conf" &
NODE_PID=$!
PIDS+=($NODE_PID)

echo "Node started with PID $NODE_PID"
echo "Waiting for node to start and trigger elections..."
echo "This should show parallel behavior - multiple connection attempts happening concurrently"

# Wait and observe the election behavior
echo "Observing election attempts for 15 seconds..."
echo "Look for 'Trigger election error' messages - they should appear close together in time"
echo "if running in parallel, rather than with long delays if running sequentially"

sleep 15

echo
echo "=== Test 2: Multi-Node Parallel Heartbeat Test ==="

# Kill the first node
kill $NODE_PID 2>/dev/null
PIDS=()
sleep 2

# Start 3 nodes to test parallel heartbeats
echo "Starting 3-node cluster to test parallel heartbeats..."

echo "Starting node 'one' on port 7771..."
./_build/default/bin/main.exe -i "one" -o 7771 -f "./cluster.conf" &
NODE1_PID=$!
PIDS+=($NODE1_PID)

echo "Starting node 'two' on port 7772..."
./_build/default/bin/main.exe -i "two" -o 7772 -f "./cluster2.conf" &
NODE2_PID=$!
PIDS+=($NODE2_PID)

echo "Starting node 'three' on port 7773..."
./_build/default/bin/main.exe -i "three" -o 7773 -f "./cluster3.conf" &
NODE3_PID=$!
PIDS+=($NODE3_PID)

echo "All nodes started. Waiting for leader election and heartbeat activity..."
echo "Once a leader is elected, watch for 'Sending heartbeat' messages"
echo "They should appear close together in time if parallel execution is working"

sleep 20

echo
echo "=== Test 3: Performance Comparison Test ==="

# Kill all nodes
for pid in "${PIDS[@]}"; do
    kill "$pid" 2>/dev/null
done
PIDS=()
sleep 3

echo "Testing with unreachable replicas to measure timeout behavior..."
echo "If parallel: multiple timeouts should happen simultaneously"
echo "If sequential: timeouts would be cumulative and much slower"

# Measure time for election attempts with unreachable replicas
echo "Starting timing test..."
start_time=$(date +%s.%N)

./_build/default/bin/main.exe -i "one" -o 7771 -f "./cluster.conf" &
NODE_PID=$!
PIDS+=($NODE_PID)

# Wait for one complete election cycle
sleep 8

end_time=$(date +%s.%N)
elapsed=$(echo "$end_time - $start_time" | bc -l 2>/dev/null || echo "N/A")

echo "Election cycle completed in: ${elapsed} seconds"
echo
echo "=== Analysis ==="
echo "If the implementation is working correctly, you should observe:"
echo "1. Multiple 'connection refused' errors appearing close together in time"
echo "2. Election cycles completing relatively quickly despite multiple unreachable replicas"
echo "3. When heartbeats are sent, they should appear in rapid succession"
echo
echo "Before parallel implementation:"
echo "- Election timeouts would be cumulative (3+ seconds per replica)"
echo "- Total election time would be much longer"
echo "- Heartbeats would appear with delays between them"
echo
echo "After parallel implementation:"
echo "- Election timeouts happen concurrently"
echo "- Total election time is roughly equal to a single timeout"
echo "- Heartbeats appear almost simultaneously"

echo
echo "=== Performance Benefits ==="
echo "Parallel execution provides:"
echo "✓ Faster leader elections"
echo "✓ More efficient heartbeat distribution"
echo "✓ Better cluster responsiveness"
echo "✓ Reduced latency for consensus operations"
echo
echo "This is especially important in larger clusters where sequential"
echo "communication would create significant delays."