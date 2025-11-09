// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {IAddressBook} from "../../src/interfaces/IAddressBook.sol";

contract MockAddressBook is IAddressBook {
    /// @notice Returns a timestamp representing when the address' verification will expire
    mapping(address => uint256) public addressVerifiedUntil;

    function setVerification(address account, uint256 timestamp) public {
        addressVerifiedUntil[account] = timestamp;
    }

    /// @notice Registers a wallet to receive grants
    /// @param account The address that will be registered
    /// @param root The root of the Merkle tree (signup-sequencer or world-id-contracts provides this)
    /// @param nullifierHash The nullifier for this proof, preventing double signaling
    /// @param proof The zero knowledge proof that demonstrates the claimer has a verified World ID
    /// @param proofTime A timestamp representing when the proof was created
    /// @custom:throws Will revert if the proof is invalid or expired
    function verify(address account, uint256 root, uint256 nullifierHash, uint256[8] calldata proof, uint256 proofTime)
        external
        payable {
        // noop
    }
}
