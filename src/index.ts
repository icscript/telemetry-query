import { TelemetryClient } from './telemetry-client.js';
import { NetworkSummary, LocationStats, TelemetryNode } from './types.js';

// Networks to query
const NETWORKS = ['Polkadot', 'Kusama'];

// Time to wait for data collection per network (in ms)
const COLLECTION_TIME = 15000; // 15 seconds

interface NetworkData {
  summary: NetworkSummary;
  nodes: TelemetryNode[];
}

async function collectNetworkData(client: TelemetryClient, networkName: string): Promise<NetworkData> {
  return new Promise((resolve) => {
    console.log(`\nSubscribing to ${networkName}...`);
    client.subscribe(networkName);

    // Wait for data to accumulate
    setTimeout(() => {
      const summary = client.getNetworkSummary();
      const nodes = client.getNodes();
      console.log(`Collected ${nodes.length} nodes from ${networkName}`);
      resolve({ summary, nodes });
    }, COLLECTION_TIME);
  });
}

function printLocationReport(summary: NetworkSummary): void {
  console.log(`\n${'='.repeat(60)}`);
  console.log(`NETWORK: ${summary.networkName}`);
  console.log(`${'='.repeat(60)}`);
  console.log(`Total Nodes: ${summary.totalNodes}`);
  console.log(`Total Validators: ${summary.totalValidators}`);
  console.log(`Unique Cities: ${summary.uniqueCities}`);
  console.log(`Nodes with Location: ${summary.locations.reduce((acc, l) => acc + l.nodeCount, 0)}`);

  console.log(`\nTop Locations by Node Count:`);
  console.log(`${'─'.repeat(60)}`);
  console.log(`${'City'.padEnd(30)} ${'Nodes'.padStart(8)} ${'Validators'.padStart(12)}`);
  console.log(`${'─'.repeat(60)}`);

  const topLocations = summary.locations.slice(0, 30);
  for (const loc of topLocations) {
    const city = loc.city.substring(0, 28).padEnd(30);
    const nodes = loc.nodeCount.toString().padStart(8);
    const validators = loc.validatorCount.toString().padStart(12);
    console.log(`${city} ${nodes} ${validators}`);
  }
}

function generateLocationListJSON(networkName: string, locations: LocationStats[]): object {
  return {
    network: networkName,
    generatedAt: new Date().toISOString(),
    totalLocations: locations.length,
    locations: locations.map(loc => ({
      city: loc.city,
      latitude: loc.latitude,
      longitude: loc.longitude,
      nodeCount: loc.nodeCount,
      validatorCount: loc.validatorCount,
      coordinates: `${loc.latitude.toFixed(4)}, ${loc.longitude.toFixed(4)}`,
    })),
  };
}

function generateNodeListJSON(networkName: string, nodes: TelemetryNode[]): object {
  return {
    network: networkName,
    generatedAt: new Date().toISOString(),
    totalNodes: nodes.length,
    nodes: nodes.map(node => ({
      name: node.details.name,
      implementation: node.details.implementation,
      version: node.details.version,
      isValidator: node.isValidator,
      validatorAddress: node.details.address || null,
      operatingSystem: node.details.operatingSystem || null,
      cpuArchitecture: node.details.cpuArchitecture || null,
      location: node.location ? {
        city: node.location.city,
        latitude: node.location.latitude,
        longitude: node.location.longitude,
      } : null,
      peers: node.stats.peers,
      blockHeight: node.block?.height || null,
    })),
  };
}

