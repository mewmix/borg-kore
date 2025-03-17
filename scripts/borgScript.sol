// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import "../test/libraries/safe.t.sol";
import "../src/borgCore.sol";
import "../src/libs/auth.sol";
import "../src/implants/failSafeImplant.sol";
import "safe-contracts/proxies/SafeProxyFactory.sol";

contract borgScript is Script {
    // Contracts to be deployed
    borgCore public core;
    BorgAuth public auth;
    SignatureHelper public helper;
    failSafeImplant public failSafe;
    IGnosisSafe public safe;

    // Dummy configuration variables
    address public weth = 0x4200000000000000000000000000000000000006; // Base WETH
    address public recoveryAddress = address(0xdead); // Dummy recovery address
    address public executor;
    address public owner2;
    address public owner1;

    // Base Chain Safe deployment addresses
    address constant SAFE_FACTORY = 0xa6B71E26C5e0845f74c812102Ca7114b6a896AB2; // SafeProxyFactory on Base
    address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552; // Safe singleton on Base

    // Dummy private keys (Foundry test keys)
    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant OWNER2_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant EXECUTOR_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    function run() public {
        // Derive dummy addresses from private keys
        owner1 = vm.addr(DEPLOYER_PK);
        owner2 = vm.addr(OWNER2_PK);
        executor = vm.addr(EXECUTOR_PK);

        vm.startBroadcast(DEPLOYER_PK);

        // Deploy Gnosis Safe
        SafeProxyFactory factory = SafeProxyFactory(SAFE_FACTORY);
        address[] memory owners = new address[](2);
        owners[0] = owner1;
        owners[1] = owner2;
        uint256 threshold = 1;

        bytes memory initializer = abi.encodeWithSignature(
            "setup(address[],uint256,address,bytes,address,address,uint256,address)",
            owners,
            threshold,
            address(0),
            bytes(""),
            address(0),
            address(0),
            0,
            address(0)
        );

        // Use createProxyWithNonce instead of createProxy
        uint256 saltNonce = 0; // Define a salt nonce (can be any unique value)
        address proxy = address(factory.createProxyWithNonce(SAFE_SINGLETON, initializer, saltNonce));
        safe = IGnosisSafe(proxy);
        console.log("Gnosis Safe deployed at:", address(safe));
        console.log("Safe owners - Owner1:", owner1, "Owner2:", owner2);
        console.log("Safe threshold:", threshold);

        // Deploy BorgAuth
        auth = new BorgAuth();
        console.log("BorgAuth deployed at:", address(auth));

        // Deploy borgCore
        borgCore.borgModes _mode = borgCore.borgModes(0); // Whitelist mode
        string memory _identifier = "Submission Dev BORG";
        core = new borgCore(auth, 0x3, _mode, _identifier, address(safe));
        console.log("borgCore deployed at:", address(core));

        // Deploy SignatureHelper and set it
        helper = new SignatureHelper();
        core.setSignatureHelper(helper);
        console.log("SignatureHelper set at:", address(helper));

        // Deploy failSafeImplant with recovery address
        failSafe = new failSafeImplant(auth, address(safe), executor);
        bytes memory failsafeData = abi.encodeWithSignature("enableModule(address)", address(failSafe));
        executeData(address(safe), 0, failsafeData);
        console.log("failSafeImplant deployed at:", address(failSafe));
        console.log("failSafeImplant enabled as module on Safe");

        // Set borgCore as guard
        bytes memory guardData = abi.encodeWithSignature("setGuard(address)", address(core));
        executeData(address(safe), 0, guardData);
        console.log("borgCore set as guard on Safe");

        // Whitelist WETH methods (simplified for testing)
        bytes32[] memory matches = new bytes32[](1);
        matches[0] = keccak256(abi.encodePacked(owner2));

        core.addUnsignedRangeParameterConstraint(
            weth,
            "approve(address,uint256)",
            borgCore.ParamType.UINT,
            0,
            999999999999999999, // < 1 ETH
            36,
            32
        );
        core.addExactMatchParameterConstraint(
            weth,
            "approve(address,uint256)",
            borgCore.ParamType.ADDRESS,
            matches,
            4,
            32
        );
        core.updateMethodCooldown(weth, "approve(address,uint256)", 604800);
        console.log("WETH approve method whitelisted with constraints");

        core.addUnsignedRangeParameterConstraint(
            weth,
            "transfer(address,uint256)",
            borgCore.ParamType.UINT,
            0,
            999999999999999999, // < 1 ETH
            36,
            32
        );
        core.addExactMatchParameterConstraint(
            weth,
            "transfer(address,uint256)",
            borgCore.ParamType.ADDRESS,
            matches,
            4,
            32
        );
        core.updateMethodCooldown(weth, "transfer(address,uint256)", 604800);
        console.log("WETH transfer method whitelisted with constraints");

        // Transfer ownership to executor
        auth.updateRole(executor, 99);
        auth.zeroOwner();
        console.log("BorgAuth ownership transferred to executor:", executor);

        vm.stopBroadcast();
    }

    function executeData(address to, uint256 value, bytes memory data) public {
        uint8 operation = 0;
        uint256 safeTxGas = 0;
        uint256 baseGas = 0;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address refundReceiver = address(0);
        uint256 nonce = safe.nonce();
        bytes memory signature = getSignature(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );
        safe.execTransaction(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            signature
        );
    }

    function getSignature(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation,
        uint256 safeTxGas,
        uint256 baseGas,
        uint256 gasPrice,
        address gasToken,
        address refundReceiver,
        uint256 nonce
    ) public view returns (bytes memory) {
        bytes memory txHashData = safe.encodeTransactionData(
            to,
            value,
            data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(DEPLOYER_PK, keccak256(txHashData));
        return abi.encodePacked(r, s, v);
    }
}
