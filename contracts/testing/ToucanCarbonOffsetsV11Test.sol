// SPDX-FileCopyrightText: 2021 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity >=0.8.4 <=0.8.14;

import '@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol';
import '@openzeppelin/contracts/utils/Context.sol';
import '@openzeppelin/contracts/utils/Strings.sol';

import '../interfaces/IToucanContractRegistry.sol';
import '../interfaces/ICarbonOffsetBatches.sol';
import '../CarbonProjects.sol';
import '../CarbonProjectVintages.sol';
import '../CarbonProjectVintageTypes.sol';
import '../ToucanCarbonOffsetsStorage.sol';
import '../ToucanCarbonOffsetsFactory.sol';
import '../CarbonOffsetBatchesTypes.sol';

interface IRetirementCertificatesUnreleasedTest {
    function mintCertificate(
        address sender,
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256 projectVintageTokenId,
        uint256 amount
    ) external;
}

/// @notice Implementation contract of the TCO2 tokens (ERC20)
/// These tokenized carbon offsets are specific to a vintage and its associated attributes
/// In order to mint TCO2s a user must deposit a matching CarbonOffsetBatch
/// @dev Each TCO2 contract is deployed via a Beacon Proxy in `ToucanCarbonOffsetsFactory`
contract ToucanCarbonOffsetsV11Test is
    ERC20Upgradeable,
    IERC721Receiver,
    ToucanCarbonOffsetsStorage
{
    // ----------------------------------------
    //      Events
    // ----------------------------------------

    event Retired(address sender, uint256 tokenId);
    event FeePaid(address bridger, uint256 fees);
    event FeeBurnt(address bridger, uint256 fees);

    // ----------------------------------------
    //              Modifiers
    // ----------------------------------------

    /// @dev modifier checks whether the `ToucanCarbonOffsetsFactory` is paused
    /// Since TCO2 contracts are permissionless, pausing does not function individually
    modifier whenNotPaused() {
        address ToucanCarbonOffsetsFactoryAddress = IToucanContractRegistry(
            contractRegistry
        ).toucanCarbonOffsetsFactoryAddress();
        bool _paused = ToucanCarbonOffsetsFactory(
            ToucanCarbonOffsetsFactoryAddress
        ).paused();
        require(!_paused, 'Error: TCO2 contract is paused');
        _;
    }

    // ----------------------------------------
    //      Upgradable related functions
    // ----------------------------------------

    /// @dev Returns the current version of the smart contract
    function version() external pure virtual returns (string memory) {
        return '1.1.0';
    }

    // ----------------------------------------
    //       Permissionless functions
    // ----------------------------------------

    function initialize(
        string memory name_,
        string memory symbol_,
        uint256 _projectVintageTokenId,
        address _contractRegistry
    ) external virtual initializer {
        __ERC20_init_unchained(name_, symbol_);
        projectVintageTokenId = _projectVintageTokenId;
        contractRegistry = _contractRegistry;
    }

    /// @notice Token name getter overriden to return the a name based on the carbon project data
    function name() public view virtual override returns (string memory) {
        string memory globalProjectId;
        string memory vintageName;
        (globalProjectId, vintageName) = getGlobalProjectVintageIdentifiers();
        return
            string(
                abi.encodePacked(
                    'Toucan Protocol: TCO2-',
                    globalProjectId,
                    '-',
                    vintageName
                )
            );
    }

    /// @notice Token symbol getter overriden to return the a symbol based on the carbon project data
    function symbol() public view virtual override returns (string memory) {
        string memory globalProjectId;
        string memory vintageName;
        (globalProjectId, vintageName) = getGlobalProjectVintageIdentifiers();
        return
            string(
                abi.encodePacked('TCO2-', globalProjectId, '-', vintageName)
            );
    }

    /// @dev Helper function to retrieve data fragments for `name()` and `symbol()`
    function getGlobalProjectVintageIdentifiers()
        public
        view
        virtual
        returns (string memory, string memory)
    {
        ProjectData memory projectData;
        VintageData memory vintageData;
        (projectData, vintageData) = getAttributes();
        return (projectData.projectId, vintageData.name);
    }

    /// @dev Function to get corresponding attributes from the CarbonProjects
    function getAttributes()
        public
        view
        virtual
        returns (ProjectData memory, VintageData memory)
    {
        address pc = IToucanContractRegistry(contractRegistry)
            .carbonProjectsAddress();
        address vc = IToucanContractRegistry(contractRegistry)
            .carbonProjectVintagesAddress();

        VintageData memory vintageData = CarbonProjectVintages(vc)
            .getProjectVintageDataByTokenId(projectVintageTokenId);
        ProjectData memory projectData = CarbonProjects(pc)
            .getProjectDataByTokenId(vintageData.projectTokenId);

        return (projectData, vintageData);
    }

    /// @notice Receive hook to fractionalize Batch-NFTs into ERC20's
    /// @dev Function is called with `operator` as `_msgSender()` in a reference implementation by OZ
    /// `from` is the previous owner, not necessarily the same as operator.
    /// The hook checks if NFT collection is whitelisted and next if attributes are matching this ERC20 contract
    function onERC721Received(
        address, /* operator */
        address from,
        uint256 tokenId,
        bytes calldata /* data */
    ) external virtual override whenNotPaused returns (bytes4) {
        // msg.sender is the CarbonOffsetBatches contract
        require(
            checkWhiteListed(msg.sender),
            'Error: Batch-NFT not from whitelisted contract'
        );

        (
            uint256 gotVintageTokenId,
            uint256 quantity,
            RetirementStatus status
        ) = ICarbonOffsetBatches(msg.sender).getBatchNFTData(tokenId);
        require(
            gotVintageTokenId == projectVintageTokenId,
            'Error: non-matching NFT'
        );
        require(
            status == RetirementStatus.Confirmed,
            'BatchNFT not yet confirmed'
        );

        minterToId[from] = tokenId;
        /// @dev multiply tonne quantity with decimals
        quantity = quantity * 10**decimals();

        require(
            getRemaining() >= quantity,
            'Error: Quantity in batch is higher than total vintages'
        );

        ToucanCarbonOffsetsFactory tco2Factory = ToucanCarbonOffsetsFactory(
            IToucanContractRegistry(contractRegistry)
                .toucanCarbonOffsetsFactoryAddress()
        );
        address bridgeFeeReceiver = tco2Factory.bridgeFeeReceiverAddress();

        if (bridgeFeeReceiver == address(0x0)) {
            // @dev if no bridge fee receiver address is set, mint without fees
            _mint(from, quantity);
        } else {
            // @dev calculate bridge fees
            (uint256 feeAmount, uint256 feeBurnAmount) = tco2Factory
                .getBridgeFeeAndBurnAmount(quantity);
            _mint(from, quantity - feeAmount);
            address bridgeFeeBurnAddress = tco2Factory.bridgeFeeBurnAddress();
            if (bridgeFeeBurnAddress != address(0x0) && feeBurnAmount > 0) {
                feeAmount -= feeBurnAmount;
                _mint(bridgeFeeReceiver, feeAmount);
                _mint(bridgeFeeBurnAddress, feeBurnAmount);
                emit FeePaid(from, feeAmount);
                emit FeeBurnt(from, feeBurnAmount);
            } else if (feeAmount > 0) {
                _mint(bridgeFeeReceiver, feeAmount);
                emit FeePaid(from, feeAmount);
            }
        }

        return this.onERC721Received.selector;
    }

    /// @dev Internal helper to check if CarbonOffsetBatches is whitelisted (official)
    function checkWhiteListed(address collection)
        internal
        view
        virtual
        returns (bool)
    {
        if (
            collection ==
            IToucanContractRegistry(contractRegistry)
                .carbonOffsetBatchesAddress()
        ) {
            return true;
        } else {
            return false;
        }
    }

    /// @dev Returns the remaining space in TCO2 contract before hitting the cap
    function getRemaining() public view returns (uint256 remaining) {
        uint256 cap = getDepositCap();
        remaining = cap - totalSupply();
    }

    /// @dev Returns the cap for TCO2s based on `totalVintageQuantity`
    /// Returns `~unlimited` if the value for the vintage is not set
    function getDepositCap() public view returns (uint256) {
        VintageData memory vintageData;
        (, vintageData) = getAttributes();
        uint64 totalVintageQuantity = vintageData.totalVintageQuantity;

        ///@dev multipliying tonnes with decimals
        uint256 cap = totalVintageQuantity * 10**decimals();

        /// @dev if totalVintageQuantity is not set (=0), remove cap
        if (cap == 0) {
            return (2**256 - 1);
        } else {
            return cap;
        }
    }

    /// @notice Retirement/Cancellation of TCO2 tokens (the actual offsetting),
    /// which results in the tokens being burnt
    function retire(uint256 amount) public virtual whenNotPaused {
        _retire(_msgSender(), amount);
    }

    /// @dev Allow for pools or third party contracts to retire for the user
    /// Requires approval
    function retireFrom(address account, uint256 amount)
        external
        virtual
        whenNotPaused
    {
        uint256 currentAllowance = allowance(account, _msgSender());
        require(
            currentAllowance >= amount,
            'ERC20: retire amount exceeds allowance'
        );
        unchecked {
            _approve(account, _msgSender(), currentAllowance - amount);
        }
        _retire(account, amount);
    }

    /// @dev Internal function for the burning of TCO2 tokens
    function _retire(address account, uint256 amount) internal virtual {
        _burn(account, amount);
        retiredAmount[account] += amount;

        address TCO2FactoryAddress = IToucanContractRegistry(contractRegistry)
            .toucanCarbonOffsetsFactoryAddress();
        ToucanCarbonOffsetsFactory(TCO2FactoryAddress).increaseTotalRetired(
            amount
        );
        emit Retired(account, amount);
    }

    /// @notice Mint an NFT showing how many tonnes of CO2 have been retired/cancelled
    function mintCertificate(
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256 amount
    ) public virtual whenNotPaused {
        require(
            retiredAmount[msg.sender] >= amount,
            'Error: Cannot mint more than user has retired'
        );

        retiredAmount[msg.sender] -= amount;
        address certAddr = IToucanContractRegistry(contractRegistry)
            .carbonOffsetBadgesAddress();
        IRetirementCertificatesUnreleasedTest(certAddr).mintCertificate(
            msg.sender, /// @dev retiringEntity set automatically
            beneficiary,
            beneficiaryString,
            retirementMessage,
            projectVintageTokenId,
            amount
        );
    }

    /// @notice Retire offsets and mint certificate at once
    function retireAndMintCertificate(
        address beneficiary,
        string calldata beneficiaryString,
        string calldata retirementMessage,
        uint256 amount
    ) external virtual whenNotPaused {
        // Retire provided amount
        //slither-disable-next-line reentrancy-no-eth
        retire(amount);
        // Mint certificate
        mintCertificate(
            beneficiary,
            beneficiaryString,
            retirementMessage,
            amount
        );
    }

    // -----------------------------
    //      Locked ERC20 safety
    // -----------------------------

    /// @dev Modifier to disallowing sending tokens to either the 0-address
    /// or this contract itself
    modifier validDestination(address to) {
        require(to != address(0x0));
        require(to != address(this));
        _;
    }

    function transfer(address recipient, uint256 amount)
        public
        virtual
        override
        validDestination(recipient)
        whenNotPaused
        returns (bool)
    {
        super.transfer(recipient, amount);
        return true;
    }

    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    )
        public
        virtual
        override
        validDestination(recipient)
        whenNotPaused
        returns (bool)
    {
        super.transferFrom(sender, recipient, amount);
        return true;
    }
}