async function main(): Promise<void> {
  console.log('Polkadot/Kusama Telemetry Query Tool');
  console.log('====================================');
  console.log('\nNote: IP addresses are NOT exposed in the public telemetry feed.');
  console.log('Location data (city, lat/lng) is available but is geolocated by the backend.');
  console.log('For datacenter/ASN information, you would need direct access to node IPs.\n');

  const client = new TelemetryClient();

  try {
    await client.connect();

    // Wait a moment for initial chain list
    await new Promise(resolve => setTimeout(resolve, 2000));

    // Show available chains
    const chains = client.getChains();
    console.log(`\nAvailable chains (${chains.length} total):`);
    const mainChains = chains.filter(c =>
      c.name === 'Polkadot' ||
      c.name === 'Kusama' ||
      c.nodeCount > 100
    ).sort((a, b) => b.nodeCount - a.nodeCount);

    for (const chain of mainChains.slice(0, 10)) {
      console.log(`  - ${chain.name}: ${chain.nodeCount} nodes`);
    }

    // Collect data for each network
    const results: Record<string, NetworkData> = {};

    for (const network of NETWORKS) {
      const data = await collectNetworkData(client, network);
      results[network] = data;
      printLocationReport(data.summary);
    }

    // Generate JSON output files
    console.log('\n\nGenerating JSON output files...');

    const output = {
      generatedAt: new Date().toISOString(),
      note: 'IP addresses are not exposed in public telemetry. Only location data is available.',
      networks: {} as Record<string, any>,
    };

    for (const [networkName, data] of Object.entries(results)) {
      output.networks[networkName] = {
        summary: {
          totalNodes: data.summary.totalNodes,
          totalValidators: data.summary.totalValidators,
          uniqueCities: data.summary.uniqueCities,
          locatedNodes: data.summary.locations.reduce((acc, l) => acc + l.nodeCount, 0),
        },
        locations: generateLocationListJSON(networkName, data.summary.locations),
        nodes: generateNodeListJSON(networkName, data.nodes),
      };
    }

    // Print aggregated city statistics across networks
    console.log('\n\nAGGREGATED CITY STATISTICS ACROSS ALL NETWORKS');
    console.log('='.repeat(60));

    const cityAggregation = new Map<string, { polkadot: number; kusama: number; total: number }>();

    for (const [networkName, data] of Object.entries(results)) {
      for (const loc of data.summary.locations) {
        const city = loc.city;
        if (!cityAggregation.has(city)) {
          cityAggregation.set(city, { polkadot: 0, kusama: 0, total: 0 });
        }
        const stats = cityAggregation.get(city)!;
        if (networkName === 'Polkadot') {
          stats.polkadot += loc.nodeCount;
        } else {
          stats.kusama += loc.nodeCount;
        }
        stats.total += loc.nodeCount;
      }
    }

    const sortedCities = Array.from(cityAggregation.entries())
      .sort((a, b) => b[1].total - a[1].total)
      .slice(0, 30);

    console.log(`\n${'City'.padEnd(25)} ${'Polkadot'.padStart(10)} ${'Kusama'.padStart(10)} ${'Total'.padStart(10)}`);
    console.log('─'.repeat(55));

    for (const [city, stats] of sortedCities) {
      console.log(
        `${city.substring(0, 23).padEnd(25)} ` +
        `${stats.polkadot.toString().padStart(10)} ` +
        `${stats.kusama.toString().padStart(10)} ` +
        `${stats.total.toString().padStart(10)}`
      );
    }

    // Output full JSON to file
    const outputJSON = JSON.stringify(output, null, 2);
    const fs = await import('fs');
    fs.writeFileSync('telemetry-data.json', outputJSON);
    console.log('\n\nFull data exported to: telemetry-data.json');

    // Summary about limitations
    console.log('\n\n' + '='.repeat(60));
    console.log('IMPORTANT LIMITATIONS');
    console.log('='.repeat(60));
    console.log(`
The public telemetry feed does NOT expose:
  - IP addresses (IPs are geolocated server-side)
  - ASN/datacenter provider information
  - Network provider details

Available data:
  - Node names and versions
  - Validator addresses (for validators)
  - Location (city, latitude, longitude)
  - Operating system and architecture
  - Peer counts and block heights

To get datacenter/ASN information, you would need:
  1. Direct access to node RPC endpoints to query peer info
  2. Access to the telemetry backend database
  3. A separate service that maps node identities to IPs
`);

    client.close();

  } catch (error) {
    console.error('Error:', error);
    client.close();
    process.exit(1);
  }
}

main().catch(console.error);
