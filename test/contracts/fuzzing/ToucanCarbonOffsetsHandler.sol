// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: LicenseRef-Proprietary
pragma solidity ^0.8.13;

import '@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol';
import '@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol';
import 'forge-std/Test.sol';

import '../../../contracts/PuroToucanCarbonOffsets.sol';
import '../../../contracts/PuroToucanCarbonOffsetsFactory.sol';
import '../../../contracts/ToucanContractRegistry.sol';
import '../../../contracts/CarbonProjects.sol';
import '../../../contracts/CarbonProjectVintages.sol';
import '../../../contracts/CarbonOffsetBatches.sol';
import '../../../contracts/libraries/Strings.sol';
import {Range, RangeProtection} from './libraries/RangeProtection.sol';

/**
 * Main responsibilities:
 * - expose the protocol functions that are relevant to the simulation
 * - constraint the input of the fuzzer to prevent unnecessary trials
 * - orchestrate the execution to make sure some pre-conditions are met (e.g.: a vintage exists before it's tokenized)
 * Overall, the main objective is to avoid reverts during the execution and allow the fuzzer to explore
 * an as wide as possible surface of valid states.
 */
contract ToucanCarbonOffsetsHandler is Test {
    using Strings for uint256;
    using RangeProtection for Range[];

    address _batchOwner;
    CarbonProjects _projects;
    CarbonProjectVintages _vintages;
    CarbonOffsetBatches _batches;
    PuroToucanCarbonOffsetsFactory _puroTco2Factory;
    mapping(uint256 => Range[]) _ranges;

    string standard = 'PURO';
    string methodology = 'test';
    string region = 'test';
    string storageMethod = 'test';
    string method = 'test';
    string emissionType = 'test';
    string category = 'test';
    string uri = 'test';
    address beneficiary = 0xd8dA6BF26964aF9D7eEd9e03E53415D37aA96045;

    string name = 'test';
    uint64 startTime = 1480464000;
    uint64 endTime = 2480464000;
    bool isCorsiaCompliant = false;
    bool isCCPcompliant = false;
    string coBenefits = 'test';
    string correspAdjustment = 'test';
    string additionalCertification = 'test';
    string registry = 'puro';

    uint256 _currentVintageId = 0;
    uint256 _currentBatchTokenId = 0;

    struct FuzzerRequest {
        PuroToucanCarbonOffsets tco2;
        uint256 requestId;
    }

    FuzzerRequest[] retirementRequests;
    FuzzerRequest[] detokenizationRequests;

    function configure(
        CarbonProjects projects,
        CarbonProjectVintages vintages,
        CarbonOffsetBatches batches,
        PuroToucanCarbonOffsetsFactory puroTco2Factory,
        address batchOwner
    ) external {
        _batchOwner = batchOwner;
        _projects = projects;
        _vintages = vintages;
        _batches = batches;
        _puroTco2Factory = puroTco2Factory;
    }

    function defractionalize(uint256 tokenId) external {
        if (_currentBatchTokenId == 0) {
            return;
        }
        tokenId = bound(tokenId, 1, _currentBatchTokenId);

        if (_batches.ownerOf(tokenId) != address(this)) {
            return;
        }

        (uint256 projectVintageTokenId, , ) = _batches.getBatchNFTData(tokenId);
        PuroToucanCarbonOffsets tco2 = PuroToucanCarbonOffsets(
            _puroTco2Factory.pvIdtoERC20(projectVintageTokenId)
        );
        tco2.defractionalize(tokenId);
    }

    function tokenize(
        uint256 seed,
        uint256 quantity,
        uint256 vintageId
    ) public {
        if (_currentVintageId == 0) {
            return;
        }

        vintageId = bound(vintageId, 1, _currentVintageId);
        quantity = _boundQuantity(quantity, vintageId);
        if (quantity == 0) {
            return;
        }

        (string memory serialNumber, bool hasOverlap) = _getSerialNumber(seed, quantity);
        if (hasOverlap) {
            return;
        }

        _currentBatchTokenId = _batches.tokenize(address(this), serialNumber, quantity, vintageId);
    }

    function _boundQuantity(uint256 quantity, uint256 vintageId) internal view returns (uint256) {
        PuroToucanCarbonOffsets tco2 = PuroToucanCarbonOffsets(
            _puroTco2Factory.pvIdtoERC20(vintageId)
        );

        uint256 remaining = tco2.getRemaining();
        if (remaining / 1e18 == 0) {
            return 0;
        }
        return bound(quantity, 1e18, remaining) / 1e18;
    }

    function _getSerialNumber(uint256 seed, uint256 quantity)
        internal
        returns (string memory serialNumber, bool hasOverlap)
    {
        uint256 start = _getStart(seed);
        uint256 end = start + quantity;

        // Perform range overlap check
        Range[] storage ranges = _ranges[seed];
        (, string memory errorMsg) = ranges.findInsertPosition(start, end);
        hasOverlap = bytes(errorMsg).length > 0;
        if (!hasOverlap) {
            ranges.add(start, end);
        }

        return (
            string(
                abi.encodePacked(
                    _get10Chars(seed),
                    '-aaaaaaa-aaaaaaa-aaa-aaaaa_',
                    start.toString(),
                    '-',
                    end.toString()
                )
            ),
            hasOverlap
        );
    }

    function requestRetirement(
        uint256 tokenId,
        uint256 amount,
        string memory retiringEntityString,
        string memory beneficiaryString,
        string memory retirementMessage,
        string memory beneficiaryLocation,
        string memory consumptionCountryCode,
        uint256 consumptionPeriodStart,
        uint256 consumptionPeriodEnd
    ) public {
        (
            uint256 actualTokenId,
            uint256 actualAmount,
            uint256 projectVintageTokenId,
            bool exit
        ) = _getParameters(tokenId, amount);
        if (exit) {
            return;
        }

        PuroToucanCarbonOffsets tco2 = PuroToucanCarbonOffsets(
            _puroTco2Factory.pvIdtoERC20(projectVintageTokenId)
        );
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = actualTokenId;
        CreateRetirementRequestParams memory requestParams = CreateRetirementRequestParams(
            tokenIds,
            actualAmount,
            retiringEntityString,
            beneficiary,
            beneficiaryString,
            retirementMessage,
            beneficiaryLocation,
            consumptionCountryCode,
            consumptionPeriodStart,
            consumptionPeriodEnd
        );

        uint256 requestId = tco2.requestRetirement(requestParams);
        retirementRequests.push(FuzzerRequest(tco2, requestId));
    }

    function finalizeRetirement(uint256 requestIdIndex) external {
        if (retirementRequests.length == 0) {
            return;
        }

        requestIdIndex = requestIdIndex % retirementRequests.length;
        FuzzerRequest storage request = retirementRequests[requestIdIndex];

        request.tco2.finalizeRetirement(request.requestId);

        _cleanRetirementRequests(requestIdIndex);
    }

    function revertRetirement(uint256 requestIdIndex) external {
        if (retirementRequests.length == 0) {
            return;
        }

        requestIdIndex = requestIdIndex % retirementRequests.length;
        FuzzerRequest storage request = retirementRequests[requestIdIndex];

        request.tco2.revertRetirement(request.requestId);

        _cleanRetirementRequests(requestIdIndex);
    }

    function requestDetokenization(uint256 tokenId, uint256 amount) public {
        (
            uint256 actualTokenId,
            uint256 actualAmount,
            uint256 projectVintageTokenId,
            bool exit
        ) = _getParameters(tokenId, amount);
        if (exit) {
            return;
        }

        PuroToucanCarbonOffsets tco2 = PuroToucanCarbonOffsets(
            _puroTco2Factory.pvIdtoERC20(projectVintageTokenId)
        );
        uint256[] memory tokenIds = new uint256[](1);
        tokenIds[0] = actualTokenId;
        uint256 requestId = tco2.requestDetokenization(tokenIds, actualAmount);
        detokenizationRequests.push(FuzzerRequest(tco2, requestId));
    }

    function finalizeDetokenization(uint256 requestIdIndex) external {
        if (detokenizationRequests.length == 0) {
            return;
        }

        requestIdIndex = requestIdIndex % detokenizationRequests.length;
        FuzzerRequest storage request = detokenizationRequests[requestIdIndex];

        request.tco2.finalizeDetokenization(request.requestId);

        _cleanDetokenizationRequests(requestIdIndex);
    }

    function revertDetokenization(uint256 requestIdIndex) external {
        if (retirementRequests.length == 0) {
            return;
        }

        requestIdIndex = requestIdIndex % detokenizationRequests.length;
        FuzzerRequest storage request = detokenizationRequests[requestIdIndex];

        request.tco2.revertDetokenization(request.requestId);

        _cleanDetokenizationRequests(requestIdIndex);
    }

    function addTCO2(string calldata projectId, uint256 totalVintageQuantity) public {
        if (bytes(projectId).length == 0 || _projects.projectIds(projectId)) {
            return;
        }

        // we limit the quantity to a value that we know would not break the serial number parsing
        totalVintageQuantity = bound(totalVintageQuantity, 1, 5000);

        uint256 projectTokenId = _projects.addNewProject(
            address(this),
            projectId,
            standard,
            method,
            region,
            storageMethod,
            method,
            emissionType,
            category,
            uri,
            beneficiary
        );

        VintageData memory vintageData = VintageData(
            name,
            startTime,
            endTime,
            projectTokenId,
            uint64(totalVintageQuantity),
            isCorsiaCompliant,
            isCCPcompliant,
            coBenefits,
            correspAdjustment,
            additionalCertification,
            uri,
            registry
        );
        _currentVintageId = _vintages.addNewVintage(address(this), vintageData);

        _puroTco2Factory.deployFromVintage(_currentVintageId);
    }

    function onERC721Received(
        address, /* operator */
        address, /* from */
        uint256, /* tokenId */
        bytes calldata /* data */
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }

    function _cleanRetirementRequests(uint256 requestIdIndex) internal {
        return _cleanRequests(requestIdIndex, retirementRequests);
    }

    function _cleanDetokenizationRequests(uint256 requestIdIndex) internal {
        return _cleanRequests(requestIdIndex, detokenizationRequests);
    }

    function _cleanRequests(uint256 requestIdIndex, FuzzerRequest[] storage requests) internal {
        requestIdIndex = requestIdIndex % requests.length;
        for (uint256 i = requestIdIndex; i < requests.length - 1; i++) {
            requests[i] = requests[i + 1];
        }
        requests.pop();
    }

    function _get10Chars(uint256 seed) internal pure returns (string memory) {
        bytes memory chars = new bytes(10);
        bytes memory seedString = bytes(Strings.toString(seed));
        for (uint256 i = 0; i < 10; i++) {
            chars[i] = seedString[i % seedString.length];
        }

        return string(chars);
    }

    function _getStart(uint256 seed) internal pure returns (uint256) {
        // The modulus is set to 10000000000 for two reasons:
        // 1. It is large enough to cover tokenized quantities across all
        //    types of vintages. We are talking about 10 billion tonnes of
        //    carbon within a single vintage. Not happening in the real world.
        // 2. It is smaller than a number that would cause our v1-vs-v2 serial
        //    number parsing to break.
        return seed % 10000000000;
    }

    function _getParameters(uint256 tokenId, uint256 amount)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256,
            bool exit
        )
    {
        if (_currentBatchTokenId == 0) {
            return (0, 0, 0, true);
        }

        tokenId = bound(tokenId, 1, _currentBatchTokenId);
        (uint256 projectVintageTokenId, uint256 quantity, BatchStatus status) = _batches
            .getBatchNFTData(tokenId);

        if (status != BatchStatus.Confirmed) {
            return (0, 0, 0, true);
        }

        if (quantity > 1) {
            amount = bound(amount, 1, quantity) * 1e18;
        } else {
            amount = 1e18;
        }

        return (tokenId, amount, projectVintageTokenId, false);
    }
}
