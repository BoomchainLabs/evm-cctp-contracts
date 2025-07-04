/*
 * Copyright (c) 2024, Circle Internet Financial Limited.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
pragma solidity 0.7.6;
pragma abicoder v2;

import {ScriptV2TestUtils} from "./ScriptV2TestUtils.sol";
import {AdminUpgradableProxy} from "../../../src/proxy/AdminUpgradableProxy.sol";
import {DeployImplementationsV2Script} from "../../../scripts/v2/DeployImplementationsV2.s.sol";
import {DeployProxiesV2Script} from "../../../scripts/v2/DeployProxiesV2.s.sol";
import {MessageTransmitterV2} from "../../../src/v2/MessageTransmitterV2.sol";
import {TokenMessengerV2} from "../../../src/v2/TokenMessengerV2.sol";
import {SALT_MESSAGE_TRANSMITTER, SALT_TOKEN_MESSENGER} from "../../../scripts/v2/Salts.sol";
import {AddressUtils} from "../../../src/messages/v2/AddressUtils.sol";

contract DeployProxiesV2Test is ScriptV2TestUtils {
    using AddressUtils for address;
    using AddressUtils for bytes32;

    DeployProxiesV2Script deployProxiesV2Script;

    function setUp() public {
        _deployCreate2Factory();
        _deployImplementations();
        _deployProxies();
        deployProxiesV2Script = new DeployProxiesV2Script();
    }

    function testDeployMessageTransmitterV2() public {
        // create2 address
        address predicted = create2Factory.computeAddress(
            SALT_MESSAGE_TRANSMITTER,
            keccak256(
                deployProxiesV2Script.getProxyCreationCode(
                    address(create2Factory),
                    address(create2Factory),
                    ""
                )
            )
        );
        assertEq(address(messageTransmitterV2), predicted);
        // owner
        assertEq(messageTransmitterV2.owner(), deployer);
        // domain
        assertEq(messageTransmitterV2.localDomain(), uint256(sourceDomain));
        // attester
        assertEq(messageTransmitterV2.attesterManager(), deployer);
        assertTrue(messageTransmitterV2.isEnabledAttester(attester1));
        assertTrue(messageTransmitterV2.isEnabledAttester(attester2));
        assertEq(messageTransmitterV2.signatureThreshold(), 2);
        // maxMessageBodySize
        assertEq(messageTransmitterV2.maxMessageBodySize(), maxMessageBodySize);
        // version
        assertEq(messageTransmitterV2.version(), uint256(1));
        // pauser
        assertEq(messageTransmitterV2.pauser(), pauser);
        // rescuer
        assertEq(messageTransmitterV2.rescuer(), rescuer);
        // admin
        assertEq(
            AdminUpgradableProxy(payable(address(messageTransmitterV2)))
                .admin(),
            messageTransmitterV2AdminAddress
        );
    }

    function testDeployTokenMessengerV2() public {
        // create2 address
        address predicted = create2Factory.computeAddress(
            SALT_TOKEN_MESSENGER,
            keccak256(
                deployProxiesV2Script.getProxyCreationCode(
                    address(create2Factory),
                    address(create2Factory),
                    ""
                )
            )
        );
        assertEq(address(tokenMessengerV2), predicted);
        // message transmitter
        assertEq(
            address(tokenMessengerV2.localMessageTransmitter()),
            address(messageTransmitterV2)
        );
        // message body version
        assertEq(
            tokenMessengerV2.messageBodyVersion(),
            uint256(_messageBodyVersion)
        );
        // owner
        assertEq(tokenMessengerV2.owner(), deployer);
        // rescuer
        assertEq(tokenMessengerV2.rescuer(), rescuer);
        // fee recipient
        assertEq(tokenMessengerV2.feeRecipient(), feeRecipient);
        // deny lister
        assertEq(tokenMessengerV2.denylister(), denyLister);
        // min fee controller
        assertEq(tokenMessengerV2.minFeeController(), minFeeController);
        // min fee
        assertEq(tokenMessengerV2.minFee(), minFee);
        // remote token messengers
        for (uint256 i = 0; i < remoteDomains.length; i++) {
            uint32 remoteDomain = remoteDomains[i];
            assertEq(
                tokenMessengerV2.remoteTokenMessengers(remoteDomain),
                remoteTokenMessengerV2s[i].toBytes32()
            );
        }
        // admin
        assertEq(
            AdminUpgradableProxy(payable(address(tokenMessengerV2))).admin(),
            tokenMessengerV2AdminAddress
        );
    }

    function testConfigureTokenMinterV2() public {
        _validateExpectedTokenMinterV2State();
    }

    function testConfigureTokenMinterV2WhenCalledSeparately() public {
        // configureTokenMinterV2() can be called through a standalone entrypoint in the deploy script
        // To test, we'll first unset all the correspond values

        address randomAddress = address(12345);

        vm.startPrank(deployer);
        // Unlink token pairs
        for (uint256 i = 0; i < remoteDomains.length; i++) {
            tokenMinterV2.unlinkTokenPair(
                token,
                remoteDomains[i],
                remoteTokens[i].toBytes32()
            );
        }
        // Remove TokenMessenger
        tokenMinterV2.removeLocalTokenMessenger();

        // Set roles to a random, different address
        tokenMinterV2.updatePauser(randomAddress);
        tokenMinterV2.updateRescuer(randomAddress);
        // set the pendingOwner to deployer, since the script call acceptOwnership()
        tokenMinterV2.transferOwnership(deployer);
        // Modify maxBurnAmount
        tokenMinterV2.setMaxBurnAmountPerMessage(token, 0);

        vm.stopPrank();

        // Now, call configureTokenMinterV2() separately
        deployProxiesV2Script.setUp();
        deployProxiesV2Script.configureTokenMinterV2();

        // Validate the expected state
        _validateExpectedTokenMinterV2State();
    }

    function _validateExpectedTokenMinterV2State() internal {
        // token controller
        assertEq(tokenMinterV2.tokenController(), deployer);
        // token messenger
        assertEq(
            tokenMinterV2.localTokenMessenger(),
            address(tokenMessengerV2)
        );
        // pauser
        assertEq(tokenMinterV2.pauser(), pauser);
        // rescuer
        assertEq(tokenMinterV2.rescuer(), rescuer);
        // max burn per msg
        assertEq(
            tokenMinterV2.burnLimitsPerMessage(token),
            maxBurnAmountPerMessage
        );
        // linked token pairs
        for (uint256 i = 0; i < remoteDomains.length; i++) {
            address remoteToken = remoteTokens[i];
            bytes32 remoteKey = keccak256(
                abi.encodePacked(remoteDomains[i], remoteToken.toBytes32())
            );
            assertEq(tokenMinterV2.remoteTokensToLocalTokens(remoteKey), token);
        }
    }
}
