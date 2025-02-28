export function getEnv(name: string, def?: any): string {
    if (process.env.hasOwnProperty(name)) {
        return process.env[name] as string;
    };
    if (def) {
        return def;
    }
    throw new Error(`Required environment variable "${name}" not set`)
}

export function sleep(ms: number) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Checks if the current network is Base Sepolia and verification should be skipped
 * @param networkName The name of the network from hardhat arguments
 * @returns True if verification should be skipped, false otherwise
 */
export function shouldSkipVerification(networkName?: string): boolean {
    if (!networkName) return false;
    
    const network = networkName.toString().toLowerCase();
    return network.includes('basesepolia') || network.includes('base-sepolia');
}
