// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/console.sol";
import {Script} from "forge-std/Script.sol";
import "../test/libraries/safe.t.sol";
import "../src/borgCore.sol";
import "../src/libs/auth.sol";
import "../src/implants/failSafeImplant.sol";
import "safe-contracts/proxies/SafeProxyFactory.sol";

contract submissionDeploy is Script {
    uint256 constant MAX_AMOUNT = 1 ether - 1; // Just under 1 ether
    uint256 constant COOLDOWN = 1 weeks;       // 1 week

    borgCore public core;
    BorgAuth public auth;
    SignatureHelper public helper;
    failSafeImplant public failSafe;
    IGnosisSafe public safe;

    address public weth = 0x4200000000000000000000000000000000000006;
    address public recoveryAddress = address(0xdead);
    address public executor;
    address public owner2;
    address public owner1;

    address constant SAFE_FACTORY = 0x4e1DCf7AD4e460CfD30791CCC4F9c8a4f820ec67;
    address constant SAFE_SINGLETON = 0xd9Db270c1B5E3Bd161E8c8503c55cEABeE709552;

    uint256 constant DEPLOYER_PK = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
    uint256 constant OWNER2_PK = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    uint256 constant EXECUTOR_PK = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;

    function run() public {
        owner1 = vm.addr(DEPLOYER_PK);
        owner2 = vm.addr(OWNER2_PK);
        executor = vm.addr(EXECUTOR_PK);

        vm.startBroadcast(DEPLOYER_PK);

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

        uint256 saltNonce = 0;
        address proxy = address(factory.createProxyWithNonce(SAFE_SINGLETON, initializer, saltNonce));
        safe = IGnosisSafe(proxy);
        console.log("Gnosis Safe deployed at:", address(safe));
        console.log("Safe owners - Owner1:", owner1, "Owner2:", owner2);
        console.log("Safe threshold:", threshold);

        auth = new BorgAuth();
        console.log("BorgAuth deployed at:", address(auth));

        borgCore.borgModes _mode = borgCore.borgModes(0);
        string memory _identifier = "Submission Dev BORG";
        core = new borgCore(auth, 0x3, _mode, _identifier, address(safe));
        console.log("borgCore deployed at:", address(core));

        helper = new SignatureHelper();
        core.setSignatureHelper(helper);
        console.log("SignatureHelper set at:", address(helper));

        failSafe = new failSafeImplant(auth, address(safe), executor);
        bytes memory failsafeData = abi.encodeWithSignature("enableModule(address)", address(failSafe));
        GnosisTransaction memory failsafeTx = GnosisTransaction(address(safe), 0, failsafeData);
        executeData(failsafeTx);
        console.log("failSafeImplant deployed at:", address(failSafe));
        console.log("failSafeImplant enabled as module on Safe");

        bytes memory guardData = abi.encodeWithSignature("setGuard(address)", address(core));
        GnosisTransaction memory guardTx = GnosisTransaction(address(safe), 0, guardData);
        executeData(guardTx);
        console.log("borgCore set as guard on Safe");

        bytes32[] memory matches = new bytes32[](1);
        matches[0] = keccak256(abi.encodePacked(owner2));

        core.addUnsignedRangeParameterConstraint(
            weth,
            "approve(address,uint256)",
            borgCore.ParamType.UINT,
            0,
            MAX_AMOUNT,
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
        core.updateMethodCooldown(weth, "approve(address,uint256)", COOLDOWN);
        console.log("WETH approve method whitelisted with constraints");

        core.addUnsignedRangeParameterConstraint(
            weth,
            "transfer(address,uint256)",
            borgCore.ParamType.UINT,
            0,
            MAX_AMOUNT,
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
        core.updateMethodCooldown(weth, "transfer(address,uint256)", COOLDOWN);
        console.log("WETH transfer method whitelisted with constraints");

        auth.updateRole(executor, 99);
        auth.zeroOwner();
        console.log("BorgAuth ownership transferred to executor:", executor);

        vm.stopBroadcast();
    }

    function executeData(GnosisTransaction memory tx) public {
        uint8 operation = 0;
        uint256 safeTxGas = 0;
        uint256 baseGas = 0;
        uint256 gasPrice = 0;
        address gasToken = address(0);
        address refundReceiver = address(0);
        uint256 nonce = safe.nonce();
        bytes memory signature = getSignature(
            tx.to,
            tx.value,
            tx.data,
            operation,
            safeTxGas,
            baseGas,
            gasPrice,
            gasToken,
            refundReceiver,
            nonce
        );
        safe.execTransaction(
            tx.to,
            tx.value,
            tx.data,
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
