// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";

/**
 * @title InlaidWrapToken
 * @notice It is used as the bridge Token through Inlaid protocol
 */
contract InlaidWrapToken is ERC20Burnable, AccessControl {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) AccessControl() {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
    }

    /**
     *
     * @param _to Address of recipient
     * @param _amount  Mint amount
     * @dev MINTER_ROLE should be granted to the bridge
     */
    function mint(address _to, uint256 _amount) external onlyRole(MINTER_ROLE) {
        _mint(_to, _amount);
    }
}
