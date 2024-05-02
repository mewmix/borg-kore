// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";
import "../src/borgCore.sol";
import "../src/implants/ejectImplant.sol";
import "../src/implants/optimisticGrantImplant.sol";
import "../src/implants/daoVoteGrantImplant.sol";
import "../src/implants/daoVetoGrantImplant.sol";
import "../src/libs/conditions/signatureCondition.sol";
import "../src/implants/failSafeImplant.sol";
import "../test/libraries/mocks/MockGovToken.sol";
import "../test/libraries/mocks/MockDAO.sol";
import "metavest/MetaVesT.sol";
import "metavest/MetaVesTController.sol";
import "../src/libs/governance/flexGovernanceAdapater.sol";
import "../test/libraries/safe.t.sol";
import {console} from "forge-std/console.sol";

contract BaseScript is Script {
  address deployerAddress;
  
  address MULTISIG = 0x586410eFD34d1f9548434a08bDc411A56FD0EA40;//0x201308B728ACb48413CD27EC60B4FfaC074c2D01; //change this to the deployed Safe address
  address gxpl = 0x42069BaBe92462393FaFdc653A88F958B64EC9A3;
  IGnosisSafe safe;
  borgCore core;
  ejectImplant eject;
  BorgAuth auth;
  optimisticGrantImplant opGrant;
  daoVoteGrantImplant voteGrant;
  daoVetoGrantImplant vetoGrant;
  SignatureCondition sigCondition;
  failSafeImplant failSafe;
  MockERC20Votes govToken;
  MockDAO mockDao;
  MetaVesT metaVesT;
  MetaVesTController metaVesTController;
  FlexGovernanceAdapter governanceAdapter;

     function run() public {
            deployerAddress = vm.addr(vm.envUint("PRIVATE_KEY_DEPLOY"));
            uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY_DEPLOY");
            vm.startBroadcast(deployerPrivateKey);
            auth = new BorgAuth();
            auth.updateRole(gxpl, 98);
            //govToken = new MockERC20Votes("OnlyBORGs", "oBORG");
            govToken = MockERC20Votes(0x362C117C919dEC312f58a11B866356c5DBF86687);
            mockDao = new MockDAO(govToken, auth);
           // govToken.delegate(address(this));

            vm.stopBroadcast();
            safe = IGnosisSafe(MULTISIG);
            vm.startBroadcast(deployerPrivateKey);
            governanceAdapter = new FlexGovernanceAdapter(address(mockDao));
            metaVesTController = new MetaVesTController(MULTISIG, MULTISIG, address(govToken));
            vm.stopBroadcast();
            address controllerAddr = address(metaVesTController);
            vm.startBroadcast(deployerPrivateKey);
            metaVesT = new MetaVesT(MULTISIG, controllerAddr, MULTISIG, address(govToken));

            safe = IGnosisSafe(MULTISIG);
            core = new borgCore(auth, 0x1);
            failSafe = new failSafeImplant(auth, address(safe), address(this));
            eject = new ejectImplant(auth, MULTISIG, address(failSafe));
            opGrant = new optimisticGrantImplant(auth, MULTISIG, address(metaVesT), address(metaVesTController));

            voteGrant = new daoVoteGrantImplant(auth, MULTISIG, 600, 1e29, 50, address(governanceAdapter), address(mockDao), address(metaVesT), address(metaVesTController));
            auth.updateRole(address(voteGrant), 98);

            auth.updateRole(address(governanceAdapter), 98);
            auth.updateRole(address(mockDao), 99);

      
            executeSingle(getAddModule(address(opGrant)));
            executeSingle(getAddModule(address(voteGrant)));

            //dao deploys the core, with the dao as the owner.
            core.addContract(address(core));
            //Set the core as the guard for the safe
            executeSingle(getSetGuardData(address(MULTISIG)));
            vm.stopBroadcast();
            console.log("Deployed");
            console.log("Addresses:");
            console.log("Safe: ", MULTISIG);
            console.log("Core: ", address(core));
            console.log("Optimistic Grant: ", address(opGrant));
            console.log("Vote Grant: ", address(voteGrant));
            console.log("Auth: ", address(auth));
            console.log("Governance Adapter: ", address(governanceAdapter));
            console.log("MetaVesT: ", address(metaVesT));
            console.log("MetaVesT Controller: ", address(metaVesTController));
            console.log("Mock DAO: ", address(mockDao));
            console.log("Mock Gov Token: ", address(govToken));


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

        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(deployerPrivateKey, keccak256(txHashData));
        bytes memory signature = abi.encodePacked(r, s, v);
        return signature;
    }


    function executeSingle(GnosisTransaction memory tx) public {
        executeData(tx.to, 0, tx.data);
    }

    function executeSingle(GnosisTransaction memory tx, uint256 value) public {
        executeData(tx.to, 0, tx.data, value);
    }

    function getAddModule(address to) public view returns (GnosisTransaction memory) {
    bytes4 addContractMethod = bytes4(
        keccak256("enableModule(address)")
    );

    bytes memory guardData = abi.encodeWithSelector(
        addContractMethod,
        to
    );
    GnosisTransaction memory txData = GnosisTransaction({to: address(safe), value: 0, data: guardData}); 
    return txData;
    }
    
    function getSetGuardData(address to) public view returns (GnosisTransaction memory) {
    bytes4 setGuardFunctionSignature = bytes4(
        keccak256("setGuard(address)")
    );

     bytes memory guardData = abi.encodeWithSelector(
        setGuardFunctionSignature,
        address(core)
    );
    GnosisTransaction memory txData = GnosisTransaction({to: to, value: 0, data: guardData});
    return txData;
  }



    function executeData(
        address to,
        uint8 operation,
        bytes memory data
    ) public {
        uint256 value = 0;
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

    function executeData(
        address to,
        uint8 operation,
        bytes memory data, 
        uint256 _value
    ) public {
        uint256 value = _value;
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

}