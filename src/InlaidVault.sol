// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "./interfaces/IMuonClient.sol";

/**
 * @title InlaidVault
 * @notice InlaidVault for staking/redeeming a single token: either native token (address(0)) or an ERC20 token.
 * Admin controlled with AccessControl. Supports pausing.
 */
contract InlaidVault is AccessControl, Pausable {
    using SafeERC20 for IERC20;

    struct StakeInfo {
        uint256 amount; // amount to stake
        address user; // address of staker
    }

    struct User {
        uint256 balance; // currently staked (locked in vault, but not redeemed yet)
        uint256 pendingClaim; // amount user has redeemed and waiting to claim (after cooldown)
        uint256 cooldownEnd; // timestamp after which claim is allowed
        bool locked; // admin lock flag
    }

    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    /// @notice Token accepted by the vault: address(0) means native ETH
    address public immutable underlyingToken;

    /// @notice Cooldown period in seconds
    uint256 public cooldownPeriod = 1 days;

    /// @notice Muon app info
    uint256 public muonAppId;
    IMuonClient.PublicKey public muonPublicKey;
    IMuonClient public muon;

    /// @notice last stake ID / A unique ID that indicates stake record
    uint256 public lastStakeId;

    /// @notice total staked tokens
    uint256 public totalStaked;

    /// @notice Stake records
    mapping(uint256 => StakeInfo) public stakes;

    /// @notice User info
    mapping(address => User) public users;

    event Staked(address indexed user, uint256 amount);
    event Redeemed(address indexed user, uint256 amount, uint256 cooldownEnd);
    event Claimed(address indexed user, uint256 amount);
    event StakeLocked(address indexed user, bool locked);

    /**
     * @param _underlyingToken Token address to accept for staking.
     *                   Use address(0) to accept native token
     */
    constructor(
        address _underlyingToken,
        uint256 _muonAppId,
        IMuonClient.PublicKey memory _muonPublicKey,
        address _muonClient
    ) {
        underlyingToken = _underlyingToken;
        muonAppId = _muonAppId;
        muonPublicKey = _muonPublicKey;
        muon = IMuonClient(_muonClient);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    /**
     * @notice Stake ERC20 or native tokens
     * @param _amount Amount to stake (for native token, must match msg.value)
     */
    function stake(uint256 _amount) external payable whenNotPaused {
        require(_amount > 0, "Zero amount");

        if (underlyingToken == address(0)) {
            require(msg.value == _amount, "ETH value mismatch");
        } else {
            IERC20 token = IERC20(underlyingToken);
            uint256 balance = token.balanceOf(address(this));
            token.safeTransferFrom(msg.sender, address(this), _amount);
            uint256 receivedAmount = token.balanceOf(address(this)) - balance;

            require(_amount == receivedAmount, "Received amount mismatch");
        }

        users[msg.sender].balance += _amount;
        stakes[++lastStakeId] = StakeInfo({amount: _amount, user: msg.sender});
        totalStaked += _amount;

        emit Staked(msg.sender, _amount);
    }

    /**
     * @notice Start redeem process by locking amount and starting cooldown
     * @param _amount Amount to redeem
     */
    function redeem(
        uint256 _amount,
        bytes calldata _reqId,
        IMuonClient.SchnorrSign calldata signature
    ) external whenNotPaused {
        User storage stakeData = users[msg.sender];
        require(!stakeData.locked, "Stake locked");
        require(
            _amount > 0 && stakeData.balance >= _amount,
            "Insufficient balance"
        );

        bytes32 hash = keccak256(
            abi.encodePacked(muonAppId, _reqId, msg.sender, _amount)
        );

        require(
            muon.muonVerify(_reqId, uint256(hash), signature, muonPublicKey),
            "Muon sig not verified"
        );

        stakeData.balance -= _amount;
        stakeData.pendingClaim += _amount;
        stakeData.cooldownEnd = block.timestamp + cooldownPeriod;
        totalStaked -= _amount;

        emit Redeemed(msg.sender, _amount, stakeData.cooldownEnd);
    }

    /**
     * @notice Claim tokens after cooldown period
     */
    function claimStake() external whenNotPaused {
        User storage stakeData = users[msg.sender];
        require(stakeData.pendingClaim > 0, "No pending claim");
        require(
            stakeData.cooldownEnd > 0 &&
                block.timestamp >= stakeData.cooldownEnd,
            "Cooldown not ended"
        );

        uint256 amount = stakeData.pendingClaim;

        stakeData.pendingClaim = 0;
        stakeData.cooldownEnd = 0;

        if (underlyingToken == address(0)) {
            payable(msg.sender).transfer(amount);
        } else {
            IERC20(underlyingToken).safeTransfer(msg.sender, amount);
        }

        emit Claimed(msg.sender, amount);
    }

    /**
     * @notice Emergency withdraw for admin
     * @param to Recipient address
     * @param amount Amount to withdraw
     */
    function emergencyWithdraw(
        address to,
        uint256 amount
    ) external onlyRole(ADMIN_ROLE) {
        require(to != address(0), "Zero address");

        if (underlyingToken == address(0)) {
            payable(to).transfer(amount);
        } else {
            IERC20(underlyingToken).safeTransfer(to, amount);
        }
    }

    /**
     * @notice Lock or unlock a user's stake
     * @param user User address
     * @param lockFlag True to lock, false to unlock
     */
    function lockStake(
        address user,
        bool lockFlag
    ) external onlyRole(ADMIN_ROLE) {
        users[user].locked = lockFlag;
        emit StakeLocked(user, lockFlag);
    }

    /**
     * @notice Update cooldown period
     * @param newPeriod Cooldown period in seconds
     */
    function setCooldownPeriod(
        uint256 newPeriod
    ) external onlyRole(ADMIN_ROLE) {
        cooldownPeriod = newPeriod;
    }

    /**
     * @notice Pause contract functions
     */
    function pause() external onlyRole(ADMIN_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause contract functions
     */
    function unpause() external onlyRole(ADMIN_ROLE) {
        _unpause();
    }

    /**
     * @notice Set MUON appId
     * @param _muonAppId App id
     */
    function setMuonAppId(uint256 _muonAppId) external onlyRole(ADMIN_ROLE) {
        muonAppId = _muonAppId;
    }

    /**
     * @notice Set MUON public key
     * @param _muonPublicKey Public key
     */
    function setMuonPublicKey(
        IMuonClient.PublicKey memory _muonPublicKey
    ) external onlyRole(ADMIN_ROLE) {
        muonPublicKey = _muonPublicKey;
    }

    /**
     * @notice Set MUON client address
     * @param _muonClient Address of MUON client
     */
    function setMuonClient(address _muonClient) external onlyRole(ADMIN_ROLE) {
        muon = IMuonClient(_muonClient);
    }

    /// @notice To receive ETH for staking
    receive() external payable {
        require(underlyingToken == address(0), "ETH not accepted");
    }

    fallback() external payable {
        require(underlyingToken == address(0), "ETH not accepted");
    }
}
