// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {ERC20} from "solady/tokens/ERC20.sol";

/// @notice Demo token with a public faucet. Testnet only.
contract MockToken is ERC20 {
    error FaucetCap();

    string internal _name;
    string internal _symbol;
    uint8 internal immutable _decimals;
    uint256 public immutable faucetCap;

    constructor(string memory name_, string memory symbol_, uint8 decimals_, uint256 faucetCap_) {
        _name = name_;
        _symbol = symbol_;
        _decimals = decimals_;
        faucetCap = faucetCap_;
    }

    function name() public view override returns (string memory) {
        return _name;
    }

    function symbol() public view override returns (string memory) {
        return _symbol;
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function faucet(address to, uint256 amount) external {
        if (amount > faucetCap) revert FaucetCap();
        _mint(to, amount);
    }
}
