// SPDX-License-Identifier: MIT
pragma solidity =0.8.37;

contract MockLOVE20Protocols {
    string public symbol = "TestLOVE20";
    uint256 internal _currentRound = 1;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public allowance;
    mapping(address => mapping(uint256 => uint256)) public govVotes;
    mapping(address => uint256) public govVoteTotals;
    mapping(address => mapping(uint256 => mapping(uint256 => mapping(uint256 => uint256)))) public actionVotes;
    mapping(address => mapping(uint256 => uint256[])) internal _actionIdsByMemberId;
    mapping(address => mapping(uint256 => mapping(uint256 => bool))) internal _joined;
    mapping(address => uint256) public proposalCounts;
    mapping(address => uint8) internal _love20TokenFlags;

    function setCurrentRound(uint256 round) external {
        _currentRound = round;
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

    function stakeAddress() external view returns (address) {
        return address(this);
    }

    function launchAddress() external view returns (address) {
        return address(this);
    }

    function voteAddress() external view returns (address) {
        return address(this);
    }

    function submitAddress() external view returns (address) {
        return address(this);
    }

    function validGovVotes(address tokenAddress, uint256 memberId) external view returns (uint256) {
        return govVotes[tokenAddress][memberId];
    }

    function globalGovVotes(address tokenAddress) external view returns (uint256) {
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

    function votesNumByMemberIdByProposalId(
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
