// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

interface IAddressBook {
    /// @notice Emitted when an account is verified
    event AccountVerified(address indexed account, uint256 verifiedUntil);

    /// @notice Returns a timestamp representing when the address' verification will expire
    /// @param account The address to check
    /// @return timestamp The timestamp when the address' verification will expire
    function addressVerifiedUntil(address account) external view returns (uint256 timestamp);

    /// @notice Registers a wallet to receive grants
    /// @param account The address that will be registered
    /// @param root The root of the Merkle tree (signup-sequencer or world-id-contracts provides this)
    /// @param nullifierHash The nullifier for this proof, preventing double signaling
    /// @param proof The zero knowledge proof that demonstrates the claimer has a verified World ID
    /// @param proofTime A timestamp representing when the proof was created
    /// @custom:throws Will revert if the proof is invalid or expired
    function verify(address account, uint256 root, uint256 nullifierHash, uint256[8] calldata proof, uint256 proofTime)
        external
        payable;
}
