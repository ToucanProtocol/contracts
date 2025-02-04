// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: LicenseRef-Proprietary
pragma solidity ^0.8.13;

import '@openzeppelin/contracts-upgradeable/proxy/ClonesUpgradeable.sol';
import '@openzeppelin/contracts/proxy/beacon/BeaconProxy.sol';
import '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import 'forge-std/Test.sol';

import '../../../contracts/PuroToucanCarbonOffsets.sol';
import '../../../contracts/CarbonOffsetBatches.sol';
import '../../../contracts/PuroToucanCarbonOffsetsFactory.sol';
import '../../../contracts/ToucanContractRegistry.sol';
import '../../../contracts/CarbonProjectVintages.sol';
import '../../../contracts/CarbonProjects.sol';
import '../../../contracts/ToucanCarbonOffsetsEscrow.sol';
import '../../../contracts/retirements/RetirementCertificates.sol';
import './ToucanCarbonOffsetsHandler.sol';

/**
 *  This Smart Contract is responsible for:
 * - setting up the part of the protocol relevant for the testing of the given invariant
 * - instantiating a handler to drive the fuzzing
 * - checking the invariant: TCO2 tokens are backed 1:1 by batches.
 * The contract can be extended to verify more variants that would require the same setup.
 */
contract Tco2BackedByBatchesInvariant is Test {
    ToucanContractRegistry toucanRegistry;
    CarbonProjectVintages vintages;
    CarbonProjects projects;
    CarbonOffsetBatches batches;
    PuroToucanCarbonOffsetsFactory puroTco2Factory;
    ToucanCarbonOffsetsEscrow toucanCarbonOffsetsEscrow;
    RetirementCertificates retirementCertificates;

    ToucanCarbonOffsetsHandler tco2Handler;

    function setUp() external {
        tco2Handler = new ToucanCarbonOffsetsHandler();

        _setupToucanRegistry();
        _setupProjects();
        _setupVintages();
        _setupBatches();
        _setupToucanCarbonOffsetsFactory();
        _setupToucanCarbonOffsets();
        _setupToucanCarbonOffsetsEscrow();
        _setupRetirementCertificates();

        // last configuration steps
        puroTco2Factory.transferOwnership(address(tco2Handler));
        tco2Handler.configure(projects, vintages, batches, puroTco2Factory, address(this));

        // limit the fuzzer scope
        targetContract(address(tco2Handler));
        bytes4[] memory selectors = new bytes4[](7);
        selectors[0] = tco2Handler.addTCO2.selector;
        selectors[1] = tco2Handler.tokenize.selector;
        selectors[2] = tco2Handler.requestRetirement.selector;
        selectors[3] = tco2Handler.finalizeRetirement.selector;
        selectors[4] = tco2Handler.requestDetokenization.selector;
        selectors[5] = tco2Handler.finalizeDetokenization.selector;
        selectors[6] = tco2Handler.defractionalize.selector;
        targetSelector(FuzzSelector(address(tco2Handler), selectors));
    }

    function _setupToucanRegistry() internal {
        toucanRegistry = new ToucanContractRegistry();
        excludeContract(address(toucanRegistry));
        address[] memory accounts = new address[](2);
        accounts[0] = accounts[1] = address(this);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = toucanRegistry.PAUSER_ROLE();
        roles[1] = toucanRegistry.DEFAULT_ADMIN_ROLE();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(toucanRegistry),
            abi.encodeWithSignature('initialize(address[],bytes32[])', accounts, roles)
        );
        toucanRegistry = ToucanContractRegistry(address(proxy));
    }

    function _setupProjects() internal {
        projects = new CarbonProjects();
        excludeContract(address(projects));
        address[] memory accounts = new address[](3);
        accounts[0] = accounts[1] = address(this);
        accounts[2] = address(tco2Handler);
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = projects.MANAGER_ROLE();
        roles[1] = projects.DEFAULT_ADMIN_ROLE();
        roles[2] = projects.MANAGER_ROLE();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(projects),
            abi.encodeWithSignature('initialize(address[],bytes32[])', accounts, roles)
        );
        projects = CarbonProjects(address(proxy));
        projects.setToucanContractRegistry(address(toucanRegistry));
        toucanRegistry.setCarbonProjectsAddress(address(projects));
    }

    function _setupVintages() internal {
        vintages = new CarbonProjectVintages();
        excludeContract(address(vintages));
        address[] memory accounts = new address[](3);
        accounts[0] = accounts[1] = address(this);
        accounts[2] = address(tco2Handler);
        bytes32[] memory roles = new bytes32[](3);
        roles[0] = vintages.MANAGER_ROLE();
        roles[1] = vintages.DEFAULT_ADMIN_ROLE();
        roles[2] = vintages.MANAGER_ROLE();
        ERC1967Proxy proxy = new ERC1967Proxy(
            address(vintages),
            abi.encodeWithSignature('initialize(address[],bytes32[])', accounts, roles)
        );
        vintages = CarbonProjectVintages(address(proxy));
        vintages.setToucanContractRegistry(address(toucanRegistry));
        toucanRegistry.setCarbonProjectVintagesAddress(address(vintages));
    }

    function _setupBatches() internal {
        CarbonOffsetBatches implBatches = new CarbonOffsetBatches();
        excludeContract(address(implBatches));

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(implBatches),
            abi.encodeWithSignature('initialize(address)', address(toucanRegistry))
        );
        batches = CarbonOffsetBatches(address(proxy));
        batches.grantRole(batches.VERIFIER_ROLE(), address(this));
        batches.grantRole(batches.VERIFIER_ROLE(), address(tco2Handler));
        batches.grantRole(batches.TOKENIZER_ROLE(), address(tco2Handler));
        batches.setSupportedRegistry('puro', true);

        toucanRegistry.setCarbonOffsetBatchesAddress(address(batches));
    }

    function _setupToucanCarbonOffsetsFactory() internal {
        puroTco2Factory = new PuroToucanCarbonOffsetsFactory();
        address[] memory accounts = new address[](4);
        accounts[0] = address(this);
        accounts[1] = accounts[2] = accounts[3] = address(tco2Handler);
        bytes32[] memory roles = new bytes32[](4);
        roles[0] = puroTco2Factory.DEFAULT_ADMIN_ROLE();
        roles[1] = puroTco2Factory.DETOKENIZER_ROLE();
        roles[2] = puroTco2Factory.TOKENIZER_ROLE();
        roles[3] = (new PuroToucanCarbonOffsets()).RETIREMENT_ROLE();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(puroTco2Factory),
            abi.encodeWithSelector(
                puroTco2Factory.initialize.selector,
                toucanRegistry,
                accounts,
                roles
            )
        );
        puroTco2Factory = PuroToucanCarbonOffsetsFactory(address(proxy));

        toucanRegistry.setToucanCarbonOffsetsFactoryAddress(address(puroTco2Factory));
    }

    function _setupToucanCarbonOffsets() internal {
        PuroToucanCarbonOffsets tco2Beacon = new PuroToucanCarbonOffsets();
        UpgradeableBeacon beacon = new UpgradeableBeacon(address(tco2Beacon));
        puroTco2Factory.setBeacon(address(beacon));
    }

    function _setupRetirementCertificates() internal {
        retirementCertificates = new RetirementCertificates();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(retirementCertificates),
            abi.encodeWithSelector(
                retirementCertificates.initialize.selector,
                toucanRegistry,
                'test.com'
            )
        );
        retirementCertificates = RetirementCertificates(address(proxy));

        toucanRegistry.setRetirementCertificatesAddress(address(retirementCertificates));
    }

    function _setupToucanCarbonOffsetsEscrow() internal {
        toucanCarbonOffsetsEscrow = new ToucanCarbonOffsetsEscrow();
        address[] memory accounts = new address[](2);
        accounts[0] = accounts[1] = address(this);
        bytes32[] memory roles = new bytes32[](2);
        roles[0] = toucanCarbonOffsetsEscrow.PAUSER_ROLE();
        roles[1] = toucanCarbonOffsetsEscrow.DEFAULT_ADMIN_ROLE();

        ERC1967Proxy proxy = new ERC1967Proxy(
            address(toucanCarbonOffsetsEscrow),
            abi.encodeWithSelector(
                toucanCarbonOffsetsEscrow.initialize.selector,
                toucanRegistry,
                accounts,
                roles
            )
        );
        toucanCarbonOffsetsEscrow = ToucanCarbonOffsetsEscrow(address(proxy));

        toucanRegistry.setToucanCarbonOffsetsEscrowAddress(address(toucanCarbonOffsetsEscrow));
    }

    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function invariant_tco2BackedByBatches1to1() external payable {
        address[] memory tco2s = puroTco2Factory.getContracts();

        for (uint256 tco2Index = 0; tco2Index < tco2s.length; tco2Index++) {
            PuroToucanCarbonOffsets tco2 = PuroToucanCarbonOffsets(tco2s[tco2Index]);
            uint256 tco2Supply = tco2.totalSupply();
            uint256 totalBatches = 0;
            for (uint256 i = 0; i < batches.balanceOf(address(tco2)); i++) {
                uint256 tokenId = batches.tokenOfOwnerByIndex(address(tco2), i);
                (, uint256 tokenQuantity, BatchStatus status) = batches.getBatchNFTData(tokenId);
                if (
                    status == BatchStatus.Confirmed ||
                    status == BatchStatus.DetokenizationRequested ||
                    status == BatchStatus.RetirementRequested
                ) totalBatches += tokenQuantity * 1e18;
            }

            assertEq(tco2Supply, totalBatches);
        }
    }

    receive() external payable {}
}
