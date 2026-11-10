// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

contract MockLOVE20Protocols {
    string public symbol = "TestLOVE20";
    uint256 internal _currentRound = 1;
    address public memberNFTAddress;
    address public phaseAddress;
    // Roles the mock plays by default; settable so tests can express a role with no code or one
    // pointing at a different contract.
    address internal submitAddress;
    address internal voteAddress;
    address internal stakeAddress;
    address internal launchAddress;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => mapping(uint256 => uint256)) public govVotes;
    mapping(address => uint256) public govVoteTotals;
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))) public actionVotes;
    mapping(address => mapping(uint256 => uint256[])) internal _actionIdsByMemberId;
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) internal _joined;
    mapping(address => uint256) public proposalCounts;
    mapping(address => uint8) internal _love20TokenFlags;
    mapping(address => mapping(uint256 => bool)) internal _plainProposal;

    constructor() {
        // The mock plays the phase as well, so the round the managers read is the one it reports.
        phaseAddress = address(this);
        submitAddress = address(this);
        voteAddress = address(this);
        stakeAddress = address(this);
        launchAddress = address(this);
    }

    function currentPhase() external view returns (uint256) {
        return _currentRound;
    }

    function setCurrentRound(uint256 round) external {
        _currentRound = round;
    }

    function setMemberNFTAddress(address memberNFTAddress_) external {
        memberNFTAddress = memberNFTAddress_;
    }

    function setPhaseAddress(address phaseAddress_) external {
        phaseAddress = phaseAddress_;
    }

    function setSubmitAddress(address submitAddress_) external {
        submitAddress = submitAddress_;
    }

    function setVoteAddress(address voteAddress_) external {
        voteAddress = voteAddress_;
    }

    function setStakeAddress(address stakeAddress_) external {
        stakeAddress = stakeAddress_;
    }

    function setLaunchAddress(address launchAddress_) external {
        launchAddress = launchAddress_;
    }

    function setBalance(address account, uint256 balance) external {
        balances[account] = balance;
    }

    function setGovVotes(address token, uint256 memberId, uint256 votes) external {
        govVoteTotals[token] = govVoteTotals[token] - govVotes[token][memberId] + votes;
        govVotes[token][memberId] = votes;
    }

    function setLOVE20Token(address token, bool listed) external {
        _love20TokenFlags[token] = listed ? 1 : 2;
    }

    function setActionsCount(address token, uint256 count) external {
        proposalCounts[token] = count;
    }

    function setPlainProposal(address token, uint256 proposalId) external {
        _plainProposal[token][proposalId] = true;
    }

    function setActionVotes(address token, uint256 round, uint256 memberId, uint256 actionId, uint256 votes) external {
        actionVotes[token][round][memberId][actionId] = votes;
    }

    function setActionJoined(address token, uint256 actionId, uint256 memberId, bool joined) external {
        _joined[token][actionId][memberId] = joined;
        if (joined) {
            _actionIdsByMemberId[token][memberId].push(actionId);
        }
    }

    function clearActionJoined(address token, uint256 memberId) external {
        delete _actionIdsByMemberId[token][memberId];
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        uint256 allowed = allowance[from][msg.sender];
        require(allowed >= amount, "ALLOWANCE");
        require(balances[from] >= amount, "BALANCE");
        allowance[from][msg.sender] = allowed - amount;
        balances[from] -= amount;
        balances[to] += amount;
        return true;
    }

    function STAKE_ADDRESS() external view returns (address) {
        return stakeAddress;
    }

    function LAUNCH_ADDRESS() external view returns (address) {
        return launchAddress;
    }

    function PHASE_ADDRESS() external view returns (address) {
        return phaseAddress;
    }

    function MEMBER_NFT_ADDRESS() external view returns (address) {
        return memberNFTAddress;
    }

    function VOTE_ADDRESS() external view returns (address) {
        return voteAddress;
    }

    function SUBMIT_ADDRESS() external view returns (address) {
        return submitAddress;
    }

    // The real `Stake` is round-keyed; this double answers only the round the phase reports (zero otherwise).
    function validGovVotes(address tokenAddress, uint256 round, uint256 memberId) external view returns (uint256) {
        if (round != _currentRound) return 0;
        return govVotes[tokenAddress][memberId];
    }

    function totalValidGovVotes(address tokenAddress, uint256 round) external view returns (uint256) {
        if (round != _currentRound) return 0;
        return govVoteTotals[tokenAddress];
    }

    function isLOVE20Token(address tokenAddress) external view returns (bool) {
        uint8 flag = _love20TokenFlags[tokenAddress];
        if (flag == 1) {
            return true;
        }
        if (flag == 2) {
            return false;
        }
        return tokenAddress.code.length != 0;
    }

    function currentRound() external view returns (uint256) {
        return _currentRound;
    }

    function voteAmountByMemberIdByProposalId(
        address tokenAddress,
        uint256 round,
        uint256 memberId,
        uint256 proposalId
    ) external view returns (uint256) {
        return actionVotes[tokenAddress][round][memberId][proposalId];
    }

    function proposalIds(address tokenAddress, uint256, uint256, bool)
        external
        view
        returns (uint256[] memory proposalIdList, uint256 totalCount)
    {
        totalCount = proposalCounts[tokenAddress];
        proposalIdList = new uint256[](0);
    }

    function executorByActionId(address tokenAddress, uint256 actionId) external view returns (address) {
        if (_plainProposal[tokenAddress][actionId] || actionId == 0 || actionId > proposalCounts[tokenAddress]) {
            return address(0);
        }
        return address(this);
    }

    function actionIdsByMemberId(address tokenAddress, uint256 memberId, uint256, uint256, bool)
        external
        view
        returns (uint256[] memory actionIds, uint256 total)
    {
        uint256[] storage stored = _actionIdsByMemberId[tokenAddress][memberId];
        total = stored.length;
        actionIds = new uint256[](0);
    }

    function isJoined(address tokenAddress, uint256 actionId, uint256 memberId) external view returns (bool) {
        return _joined[tokenAddress][actionId][memberId];
    }
}
