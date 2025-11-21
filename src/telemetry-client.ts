import WebSocket from 'ws';
import {
  FeedAction,
  TelemetryNode,
  NodeDetails,
  NodeStats,
  NodeLocation,
  NodeIO,
  NodeHardware,
  BlockDetails,
  Chain,
  LocationStats,
  NetworkSummary,
} from './types.js';

const TELEMETRY_URL = 'wss://telemetry.polkadot.io/feed/';

export class TelemetryClient {
  private ws: WebSocket | null = null;
  private nodes: Map<number, TelemetryNode> = new Map();
  private chains: Map<string, Chain> = new Map();
  private currentChain: string | null = null;
  private messageCount = 0;
  private onDataCallback?: (data: { nodes: Map<number, TelemetryNode>; chains: Map<string, Chain> }) => void;

  constructor() {}

  async connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(TELEMETRY_URL);

      this.ws.on('open', () => {
        console.log('Connected to Polkadot telemetry');
        resolve();
      });

      this.ws.on('message', (data: Buffer) => {
        this.handleMessage(data);
      });

      this.ws.on('error', (error) => {
        console.error('WebSocket error:', error);
        reject(error);
      });

      this.ws.on('close', () => {
        console.log('Disconnected from telemetry');
      });
    });
  }

  private handleMessage(data: Buffer): void {
    try {
      const message = JSON.parse(data.toString());

      if (!Array.isArray(message)) {
        return;
      }

      // Messages come as alternating [action, payload, action, payload, ...]
      for (let i = 0; i < message.length; i += 2) {
        const action = message[i] as FeedAction;
        const payload = message[i + 1];
        this.processAction(action, payload);
      }

      this.messageCount++;

      if (this.onDataCallback && this.messageCount % 10 === 0) {
        this.onDataCallback({ nodes: this.nodes, chains: this.chains });
      }
    } catch (error) {
      // Silently ignore parse errors for malformed messages
    }
  }

  private processAction(action: FeedAction, payload: any): void {
    switch (action) {
      case FeedAction.AddedChain:
        this.handleAddedChain(payload);
        break;
      case FeedAction.RemovedChain:
        this.handleRemovedChain(payload);
        break;
      case FeedAction.AddedNode:
        this.handleAddedNode(payload);
        break;
      case FeedAction.RemovedNode:
        this.handleRemovedNode(payload);
        break;
      case FeedAction.LocatedNode:
        this.handleLocatedNode(payload);
        break;
      case FeedAction.NodeStats:
        this.handleNodeStats(payload);
        break;
      case FeedAction.StaleNode:
        this.handleStaleNode(payload);
        break;
      case FeedAction.SubscribedTo:
        this.handleSubscribedTo(payload);
        break;
      // Ignore other message types
    }
  }

  private handleAddedChain(payload: any): void {
    if (!Array.isArray(payload) || payload.length < 2) return;

    const [name, genesisHash, nodeCount] = payload;
    this.chains.set(name, {
      name,
      genesisHash: genesisHash || '',
      nodeCount: nodeCount || 0,
    });
  }

  private handleRemovedChain(payload: any): void {
    if (typeof payload === 'string') {
      this.chains.delete(payload);
    }
  }

  private handleSubscribedTo(payload: any): void {
    if (typeof payload === 'string') {
      this.currentChain = payload;
      this.nodes.clear(); // Clear nodes when switching chains
    }
  }

  private handleAddedNode(payload: any): void {
    if (!Array.isArray(payload) || payload.length < 2) return;

    const [
      id,
      nodeDetailsArray,
      nodeStatsArray,
      nodeIOArray,
      nodeHardwareArray,
      blockDetailsArray,
      locationArray,
      startupTime,
    ] = payload;

    const details = this.parseNodeDetails(nodeDetailsArray);
    const stats = this.parseNodeStats(nodeStatsArray);
    const io = this.parseNodeIO(nodeIOArray);
    const hardware = this.parseNodeHardware(nodeHardwareArray);
    const block = this.parseBlockDetails(blockDetailsArray);
    const location = this.parseLocation(locationArray);

    const node: TelemetryNode = {
      id,
      details,
      stats,
      io,
      hardware,
      block,
      location,
      startupTime,
      // A node is likely a validator if it has a validator address
      isValidator: !!details.address,
    };

    this.nodes.set(id, node);
  }

  private handleRemovedNode(payload: any): void {
    if (typeof payload === 'number') {
      this.nodes.delete(payload);
    }
  }

  private handleLocatedNode(payload: any): void {
    if (!Array.isArray(payload) || payload.length < 4) return;

    const [id, latitude, longitude, city] = payload;
    const node = this.nodes.get(id);

    if (node) {
      node.location = {
        latitude,
        longitude,
        city: city || 'Unknown',
      };
    }
  }

  private handleNodeStats(payload: any): void {
    if (!Array.isArray(payload) || payload.length < 3) return;

    const [id, peers, txCount] = payload;
    const node = this.nodes.get(id);

    if (node) {
      node.stats = { peers, txCount };
    }
  }

  private handleStaleNode(payload: any): void {
    // Stale nodes are nodes that haven't sent data recently
    // We keep them but could mark them as stale if needed
  }

  private parseNodeDetails(data: any): NodeDetails {
    if (!Array.isArray(data)) {
      return { name: 'Unknown', implementation: '', version: '' };
    }

    const [
      name,
      implementation,
      version,
      address,
      networkId,
      operatingSystem,
      cpuArchitecture,
      targetEnv,
      _unknown,
      sysInfoArray,
    ] = data;

    return {
      name: name || 'Unknown',
      implementation: implementation || '',
      version: version || '',
      address: address || undefined,
      networkId: networkId || undefined,
      operatingSystem: operatingSystem || undefined,
      cpuArchitecture: cpuArchitecture || undefined,
      targetEnv: targetEnv || undefined,
      sysInfo: this.parseSysInfo(sysInfoArray),
    };
  }

  private parseSysInfo(data: any): any {
    if (!Array.isArray(data)) return undefined;

    const [cpu, memory, coreCount, linuxKernel, linuxDistro, isVirtualMachine] = data;
    return {
      cpu,
      memory,
      coreCount,
      linuxKernel,
      linuxDistro,
      isVirtualMachine,
    };
  }

  private parseNodeStats(data: any): NodeStats {
    if (!Array.isArray(data)) {
      return { peers: 0, txCount: 0 };
    }

    const [peers, txCount] = data;
    return { peers: peers || 0, txCount: txCount || 0 };
  }

  private parseNodeIO(data: any): NodeIO | undefined {
    if (!Array.isArray(data)) return undefined;
    return { stateCacheSize: data };
  }

  private parseNodeHardware(data: any): NodeHardware | undefined {
    if (!Array.isArray(data) || data.length < 3) return undefined;
    const [upload, download, chartStamps] = data;
    return { upload, download, chartStamps };
  }

  private parseBlockDetails(data: any): BlockDetails | undefined {
    if (!Array.isArray(data) || data.length < 4) return undefined;

    const [height, hash, blockTime, blockTimestamp, propagationTime] = data;
    return {
      height,
      hash,
      blockTime,
      blockTimestamp,
      propagationTime,
    };
  }

  private parseLocation(data: any): NodeLocation | undefined {
    if (!Array.isArray(data) || data.length < 3) return undefined;

    const [latitude, longitude, city] = data;
    if (latitude === null || longitude === null) return undefined;

    return {
      latitude,
      longitude,
      city: city || 'Unknown',
    };
  }

  // Subscribe to a specific chain
  subscribe(chainName: string): void {
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(`subscribe:${chainName}`);
      this.currentChain = chainName;
      this.nodes.clear();
      console.log(`Subscribed to ${chainName}`);
    }
  }

  // Get available chains
  getChains(): Chain[] {
    return Array.from(this.chains.values());
  }

  // Get all nodes for current subscription
  getNodes(): TelemetryNode[] {
    return Array.from(this.nodes.values());
  }

  // Get validators only
  getValidators(): TelemetryNode[] {
    return Array.from(this.nodes.values()).filter(node => node.isValidator);
  }

  // Get nodes with location data
  getLocatedNodes(): TelemetryNode[] {
    return Array.from(this.nodes.values()).filter(node => node.location);
  }

  // Aggregate locations
  getLocationStats(): LocationStats[] {
    const locationMap = new Map<string, LocationStats>();

    for (const node of this.nodes.values()) {
      if (!node.location) continue;

      const key = `${node.location.latitude.toFixed(2)},${node.location.longitude.toFixed(2)}`;

      if (!locationMap.has(key)) {
        locationMap.set(key, {
          city: node.location.city,
          latitude: node.location.latitude,
          longitude: node.location.longitude,
          nodeCount: 0,
          validatorCount: 0,
          nodes: [],
        });
      }

      const stats = locationMap.get(key)!;
      stats.nodeCount++;
      if (node.isValidator) {
        stats.validatorCount++;
      }
      stats.nodes.push(node.details.name);
    }

    return Array.from(locationMap.values())
      .sort((a, b) => b.nodeCount - a.nodeCount);
  }

  // Get network summary
  getNetworkSummary(): NetworkSummary {
    const locations = this.getLocationStats();
    const uniqueCities = new Set(locations.map(l => l.city)).size;

    return {
      networkName: this.currentChain || 'Unknown',
      totalNodes: this.nodes.size,
      totalValidators: this.getValidators().length,
      locations,
      uniqueCities,
      uniqueCountries: 0, // Would need country data to calculate
    };
  }

  // Set callback for data updates
  onData(callback: (data: { nodes: Map<number, TelemetryNode>; chains: Map<string, Chain> }) => void): void {
    this.onDataCallback = callback;
  }

  // Close connection
  close(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  // Get current state
  getState(): { nodes: Map<number, TelemetryNode>; chains: Map<string, Chain> } {
    return { nodes: this.nodes, chains: this.chains };
  }
}
