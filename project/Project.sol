// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

contract GigWorkerAdvances {
    struct Advance {
        uint256 id;
        address worker;
        address employer;
        uint256 advanceAmount;
        uint256 fullJobAmount;
        uint256 dueDate;
        bool isRepaid;
        bool isJobConfirmed;
        string jobDescription;
    }
    
    mapping(uint256 => Advance) public advances;
    mapping(address => uint256[]) public workerAdvances;
    mapping(address => uint256[]) public employerAdvances;
    mapping(address => uint256) public workerRatings; // Simple rating system
    
    uint256 private nextAdvanceId = 1;
    uint256 public constant ADVANCE_FEE_PERCENT = 5; // 5% fee on advances
    address public owner;
    uint256 public totalFeesCollected;
    
    event AdvanceRequested(uint256 indexed advanceId, address indexed worker, address indexed employer, uint256 amount);
    event AdvanceApproved(uint256 indexed advanceId, uint256 amount);
    event AdvanceRepaid(uint256 indexed advanceId, uint256 amount);
    event JobConfirmed(uint256 indexed advanceId);
    
    modifier onlyOwner() {
        require(msg.sender == owner, "Only owner can call this function");
        _;
    }
    
    modifier onlyEmployer(uint256 _advanceId) {
        require(msg.sender == advances[_advanceId].employer, "Only employer can call this function");
        _;
    }
    
    modifier onlyWorker(uint256 _advanceId) {
        require(msg.sender == advances[_advanceId].worker, "Only worker can call this function");
        _;
    }
    
    constructor() {
        owner = msg.sender;
    }
    
    // Function 1: Request advance against future work
    function requestAdvance(
        address _employer,
        uint256 _advanceAmount,
        uint256 _fullJobAmount,
        uint256 _jobDurationDays,
        string memory _jobDescription
    ) external {
        require(_advanceAmount > 0, "Advance amount must be greater than 0");
        require(_fullJobAmount > _advanceAmount, "Full job amount must be greater than advance");
        require(_jobDurationDays > 0 && _jobDurationDays <= 90, "Job duration must be 1-90 days");
        
        uint256 dueDate = block.timestamp + (_jobDurationDays * 1 days);
        
        advances[nextAdvanceId] = Advance({
            id: nextAdvanceId,
            worker: msg.sender,
            employer: _employer,
            advanceAmount: _advanceAmount,
            fullJobAmount: _fullJobAmount,
            dueDate: dueDate,
            isRepaid: false,
            isJobConfirmed: false,
            jobDescription: _jobDescription
        });
        
        workerAdvances[msg.sender].push(nextAdvanceId);
        employerAdvances[_employer].push(nextAdvanceId);
        
        emit AdvanceRequested(nextAdvanceId, msg.sender, _employer, _advanceAmount);
        nextAdvanceId++;
    }
    
    // Function 2: Employer approves and funds the advance
    function approveAndFundAdvance(uint256 _advanceId) external payable onlyEmployer(_advanceId) {
        Advance storage advance = advances[_advanceId];
        require(!advance.isJobConfirmed, "Advance already processed");
        require(msg.value == advance.advanceAmount, "Must send exact advance amount");
        
        // Calculate fee and net amount to worker
        uint256 fee = (advance.advanceAmount * ADVANCE_FEE_PERCENT) / 100;
        uint256 netAmount = advance.advanceAmount - fee;
        
        totalFeesCollected += fee;
        advance.isJobConfirmed = true;
        
        // Transfer net amount to worker
        payable(advance.worker).transfer(netAmount);
        
        emit AdvanceApproved(_advanceId, advance.advanceAmount);
        emit JobConfirmed(_advanceId);
    }
    
    // Function 3: Worker completes job and gets remaining payment
    function completeJobAndRepay(uint256 _advanceId) external payable onlyWorker(_advanceId) {
        Advance storage advance = advances[_advanceId];
        require(advance.isJobConfirmed, "Job not confirmed by employer");
        require(!advance.isRepaid, "Advance already repaid");
        require(block.timestamp <= advance.dueDate, "Job completion deadline passed");
        
        uint256 remainingAmount = advance.fullJobAmount - advance.advanceAmount;
        require(msg.value == remainingAmount, "Must send exact remaining job amount");
        
        advance.isRepaid = true;
        
        // Transfer remaining amount back to worker (they're paying the full job amount)
        // This represents the employer paying the remaining balance
        payable(advance.worker).transfer(remainingAmount);
        
        // Improve worker rating
        workerRatings[advance.worker] += 10;
        
        emit AdvanceRepaid(_advanceId, advance.advanceAmount);
    }
    
    // Function 4: Handle overdue advances (called by employer)
    function handleOverdueAdvance(uint256 _advanceId) external onlyEmployer(_advanceId) {
        Advance storage advance = advances[_advanceId];
        require(advance.isJobConfirmed, "Job not confirmed");
        require(!advance.isRepaid, "Advance already repaid");
        require(block.timestamp > advance.dueDate, "Job not yet overdue");
        
        // Mark as resolved (employer can take further action off-chain)
        advance.isRepaid = true;
        
        // Reduce worker rating for missed deadline
        if (workerRatings[advance.worker] >= 20) {
            workerRatings[advance.worker] -= 20;
        } else {
            workerRatings[advance.worker] = 0;
        }
    }
    
    // Function 5: Owner can withdraw collected fees
    function withdrawFees() external onlyOwner {
        require(totalFeesCollected > 0, "No fees to withdraw");
        uint256 amount = totalFeesCollected;
        totalFeesCollected = 0;
        payable(owner).transfer(amount);
    }
    
    // View functions
    function getAdvanceDetails(uint256 _advanceId) external view returns (Advance memory) {
        return advances[_advanceId];
    }
    
    function getWorkerAdvances(address _worker) external view returns (uint256[] memory) {
        return workerAdvances[_worker];
    }
    
    function getEmployerAdvances(address _employer) external view returns (uint256[] memory) {
        return employerAdvances[_employer];
    }
    
    function getWorkerRating(address _worker) external view returns (uint256) {
        return workerRatings[_worker];
    }
    
    // Emergency function to pause contract (if needed)
    function emergencyWithdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }
}
