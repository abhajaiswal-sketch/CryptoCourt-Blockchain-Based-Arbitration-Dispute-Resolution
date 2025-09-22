// CryptoCourt Frontend JavaScript with Ethers.js Integration

// Contract Configuration
const CONTRACT_ADDRESS = "0x..."; // Replace with your deployed contract address
const CONTRACT_ABI = [
    "function createDispute(address _defendant, string memory _description) external payable returns (uint256)",
    "function assignArbitrator(uint256 _disputeId, address _arbitrator) external",
    "function resolveDispute(uint256 _disputeId, address _winner) external",
    "function authorizeArbitrator(address _arbitrator) external",
    "function getDispute(uint256 _disputeId) external view returns (tuple(uint256 id, address plaintiff, address defendant, address arbitrator, string description, uint256 amount, uint8 status, uint256 createdAt, uint256 resolvedAt, address winner))",
    "function getDisputeCount() external view returns (uint256)",
    "function isAuthorizedArbitrator(address _arbitrator) external view returns (bool)",
    "function arbitrationFee() external view returns (uint256)",
    "function owner() external view returns (address)",
    "event DisputeCreated(uint256 indexed disputeId, address indexed plaintiff, address indexed defendant, uint256 amount)",
    "event ArbitratorAssigned(uint256 indexed disputeId, address indexed arbitrator)",
    "event DisputeResolved(uint256 indexed disputeId, address indexed winner, uint256 amount)"
];

// Global Variables
let provider;
let signer;
let contract;
let userAddress;

// Status enum mapping
const DisputeStatus = {
    0: 'Created',
    1: 'Arbitrator Assigned',
    2: 'In Progress',
    3: 'Resolved',
    4: 'Cancelled'
};

// Initialize App
document.addEventListener('DOMContentLoaded', async () => {
    setupEventListeners();
    await checkWalletConnection();
});

// Setup Event Listeners
function setupEventListeners() {
