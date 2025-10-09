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
    
    // NEW FUNCTION: Start Dispute Investigation
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
    
    // Core Function 3: Resolve Dispute
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
        
        dispute.status = DisputeStatus.Resolved;
        dispute.resolvedAt = block.timestamp;
        dispute.winner = _winner;
        
        // Transfer dispute amount to winner
        payable(_winner).transfer(dispute.amount);
        
        // Transfer arbitration fee to arbitrator
        payable(dispute.arbitrator).transfer(arbitrationFee);
        
        emit DisputeResolved(_disputeId, _winner, dispute.amount);
    }
    
    // Function: Cancel Dispute
    function cancelDispute(uint256 _disputeId) 
        external 
        disputeExists(_disputeId) 
    {
        Dispute storage dispute = disputes[_disputeId];
        
        // Only plaintiff can cancel if no arbitrator assigned yet
        // Both parties can cancel if arbitrator is assigned but dispute hasn't started
        require(
            (dispute.status == DisputeStatus.Created && msg.sender == dispute.plaintiff) ||
            (dispute.status == DisputeStatus.ArbitratorAssigned && 
             (msg.sender == dispute.plaintiff || msg.sender == dispute.defendant)),
            "Not authorized to cancel or dispute cannot be cancelled"
        );
        
        dispute.status = DisputeStatus.Cancelled;
        dispute.resolvedAt = block.timestamp;
        
        uint256 refundAmount;
        address refundRecipient;
        
        if (dispute.status == DisputeStatus.Created) {
            // If no arbitrator assigned, refund everything to plaintiff
            refundAmount = dispute.amount + arbitrationFee;
            refundRecipient = dispute.plaintiff;
        } else {
            // If arbitrator assigned, refund dispute amount to plaintiff
            // and pay arbitration fee to arbitrator for their time
            refundAmount = dispute.amount;
            refundRecipient = dispute.plaintiff;
            
            // Pay arbitrator for their time
            payable(dispute.arbitrator).transfer(arbitrationFee);
        }
        
        // Refund the dispute amount
        payable(refundRecipient).transfer(refundAmount);
        
        emit DisputeCancelled(_disputeId, msg.sender, refundAmount);
    }
    
    // Additional utility functions
    function authorizeArbitrator(address _arbitrator) external onlyOwner {
        require(_arbitrator != address(0), "Invalid arbitrator address");
        authorizedArbitrators[_arbitrator] = true;
        emit ArbitratorAuthorized(_arbitrator);
    }
    
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
    
    // Emergency function to update arbitration fee
    function updateArbitrationFee(uint256 _newFee) external onlyOwner {
        arbitrationFee = _newFee;
    }
    
    // Function to withdraw contract balance (only owner)
    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
