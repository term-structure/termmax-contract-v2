// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    Ownable2StepUpgradeable,
    OwnableUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {SafeERC20, IERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract TermMaxRewardContract is
    UUPSUpgradeable,
    Ownable2StepUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    error UserNotActive(address user);
    error ArrayLengthMismatch();

    event RewardAdded(address indexed user, IERC20[] tokens, uint256[] amounts);
    event RewardRemoved(address indexed user, IERC20[] tokens, uint256[] amounts);
    event RewardClaimed(address indexed user, address to, IERC20[] tokens, uint256[] amounts);
    event UserWhitelisted(address[] users);
    event UserBlacklisted(address[] users);
    event UserCheckedIn(address indexed user);

    struct UserProfile {
        bool isBlocked;
        mapping(IERC20 => uint256) rewards;
    }

    struct Reward {
        address user;
        IERC20[] tokens;
        uint256[] amounts;
    }

    address public constant ETH_ADDRESS = address(0);
    mapping(address => UserProfile) public userProfiles;

    modifier onlyAvailableUser() {
        require(!userProfiles[msg.sender].isBlocked, UserNotActive(msg.sender));
        _;
    }

    function initialize(address admin) external initializer {
        __Ownable2Step_init_unchained();
        __Ownable_init_unchained(admin);
        __ReentrancyGuard_init_unchained();
        __Pausable_init_unchained();
    }

    function checkIn() external whenNotPaused onlyAvailableUser {
        emit UserCheckedIn(msg.sender);
    }

    function claimRewards(IERC20[] calldata tokens, address to)
        external
        payable
        nonReentrant
        whenNotPaused
        onlyAvailableUser
    {
        UserProfile storage profile = userProfiles[msg.sender];

        uint256[] memory amounts = new uint256[](tokens.length);
        for (uint256 i = 0; i < tokens.length; ++i) {
            IERC20 token = tokens[i];
            amounts[i] = profile.rewards[token];
            if (amounts[i] == 0) {
                continue; // Skip if no rewards for this token
            }
            delete profile.rewards[token];
            if (address(token) == ETH_ADDRESS) {
                payable(to).transfer(amounts[i]);
            } else {
                token.safeTransfer(to, amounts[i]);
            }
        }
        emit RewardClaimed(msg.sender, to, tokens, amounts);
    }

    function addRewards(Reward[] memory rewards) external payable onlyOwner {
        for (uint256 i = 0; i < rewards.length; ++i) {
            Reward memory reward = rewards[i];
            require(reward.tokens.length == reward.amounts.length, ArrayLengthMismatch());

            for (uint256 j = 0; j < reward.tokens.length; ++j) {
                userProfiles[reward.user].rewards[reward.tokens[j]] += reward.amounts[j];
            }
            emit RewardAdded(reward.user, reward.tokens, reward.amounts);
        }
    }

    function removeRewards(Reward[] memory rewards) external onlyOwner {
        for (uint256 i = 0; i < rewards.length; ++i) {
            Reward memory reward = rewards[i];
            require(reward.tokens.length == reward.amounts.length, ArrayLengthMismatch());

            for (uint256 j = 0; j < reward.tokens.length; ++j) {
                mapping(IERC20 => uint256) storage userRewards = userProfiles[reward.user].rewards;
                uint256 currentReward = userRewards[reward.tokens[j]];
                if (currentReward <= reward.amounts[j]) {
                    delete userRewards[reward.tokens[j]];
                } else {
                    userRewards[reward.tokens[j]] = currentReward - reward.amounts[j];
                }
            }
            emit RewardRemoved(reward.user, reward.tokens, reward.amounts);
        }
    }

    function withdrawAssets(IERC20 token, address to, uint256 amount) public payable onlyOwner {
        if (address(token) == ETH_ADDRESS) {
            payable(to).transfer(amount);
        } else {
            token.safeTransfer(to, amount);
        }
    }

    function whitelistUsers(address[] calldata users) public onlyOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            delete userProfiles[user].isBlocked;
        }
        emit UserWhitelisted(users);
    }

    function blacklistUsers(address[] calldata users) public onlyOwner {
        for (uint256 i = 0; i < users.length; ++i) {
            address user = users[i];
            userProfiles[user].isBlocked = true;
        }
        emit UserBlacklisted(users);
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _authorizeUpgrade(address newImplementation) internal virtual override onlyOwner {}
}
