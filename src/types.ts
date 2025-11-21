// Telemetry Feed Message Actions
export enum FeedAction {
  FeedVersion = 0,
  BestBlock = 1,
  BestFinalized = 2,
  AddedNode = 3,
  RemovedNode = 4,
  LocatedNode = 5,
  ImportedBlock = 6,
  FinalizedBlock = 7,
  NodeStats = 8,
  NodeHardware = 9,
  TimeSync = 10,
  AddedChain = 11,
  RemovedChain = 12,
  SubscribedTo = 13,
  UnsubscribedFrom = 14,
  Pong = 15,
  AfgFinalized = 16,
  AfgReceivedPrevote = 17,
  AfgReceivedPrecommit = 18,
  AfgAuthoritySet = 19,
  StaleNode = 20,
  NodeIO = 21,
  ChainStatsUpdate = 22,
  TelemetryInfo = 23,
}

// Node location data
export interface NodeLocation {
  latitude: number;
  longitude: number;
  city: string;
}

// Node details from AddedNode message
export interface NodeDetails {
  name: string;
  implementation: string;
  version: string;
  address?: string;
  networkId?: string;
  operatingSystem?: string;
  cpuArchitecture?: string;
  targetEnv?: string;
  sysInfo?: NodeSysInfo;
}

export interface NodeSysInfo {
  cpu?: string;
  memory?: number;
  coreCount?: number;
  linuxKernel?: string;
  linuxDistro?: string;
  isVirtualMachine?: boolean;
}

// Node stats
export interface NodeStats {
  peers: number;
  txCount: number;
}

// Node IO stats
export interface NodeIO {
  stateCacheSize: number[];
}

// Hardware info
export interface NodeHardware {
  upload: number[];
  download: number[];
  chartStamps: number[];
}

// Block details
export interface BlockDetails {
  height: number;
  hash: string;
  blockTime: number;
  blockTimestamp: number;
  propagationTime?: number;
}

// Complete node information
export interface TelemetryNode {
  id: number;
  details: NodeDetails;
  stats: NodeStats;
  io?: NodeIO;
  hardware?: NodeHardware;
  block?: BlockDetails;
  location?: NodeLocation;
  startupTime?: number;
  isValidator?: boolean;
}

// Chain information
export interface Chain {
  name: string;
  genesisHash: string;
  nodeCount: number;
}

// Aggregated location data
export interface LocationStats {
  city: string;
  latitude: number;
  longitude: number;
  nodeCount: number;
  validatorCount: number;
  nodes: string[];
}

// Network summary
export interface NetworkSummary {
  networkName: string;
  totalNodes: number;
  totalValidators: number;
  locations: LocationStats[];
  uniqueCities: number;
  uniqueCountries: number;
}
