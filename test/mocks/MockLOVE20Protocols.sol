// SPDX-License-Identifier: MIT
pragma solidity =0.8.17;

contract MockLOVE20Protocols {
    string public symbol = "LOVE20";
    uint256 internal _currentRound = 1;
    uint256 public originBlocks = 100;
    uint256 public phaseBlocks = 25;

    mapping(address => uint256) public balances;
    mapping(address => mapping(address => uint256)) public govVotes;
    mapping(address => uint256) public govVoteTotals;
    mapping(address => mapping(uint256 => mapping(address => uint256))) public joinedAmounts;
    mapping(address => mapping(address => uint256)) public joinedAmountsByAccount;
    mapping(address => mapping(uint256 => mapping(address => mapping(uint256 => uint256)))) public actionVotes;
    mapping(address => mapping(uint256 => mapping(address => bool))) public extensionJoined;
    mapping(address => uint256) public extensionJoinedAmounts;
    mapping(address => uint256) public actionCounts;
    mapping(address => mapping(uint256 => uint256[])) internal _votedActionIds;
    mapping(address => uint8) internal _love20TokenFlags;

    function setCurrentRound(uint256 round) external {
        _currentRound = round;
    }

    function setPhase(uint256 originBlocks_, uint256 phaseBlocks_) external {
        originBlocks = originBlocks_;
        phaseBlocks = phaseBlocks_;
    }

    function setBalance(address account, uint256 balance) external {
        balances[account] = balance;
    }

    function setGovVotes(address token, address account, uint256 votes) external {
        govVoteTotals[token] = govVoteTotals[token] - govVotes[token][account] + votes;
        govVotes[token][account] = votes;
    }

    function setLOVE20Token(address token, bool listed) external {
        _love20TokenFlags[token] = listed ? 1 : 2;
    }

    function setActionsCount(address token, uint256 count) external {
        actionCounts[token] = count;
    }

    function setJoinedAmount(address token, uint256 actionId, address account, uint256 amount) external {
        joinedAmounts[token][actionId][account] = amount;
    }

    function setJoinedAmountByAccount(address token, address account, uint256 amount) external {
        joinedAmountsByAccount[token][account] = amount;
    }

    function setActionVotes(address token, uint256 round, address account, uint256 actionId, uint256 votes) external {
        actionVotes[token][round][account][actionId] = votes;
    }

    function setExtensionJoined(address token, uint256 actionId, address account, bool joined) external {
        extensionJoined[token][actionId][account] = joined;
    }

    function setExtensionJoinedAmount(address account, uint256 amount) external {
        extensionJoinedAmounts[account] = amount;
    }

    function setVotedAction(address token, uint256 round, uint256 actionId, address whiteListAddress) external {
        whiteListAddress;
        _votedActionIds[token][round].push(actionId);
    }

    function balanceOf(address account) external view returns (uint256) {
        return balances[account];
    }

    function stakeAddress() external view returns (address) {
        return address(this);
    }

    function launchAddress() external view returns (address) {
        return address(this);
    }

    function joinAddress() external view returns (address) {
        return address(this);
    }

    function voteAddress() external view returns (address) {
        return address(this);
    }

    function submitAddress() external view returns (address) {
        return address(this);
    }

    function validGovVotes(address tokenAddress, address account) external view returns (uint256) {
        return govVotes[tokenAddress][account];
    }

    function govVotesNum(address tokenAddress) external view returns (uint256) {
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

    function votesNumByAccountByActionId(address tokenAddress, uint256 round, address account, uint256 actionId)
        external
        view
        returns (uint256)
    {
        return actionVotes[tokenAddress][round][account][actionId];
    }

    function amountByActionIdByAccount(address tokenAddress, uint256 actionId, address account)
        external
        view
        returns (uint256)
    {
        return joinedAmounts[tokenAddress][actionId][account];
    }

    function amountByAccount(address tokenAddress, address account) external view returns (uint256) {
        return joinedAmountsByAccount[tokenAddress][account];
    }

    function votedActionIdsCount(address tokenAddress, uint256 round) external view returns (uint256) {
        return _votedActionIds[tokenAddress][round].length;
    }

    function votedActionIdsAtIndex(address tokenAddress, uint256 round, uint256 index)
        external
        view
        returns (uint256)
    {
        return _votedActionIds[tokenAddress][round][index];
    }

    function joinedAmountByAccount(address account) external view returns (uint256) {
        return extensionJoinedAmounts[account];
    }

    function actionsCount(address tokenAddress) external view returns (uint256) {
        return actionCounts[tokenAddress];
    }

    function isAccountJoined(address tokenAddress, uint256 actionId, address account) external view returns (bool) {
        return extensionJoined[tokenAddress][actionId][account];
    }
}
