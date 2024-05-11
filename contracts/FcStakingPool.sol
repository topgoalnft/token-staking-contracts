// SPDX-License-Identifier: MIT
pragma solidity ^0.8.16;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract FcStakingPool is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    struct Stake {
        uint256 activityId;
        address user;
        address token;
        uint256 amount;
        uint256 lockEndTime;
    }

    // activityId - is in effect？
    mapping(uint256 => bool) public activityState;

    // activityId - lockDays, 0 or unset means no limit
    mapping(uint256 => uint256) public activityLockDays;

    mapping(address => bool) public tokenWhitelist;
    // user stakes
    mapping(address => Stake[]) public stakes;
    // user - token - total
    mapping(address => mapping(address => uint256)) public userTotalStakes;
    // totoal of token
    mapping(IERC20 => uint256) public totalOf;

    event Staked(uint256 activityId, address indexed user, address indexed token, uint256 amount, uint256 lockDays, uint256 lockEndTime);
    event Unstaked(uint256 activityId, address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed to, address indexed token, uint256 amount);
    event ActivityStateChanged(uint256 activityId, bool state);
    event ActivityLockDaysChanged(uint256 activityId, uint256 lockDays);
    event TokenAddedToWhitelist(address indexed token);
    event TokenRemovedFromWhitelist(address indexed token);

    // Deposit ERC20 token
    function stakeToken(uint256 activityId, address token, uint256 amount, uint256 lockDays) external {
        require(activityState[activityId], "Activity is not valid");
        require(tokenWhitelist[token], "Token is not whitelisted");
        require(amount > 0, "Amount must be greater than 0");
        uint256 aLockDays = activityLockDays[activityId];
        if (aLockDays > 0) {
            require(lockDays == aLockDays, "Invalid lockDays");
        }

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        
        uint256 lockEndTime = lockDays.mul(1 days).add(block.timestamp);
        stakes[msg.sender].push(Stake(activityId,msg.sender, token, amount, lockEndTime));
        userTotalStakes[msg.sender][token] += amount;
        totalOf[IERC20(token)] += amount;

        emit Staked(activityId, msg.sender, token, amount, lockDays, lockEndTime);
    }

    // Deposit ETH
    function stakeETH(uint256 activityId, uint256 lockDays) external payable {
        require(activityState[activityId], "Activity is not valid");
        require(msg.value > 0, "ETH amount must be greater than 0");
        
        uint256 aLockDays = activityLockDays[activityId];
        if (aLockDays > 0) {
            require(lockDays == aLockDays, "Invalid lockDays");
        }
        uint256 lockEndTime = lockDays.mul(1 days).add(block.timestamp);
        stakes[msg.sender].push(Stake(activityId, msg.sender, address(0), msg.value, lockEndTime));
        
        userTotalStakes[msg.sender][address(0)] += msg.value;
        totalOf[IERC20(address(0))] += msg.value;

        emit Staked(activityId, msg.sender, address(0), msg.value, lockDays,lockEndTime);
    }

    // Withdraw ERC20 token or ETH after lock period
    function withdraw(uint256 index) external nonReentrant {
        require(index < stakes[msg.sender].length, "Invalid index");
        Stake memory stake = stakes[msg.sender][index];
        require(block.timestamp >= stake.lockEndTime, "Lock period not over");

        if (stake.token == address(0)) {
            (bool sent, ) = payable(msg.sender).call{value: stake.amount}("");
            require(sent, "Token transfer failed");
        } else {
            IERC20(stake.token).safeTransfer(msg.sender, stake.amount);
        }
        
        userTotalStakes[msg.sender][stake.token] -= stake.amount;
        totalOf[IERC20(stake.token)] -= stake.amount;
        emit Unstaked(stake.activityId, msg.sender, stake.token, stake.amount);

        // Remove stake from array
        if (index < stakes[msg.sender].length - 1) {
            stakes[msg.sender][index] = stakes[msg.sender][stakes[msg.sender].length - 1];
        }
        stakes[msg.sender].pop();
    }

    // Get number of stakes for a user
    function getStakeCount(address user) external view returns (uint256) {
        return stakes[user].length;
    }

    // Get total staked amount of a user for a specific token
    function getUserTotalStakedAmount(address user, address token) external view returns (uint256) {
        return userTotalStakes[user][token];
    }

    // Get user's stake list
    function getUserStakes(address user) external view returns (Stake[] memory) {
        return stakes[user];
    }

    // admins
    function setActivityState(uint256 activityId, bool state) external onlyOwner {
        activityState[activityId] = state;
        emit ActivityStateChanged(activityId, state);
    }

    function changeActivityLockDays(uint256 activityId, uint256 lockDays) external onlyOwner {
        require(activityState[activityId], "Activity is not valid");

        activityLockDays[activityId] = lockDays;
        emit ActivityLockDaysChanged(activityId, lockDays);
    }

    // Add token to whitelist
    function addTokenToWhitelist(address token) external onlyOwner {
        tokenWhitelist[token] = true;
        emit TokenAddedToWhitelist(token);
    }

    // Remove token from whitelist
    function removeTokenFromWhitelist(address token) external onlyOwner {
        tokenWhitelist[token] = false;
        emit TokenRemovedFromWhitelist(token);
    }

}