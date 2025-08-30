// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IDelegationManager.sol";
import "./interfaces/IStrategyManager.sol";
import "./interfaces/IMuonClient.sol";

interface IWrappedToken is IERC20 {
    function mint(address to, uint256 amount) external;

    function burnFrom(address from, uint256 amount) external;
}

/**
 * @title EigenCloudGateway
 * @notice EigenCloudGateway contract allowing users to claim bridged tokens by minting wrapped tokens,
 *         and stake to EigenLayer in one tx, as well as pay back (burn) tokens to bridge back.
 */
contract EigenCloudGateway is AccessControl, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct Token {
        uint256 tokenId;
        uint256 chainId;
        address token;
        address strategy;
        address wToken;
        uint256 value;
    }

    /// Admin role for future control if needed
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");

    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// EigenLayer strategyManager contract
    IStrategyManager public immutable strategyManager;

    /// EigenLayer delegationManager contract
    IDelegationManager public immutable delegationManager;

    /// Mapping of ID to token
    mapping(uint256 => Token) public tokens;

    /// Mapping of token address to ID
    mapping(address => mapping(uint256 => uint256)) public tokenIds;

    /// Mapping of token address to claimed stakeID
    mapping(address => mapping(uint256 => mapping(uint256 => bool)))
        public claimedStakes;

    /// Mapping of staker address to nonce
    mapping(address => uint256) public nonces;

    /// Event emitted on successful claim + stake
    event ClaimedAndStaked(address indexed user, uint256 amount);

    /// Event emitted on successful claim
    event Claimed(address indexed user, uint256 amount);

    /// Event emitted on payback (burn + bridge back trigger)
    event Payback(address indexed user, uint256 amount);

    constructor(address _strategyManager, address _delegationManager) {
        strategyManager = IStrategyManager(_strategyManager);
        delegationManager = IDelegationManager(_delegationManager);

        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
    }

    function autoDelegate(
        uint256 _chainId,
        address _token,
        uint256 _amount,
        uint256 _stakeId
    ) external onlyRole(OPERATOR_ROLE) returns (uint256 depositShares) {
        uint256 tokenId = tokenIds[_token][_chainId];

        require(tokenId > 0, "Invalid token");
        require(_amount > 0, "Zero amount");

        // Reset approval to zero for safety (optional)
        IERC20(tokens[tokenId].wToken).approve(
            address(strategyManager),
            _amount
        );

        // Call depositIntoStrategy in StrategyManager to stake tokens
        // The StrategyManager will internally transfer tokens from this contract to Strategy,
        // so this contract needs to approve StrategyManager to pull tokens.
        depositShares = strategyManager.depositIntoStrategy(
            IStrategy(tokens[tokenId].strategy),
            IERC20(tokens[tokenId].wToken),
            _amount
        );

        return depositShares;
    }

    /**
     * @notice Claim bridged tokens (mint wrappedToken) and stake to EigenLayer in one transaction.
     * @dev This function would normally be called only by a trusted relayer or after proof verification.
     * Here, for simplicity, it is open but should be protected in production.
     * @param _amount Amount of tokens to claim and stake.
     */
    function claim(
        uint256 _chainId,
        address _token,
        uint256 _amount,
        uint256 _stakeId,
        bytes calldata _reqId,
        IMuonClient.SchnorrSign calldata signature
    ) external nonReentrant {
        require(_amount > 0, "Zero amount");

        uint256 tokenId = tokenIds[_token][_chainId];

        claimedStakes[_token][_chainId][_stakeId] = true;

        // Mint wrapped tokens to user
        IWrappedToken(tokens[tokenId].wToken).mint(msg.sender, _amount);

        emit ClaimedAndStaked(msg.sender, _amount);
    }

    /**
     * @notice Payback wrapped tokens to burn them and initiate bridging back to original chain.
     * @param _amount Amount of tokens to pay back.
     */
    function payback(uint256 _tokenId, uint256 _amount) external nonReentrant {
        require(_amount > 0, "Zero amount");

        // Burn wrapped tokens from the sender
        IWrappedToken(tokens[_tokenId].wToken).burnFrom(msg.sender, _amount);

        // TODO: add bridging logic here (e.g., emit event for relayer off-chain to listen)

        emit Payback(msg.sender, _amount);
    }

    function getSignatureDigestHash(
        address _staker,
        address _token,
        uint256 _amount
    ) public returns (bytes memory) {
        bytes memory result; // Declared but not initialized
        return result;
    }
}
