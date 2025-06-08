# Toy Raft

This is my toy Raft implementation, backing a key-value store. Still work in progress!

## New Client APIs

The Raft cluster now supports client operations to add, delete, and retrieve items from the distributed state machine.

### Available Operations

- **Add**: Store a key-value pair in the state machine
- **Delete**: Remove a key from the state machine
- **Get**: Retrieve the value for a key from the state machine

### Client Usage

Build the project and use the client:

```bash
dune build
```

#### Adding key-value pairs:
```bash
dune exec raft_client -- add <key> <value> -h <host> -p <port>
# OR use the built executable directly:
./_build/default/client/main.exe add <key> <value> -h <host> -p <port>
```

Example:
```bash
dune exec raft_client -- add name 42 -h 127.0.0.1 -p 7771
dune exec raft_client -- add score 100 -h 127.0.0.1 -p 7771
```

#### Getting values:
```bash
dune exec raft_client -- get <key> -h <host> -p <port>
# OR use the built executable directly:
./_build/default/client/main.exe get <key> -h <host> -p <port>
```

Example:
```bash
dune exec raft_client -- get name -h 127.0.0.1 -p 7771
```

#### Deleting keys:
```bash
dune exec raft_client -- delete <key> -h <host> -p <port>
# OR use the built executable directly:
./_build/default/client/main.exe delete <key> -h <host> -p <port>
```

Example:
```bash
dune exec raft_client -- delete name -h 127.0.0.1 -p 7771
```

### Quick Demo

Run the demo script to see all operations in action:

```bash
# Build first
dune build

# Run the demo
./demo.sh

# Or run the working demo that waits for leader election
./working_demo.sh
```

**Note**: The demo scripts use direct executable calls (not `dune exec`) to avoid lock conflicts and properly manage background processes. All background processes are automatically cleaned up when the scripts exit.

## How to test the cluster

### Single Node Testing
For simple testing, use the single node configuration:

```bash
# Build the project
dune build

# Start a single node
./_build/default/bin/main.exe -i "one" -o 7771 -f "./single_node.conf" &

# Wait for it to become leader, then use the client
./_build/default/client/main.exe add test 123 -h 127.0.0.1 -p 7771
```

### Multi-Node Cluster
Run servers from different terminals with their own cluster.conf files, and watch them negotiate who will be the leader:

```bash
# Terminal 1
dune exec raft -- -p 5555 -o 7771 -i "one" -f cluster.conf

# Terminal 2
dune exec raft -- -p 5556 -o 7772 -i "two" -f cluster2.conf

# Terminal 3
dune exec raft -- -p 5557 -o 7773 -i "three" -f cluster3.conf
```

## API Implementation Details

The client APIs work as follows:

1. **Write operations (add, delete)**: Must be sent to the current leader node only
2. **Read operations (get)**: Can be sent to any node (leader, follower, or candidate) for better performance
3. **Error handling**: If you send a write request to a follower, you'll get an error message indicating it's not the leader
4. **Consistency**: All write operations go through the Raft consensus protocol to ensure consistency
5. **Read performance**: Get operations read directly from any node's state machine, enabling load distribution
6. **Parallel execution**: Election requests and heartbeats are sent to all replicas concurrently using Eio for improved performance

### Client Protocol

The client communicates with the Raft cluster using the same RPC protocol as inter-node communication, with new message types:

- `Client_add (key, value)`: Add operation
- `Client_delete key`: Delete operation
- `Client_get key`: Get operation

Responses include success/error status and appropriate data.

### Important Notes

1. **Leader Election**: Single nodes need time to trigger elections and become leaders. If you see "I'm not the leader" errors for write operations, wait a few seconds and try again.

2. **Read-Anywhere Behavior**: Get operations work on any node regardless of leadership status. This allows for:
   - Better read performance and load distribution
   - Reduced load on the leader node
   - Continued read availability even during leader elections

3. **Write-to-Leader Requirement**: Add and delete operations only work on the leader to maintain consistency through the Raft consensus protocol.

4. **Parallel Communication**: The implementation uses Eio for concurrent operations:
   - Election requests are sent to all replicas simultaneously
   - Heartbeats are broadcast to all followers in parallel
   - This significantly improves cluster responsiveness and reduces latency

5. **Executable Usage**: Use `--` separator when using `dune exec` to pass arguments to the client, or call the built executables directly to avoid conflicts.

6. **Configuration Files**:
   - `single_node.conf`: For single-node testing (quorum=1)
   - `cluster.conf`, `cluster2.conf`, `cluster3.conf`: For multi-node testing
