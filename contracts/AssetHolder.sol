// Copyright (c) 2019 The Perun Authors. All rights reserved.
// This file is part of go-perun. Use of this source code is governed by a
// MIT-style license that can be found in the LICENSE file.

pragma solidity ^0.5.13;
pragma experimental ABIEncoderV2;
import "./SafeMath.sol";

/**
 * @title The Perun AssetHolder
 * @author The Perun Authors
 * @dev AssetHolder is an abstract contract that holds the funds for a Perun state channel.
 */
contract AssetHolder {

    using SafeMath for uint256;

    /**
     * @dev WithdrawalAuthorization authorizes a on-chain public key to withdraw from an ephemeral key.
     */
    struct WithdrawalAuth {
        bytes32 channelID;
        address participant; // The account used to sign the authorization which is debited.
        address payable receiver; // The receiver of the authorization.
        uint256 amount; // The amount that can be withdrawn.
    }

    event OutcomeSet(bytes32 indexed channelID);
    event Deposited(bytes32 indexed fundingID, uint256 amount);

    /**
     * @notice This mapping stores the balances of participants to their fundingID.
     * @dev Mapping H(channelID||participant) => money
     */
    mapping(bytes32 => uint256) public holdings;

    /**
     * @notice This mapping stores whether a channel was already settled.
     * @dev Mapping channelID => settled
     */
    mapping(bytes32 => bool) public settled;

    /**
     * @notice adjudicator stores the address of the adjudicator contract that can call setOutcome().
     * @dev This should only be set in the constructor of the implementing contract.
     */
    address public adjudicator = address(0);

    /**
     * @notice The onlyAdjudicator modifier specifies functions that can only be called from the adjudicator contract.
     */
    modifier onlyAdjudicator {
        require(msg.sender == adjudicator,
            "This method can only be called by the adjudicator contract");
        _;
    }

    /**
     * @notice Sets the final outcome of a channel, can only be called by the adjudicator.
     * @dev this method should not be overwritten by the implementing contract.
     * @param channelID ID of the channel that should be disbursed.
     * @param parts Array of participants of the channel.
     * @param newBals New Balances after execution of the channel.
     * @param subAllocs currently not implemented.
     * @param subBalances currently not implemented.
     */
    function setOutcome(
        bytes32 channelID,
        address[] calldata parts,
        uint256[] calldata newBals,
        bytes32[] calldata subAllocs,
        uint256[] calldata subBalances)
    external onlyAdjudicator {
        require(parts.length == newBals.length, "participants length should equal balances");
        require(subAllocs.length == subBalances.length, "length of subAllocs and subBalances should be equal");
        require(subAllocs.length == 0, "subAllocs currently not implemented");
        require(settled[channelID] == false, "trying to set already settled channel");

        // The channelID itself might already be funded
        uint256 sumHeld = holdings[channelID];
        uint256 sumOutcome = 0;

        bytes32[] memory fundingIDs = new bytes32[](parts.length);
        for (uint256 i = 0; i < parts.length; i++) {
            bytes32 id = calcFundingID(channelID, parts[i]);
            // Save calculated ids to save gas.
            fundingIDs[i] = id;
            // Compute old balances.
            sumHeld = sumHeld.add(holdings[id]);
            // Compute new balances.
            sumOutcome = sumOutcome.add(newBals[i]);
        }

        // We allow overfunding channels, who overfunds looses their funds.
        if (sumHeld >= sumOutcome) {
            for (uint256 i = 0; i < parts.length; i++) {
                holdings[fundingIDs[i]] = newBals[i];
            }
        }
        settled[channelID] = true;
        emit OutcomeSet(channelID);
    }

    /**
     * @notice Internal helper function that calculates the fundingID.
     * @param channelID Unique identifier of a channel.
     * @param participant Address of a participant in the channel.
     * @return fundingID = H(channelID || participant)
     */
    function calcFundingID(bytes32 channelID, address participant) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(channelID, participant));
    }

    /**
     * @notice Payable function that is used to fund a channel.
     * @dev Abstract function that should be implemented in the concrete AssetHolder implementation.
     * @param fundingID Unique identifier for a participant in a channel.
     * @param amount Amount of money that should be deposited.
     */
    function deposit(bytes32 fundingID, uint256 amount) external payable;

    /**
     * @notice Sends money from authorization.participant to authorization.receiver
     * @dev Abstract function that should be implemented in the concrete AssetHolder implementation.
     * @param authorization WithdrawalAuth struct that is used to send money from an ephemeral key to an on-chain key.
     * @param signature Signature on the withdrawal authorization
     */
    function withdraw(WithdrawalAuth memory authorization, bytes memory signature) public;
}
