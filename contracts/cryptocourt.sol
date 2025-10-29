// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract CryptoCourt {
    // Struct to represent a dispute
    struct Dispute {
        uint256 id;
        address plaintiff;
        address defendant;
        address arbitrator;
        string description;
        uint256 amount;
        DisputeStatus status;
        uint256 createdAt;
        uint256 resolvedAt;
        address winner;
    }
   enum DisputeStatus {
        Created,
        ArbitratorAssigned,
        InProgress,
        Resolved,
        Cancelled
    }
    
    
    // State variables
    mapping(uint256 => Dispute) public disputes;
    mapping(address => bool) public authorizedArbitrators;
    uint256 public disputeCounter;
    uint256 public arbitrationFee = 0.01 ether;
    address public owner;
    
    // Events
    event DisputeCreated(uint256 indexed disputeId, address indexed plaintiff, address indexed defendant, uint256 amount);
    event ArbitratorAssigned(uint256 indexed disputeId, address indexed arbitrator);
    event DisputeInProgress(uint256 indexed disputeId, uint256 timestamp);
    event DisputeResolved(uint256 indexed disputeId, address indexed winner, uint256 amount);
    event DisputeCancelled(uint256 indexed disputeId, address indexed cancelledBy, uint256 refundAmount);
    event ArbitratorAuthorized(address indexed arbitrator);
    event ArbitratorRevoked(address indexed arbitrator);
    event ArbitrationFeeUpdated(uint256 oldFee, uint256 newFee);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    
    // Modifiers
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyAuthorizedArbitrator() {
        require(authorizedArbitrators[msg.sender], "Only authorized arbitrators can call this function");
        _;
    }
    
    modifier disputeExists(uint256 _disputeId) {
        require(_disputeId < disputeCounter, "Dispute does not exist");
        _;
    }
    
    constructor() {
        owner = msg.sender;
        disputeCounter = 0;
    }
    
    // Core Function 1: Create Dispute
    function createDispute(
        address _defendant,
        string memory _description
    ) external payable returns (uint256) {
        require(_defendant != address(0), "Invalid defendant address");
        require(_defendant != msg.sender, "Cannot create dispute with yourself");
        require(msg.value > arbitrationFee, "Must send more than arbitration fee");
        require(bytes(_description).length > 0, "Description cannot be empty");
        require(bytes(_description).length <= 1000, "Description too long");
        
        uint256 disputeId = disputeCounter;
        uint256 disputeAmount = msg.value - arbitrationFee;
        
        disputes[disputeId] = Dispute({
            id: disputeId,
            plaintiff: msg.sender,
            defendant: _defendant,
            arbitrator: address(0),
            description: _description,
            amount: disputeAmount,
            status: DisputeStatus.Created,
            createdAt: block.timestamp,
            resolvedAt: 0,
            winner: address(0)
        });
        
        disputeCounter++;
        
        emit DisputeCreated(disputeId, msg.sender, _defendant, disputeAmount);
        return disputeId;
    }
    
    // Core Function 2: Assign Arbitrator
    function assignArbitrator(uint256 _disputeId, address _arbitrator) 
        external 
        onlyOwner 
        disputeExists(_disputeId) 
    {
        require(authorizedArbitrators[_arbitrator], "Arbitrator not authorized");
        require(disputes[_disputeId].status == DisputeStatus.Created, "Dispute not in created status");
        require(_arbitrator != disputes[_disputeId].plaintiff && _arbitrator != disputes[_disputeId].defendant, 
                "Arbitrator cannot be involved party");
        
        disputes[_disputeId].arbitrator = _arbitrator;
        disputes[_disputeId].status = DisputeStatus.ArbitratorAssigned;
        
        emit ArbitratorAssigned(_disputeId, _arbitrator);
    }
    
    // Start Dispute Investigation
    function startDisputeInvestigation(uint256 _disputeId) 
        external 
        onlyAuthorizedArbitrator
        disputeExists(_disputeId) 
    {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.arbitrator == msg.sender, "Only assigned arbitrator can start investigation");
        require(dispute.status == DisputeStatus.ArbitratorAssigned, "Dispute must be in ArbitratorAssigned status");
        
        dispute.status = DisputeStatus.InProgress;
        
        emit DisputeInProgress(_disputeId, block.timestamp);
    }
    
    // Core Function 3: Resolve Dispute (FIXED - Reentrancy Protection)
    function resolveDispute(uint256 _disputeId, address _winner) 
        external 
        onlyAuthorizedArbitrator 
        disputeExists(_disputeId) 
    {
        Dispute storage dispute = disputes[_disputeId];
        require(dispute.arbitrator == msg.sender, "Only assigned arbitrator can resolve");
        require(dispute.status == DisputeStatus.ArbitratorAssigned || dispute.status == DisputeStatus.InProgress, 
                "Invalid dispute status");
        require(_winner == dispute.plaintiff || _winner == dispute.defendant, "Winner must be involved party");
        
        // Update state BEFORE transfers (Checks-Effects-Interactions pattern)
        dispute.status = DisputeStatus.Resolved;
        dispute.resolvedAt = block.timestamp;
        dispute.winner = _winner;
        
        uint256 amountToWinner = dispute.amount;
        uint256 feeToArbitrator = arbitrationFee;
        
        emit DisputeResolved(_disputeId, _winner, amountToWinner);
        
        // Transfer funds AFTER state changes
        (bool successWinner, ) = payable(_winner).call{value: amountToWinner}("");
        require(successWinner, "Transfer to winner failed");
        
        (bool successArbitrator, ) = payable(dispute.arbitrator).call{value: feeToArbitrator}("");
        require(successArbitrator, "Transfer to arbitrator failed");
    }
    
    // Cancel Dispute (FIXED - Reentrancy Protection)
    function cancelDispute(uint256 _disputeId) 
        external 
        disputeExists(_disputeId) 
    {
        Dispute storage dispute = disputes[_disputeId];
        DisputeStatus currentStatus = dispute.status;
        
        // Check authorization based on current status
        require(
            (currentStatus == DisputeStatus.Created && msg.sender == dispute.plaintiff) ||
            (currentStatus == DisputeStatus.ArbitratorAssigned && 
             (msg.sender == dispute.plaintiff || msg.sender == dispute.defendant)),
            "Not authorized to cancel or dispute cannot be cancelled"
        );
        
        // Calculate refunds before state changes
        uint256 refundAmount;
        address refundRecipient;
        uint256 arbitratorFee = 0;
        address arbitratorAddress = address(0);
        
        if (currentStatus == DisputeStatus.Created) {
            refundAmount = dispute.amount + arbitrationFee;
            refundRecipient = dispute.plaintiff;
        } else {
            refundAmount = dispute.amount;
            refundRecipient = dispute.plaintiff;
            arbitratorFee = arbitrationFee;
            arbitratorAddress = dispute.arbitrator;
        }
        
        // Update state BEFORE transfers
        dispute.status = DisputeStatus.Cancelled;
        dispute.resolvedAt = block.timestamp;
        
        emit DisputeCancelled(_disputeId, msg.sender, refundAmount);
        
        // Perform transfers AFTER state changes
        (bool successRefund, ) = payable(refundRecipient).call{value: refundAmount}("");
        require(successRefund, "Refund transfer failed");
        
        if (arbitratorFee > 0 && arbitratorAddress != address(0)) {
            (bool successArbitrator, ) = payable(arbitratorAddress).call{value: arbitratorFee}("");
            require(successArbitrator, "Arbitrator fee transfer failed");
        }
    }
    
    // Authorize Arbitrator
    function authorizeArbitrator(address _arbitrator) external onlyOwner {
        require(_arbitrator != address(0), "Invalid arbitrator address");
        require(!authorizedArbitrators[_arbitrator], "Arbitrator already authorized");
        authorizedArbitrators[_arbitrator] = true;
        emit ArbitratorAuthorized(_arbitrator);
    }
    
    // Revoke Arbitrator (NEW)
    function revokeArbitrator(address _arbitrator) external onlyOwner {
        require(_arbitrator != address(0), "Invalid arbitrator address");
        require(authorizedArbitrators[_arbitrator], "Arbitrator not authorized");
        authorizedArbitrators[_arbitrator] = false;
        emit ArbitratorRevoked(_arbitrator);
    }
    
    // View Functions
    function getDispute(uint256 _disputeId) 
        external 
        view 
        disputeExists(_disputeId) 
        returns (Dispute memory) 
    {
        return disputes[_disputeId];
    }
    
    function getDisputeCount() external view returns (uint256) {
        return disputeCounter;
    }
    
    function isAuthorizedArbitrator(address _arbitrator) external view returns (bool) {
        return authorizedArbitrators[_arbitrator];
    }
    
    // Update Arbitration Fee
    function updateArbitrationFee(uint256 _newFee) external onlyOwner {
        require(_newFee > 0, "Fee must be greater than zero");
        require(_newFee != arbitrationFee, "New fee must be different");
        uint256 oldFee = arbitrationFee;
        arbitrationFee = _newFee;
        emit ArbitrationFeeUpdated(oldFee, _newFee);
    }
    
    // Transfer Ownership (NEW)
    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "Invalid new owner address");
        require(_newOwner != owner, "Already the owner");
        address previousOwner = owner;
        owner = _newOwner;
        emit OwnershipTransferred(previousOwner, _newOwner);
    }
    
    // REMOVED: withdraw() function - This was dangerous as it could drain funds 
    // that belong to active disputes. Funds should only be transferred through 
    // the proper dispute resolution mechanisms.
    
    // Emergency function to check contract balance
    function getContractBalance() external view returns (uint256) {
        return address(this).balance;
    }
}
