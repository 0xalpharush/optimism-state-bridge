// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.15;

/// @dev using Test from forge-std which is inherited from Optimism's CommonTest.t.sol
// import { PRBTest } from "@prb/test/PRBTest.sol";
// import { StdCheats } from "forge-std/StdCheats.sol";
import {OpWorldID} from "../src/OpWorldID.sol";
import {L2CrossDomainMessenger} from "@eth-optimism/contracts-bedrock/contracts/L2/L2CrossDomainMessenger.sol";
import {CrossDomainOwnable2} from "@eth-optimism/contracts-bedrock/contracts/L2/CrossDomainOwnable2.sol";
import {Predeploys} from "@eth-optimism/contracts-bedrock/contracts/libraries/Predeploys.sol";
import {CommonTest, Messenger_Initializer} from "@eth-optimism/contracts-bedrock/contracts/test/CommonTest.t.sol";
import {AddressAliasHelper} from "@eth-optimism/contracts-bedrock/contracts/vendor/AddressAliasHelper.sol";
import {Encoding} from "@eth-optimism/contracts-bedrock/contracts/libraries/Encoding.sol";
import {Bytes32AddressLib} from "solmate/src/utils/Bytes32AddressLib.sol";

/// @title OpWorldIDTest
/// @author Worldcoin
/// @notice A test contract for OpWorldID
/// @dev The OpWorldID contract is deployed on Optimism and is called by the L1 Proxy contract.
/// @dev This contract uses the Optimism CommonTest.t.sol tool suite to test the OpWorldID contract.
/// For more information on the CommonTest.t.sol tool suite, please see the CommonTest.t.sol source code.
/// CommonTest.t.sol - Link https://github.com/ethereum-optimism/optimism/blob/e768427b369f6dd642bee1755574537d7424f847/packages/contracts-bedrock/contracts/test/CommonTest.t.sol
/// CrossDomainOwnable2.t.sol - Link https://github.com/ethereum-optimism/optimism/blob/e768427b369f6dd642bee1755574537d7424f847/packages/contracts-bedrock/contracts/test/CrossDomainOwnable2.t.sol
contract OpWorldIDTest is Messenger_Initializer {
    /*//////////////////////////////////////////////////////////////
                                WORLD ID
    //////////////////////////////////////////////////////////////*/
    /// @notice The OpWorldID contract
    OpWorldID internal id;

    /// @notice The root of the merkle tree before the first update
    uint256 public preRoot = 0x18f43331537ee2af2e3d758d50f72106467c6eea50371dd528d57eb2b856d238;

    /// @notice The root of the merkle tree after the first update
    uint256 public newRoot = 0x5c1e52b41a571293b30efacd2afdb7173b20cfaf1f646c4ac9f96eb75848270;

    function setUp() public override {
        /// @notice CrossDomainOwnable2 setup
        super.setUp();

        /// @notice The timestamp of the root of the merkle tree before the first update
        uint128 preRootTimestamp = uint128(block.timestamp);

        /// @notice Initialize the OpWorldID contract
        id = new OpWorldID();

        id.initialize(preRoot, preRootTimestamp);

        /// @dev label important addresses
        vm.label(address(this), "Sender");
        vm.label(address(id), "OPWorldID");
    }

    function test_onlyOwner_notMessenger_reverts() external {
        uint128 newRootTimestamp = uint128(block.timestamp + 100);

        vm.expectRevert("CrossDomainOwnable2: caller is not the messenger");
        id.receiveRoot(newRoot, newRootTimestamp);
    }

    function test_onlyOwner_notOwner_reverts() external {
        // set the xDomainMsgSender storage slot
        bytes32 key = bytes32(uint256(204));
        bytes32 value = Bytes32AddressLib.fillLast12Bytes(address(alice));
        vm.store(address(L2Messenger), key, value);

        uint128 newRootTimestamp = uint128(block.timestamp + 100);

        vm.prank(address(L2Messenger));
        vm.expectRevert("CrossDomainOwnable2: caller is not the owner");
        id.receiveRoot(newRoot, newRootTimestamp);
    }

    /// @notice Test that you can insert new root and check if it is valid
    function test_receiveVerifyRoot_succeeds() public {
        address owner = id.owner();
        uint128 newRootTimestamp = uint128(block.timestamp + 100);
        vm.warp(block.timestamp + 200);

        // set the xDomainMsgSender storage slot to the L1Messenger
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(L1Messenger)));
        L2Messenger.relayMessage(
            Encoding.encodeVersionedNonce(0, 1),
            owner,
            address(id),
            0,
            0,
            abi.encodeWithSelector(id.receiveRoot.selector, newRoot, newRootTimestamp)
        );

        assertTrue(id.checkValidRoot(newRoot));
    }

    /// @notice Test that a root that hasn't been inserted is invalid
    function test_receiveVerifyInvalidRoot_reverts() public {
        address owner = id.owner();

        uint128 newRootTimestamp = uint128(block.timestamp + 100);
        vm.warp(block.timestamp + 200);
        uint256 randomRoot = 0x712cab3414951eba341ca234aef42142567c6eea50371dd528d57eb2b856d238;

        // set the xDomainMsgSender storage slot to the L1Messenger
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(L1Messenger)));
        L2Messenger.relayMessage(
            Encoding.encodeVersionedNonce(1, 1),
            owner,
            address(id),
            0,
            0,
            abi.encodeWithSelector(id.receiveRoot.selector, newRoot, newRootTimestamp)
        );

        vm.expectRevert(OpWorldID.NonExistentRoot.selector);
        id.checkValidRoot(randomRoot);
    }

    /// @notice Test that you can insert a root and check it has expired if more than 7 days have passed
    function test_expiredRoot_reverts() public {
        address owner = id.owner();

        uint128 newRootTimestamp = uint128(block.timestamp + 100);

        // set the xDomainMsgSender storage slot to the L1Messenger
        vm.prank(AddressAliasHelper.applyL1ToL2Alias(address(L1Messenger)));
        L2Messenger.relayMessage(
            Encoding.encodeVersionedNonce(2, 1),
            owner,
            address(id),
            0,
            0,
            abi.encodeWithSelector(id.receiveRoot.selector, newRoot, newRootTimestamp)
        );
        vm.warp(block.timestamp + 8 days);

        vm.expectRevert(OpWorldID.ExpiredRoot.selector);
        id.checkValidRoot(newRoot);
    }
}
