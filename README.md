# Polkadot Telemetry Query Tool

Query Polkadot and Kusama public telemetry to retrieve validator/node location data.

## Important Limitations

**IP addresses are NOT exposed in the public telemetry feed.** The telemetry backend receives IPs from nodes, geolocates them internally, and only exposes location data to clients.

### Available Data
- Node names and versions
- Validator addresses (for validators)
- **Location: city, latitude, longitude**
- Operating system and architecture
- Peer counts and block heights

### NOT Available
- IP addresses
- ASN/datacenter provider information
- Network provider details

## Installation

```bash
npm install
```

## Usage

```bash
# Run the query tool
npm run dev

# Or build and run
npm run build
npm start
```

The tool will:
1. Connect to `wss://telemetry.polkadot.io/feed/`
2. Subscribe to Polkadot and Kusama networks
3. Collect node data for ~15 seconds per network
4. Generate location statistics
5. Export full data to `telemetry-data.json`

## Output

### Console Output
- Available chains and node counts
- Top locations by node count per network
- Aggregated city statistics across networks

### JSON Output (`telemetry-data.json`)
```json
{
  "generatedAt": "2025-01-01T00:00:00.000Z",
  "note": "IP addresses are not exposed...",
  "networks": {
    "Polkadot": {
      "summary": {
        "totalNodes": 1000,
        "totalValidators": 297,
        "uniqueCities": 150,
        "locatedNodes": 950
      },
      "locations": [...],
      "nodes": [...]
    },
    "Kusama": {...}
  }
}
```

## Getting Datacenter/ASN Information

Since the public telemetry doesn't expose IP addresses, to get datacenter/ASN information you would need:

1. **Direct RPC Access**: Query nodes directly via their RPC endpoints to get peer information
2. **P2P Network Discovery**: Connect to the P2P network and collect peer addresses
3. **Telemetry Backend Access**: Access the backend database directly
4. **Alternative Data Sources**: Use services that track Polkadot/Kusama node IPs

### Alternative Approaches

1. **Polkadot.js API**: Connect to nodes and query `system_networkState()` to get peer IPs
2. **Substrate Network Crawler**: Build a crawler that connects to the P2P network
3. **Public Node Lists**: Some community-maintained lists include IP data

## Customization

### Change Collection Time

Edit `COLLECTION_TIME` in `src/index.ts`:

```typescript
const COLLECTION_TIME = 30000; // 30 seconds
```

### Query Different Networks

Edit the `NETWORKS` array:

```typescript
const NETWORKS = ['Polkadot', 'Kusama', 'Westend'];
```

## Project Structure

```
├── src/
│   ├── index.ts              # Main entry point
│   ├── telemetry-client.ts   # WebSocket client
│   └── types.ts              # TypeScript types
├── package.json
├── tsconfig.json
└── README.md
```

## Telemetry Feed Protocol

The tool connects to the public telemetry WebSocket feed at `wss://telemetry.polkadot.io/feed/`.

### Message Format
Messages are JSON arrays with alternating action codes and payloads:
```json
[action1, payload1, action2, payload2, ...]
```

### Key Actions
- `AddedNode (3)`: New node with details, stats, location
- `LocatedNode (5)`: Location update: `[id, lat, lng, city]`
- `RemovedNode (4)`: Node disconnected
- `AddedChain (11)`: New chain available
- `SubscribedTo (13)`: Subscription confirmed

## License

MIT
