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

import '../../interfaces/IToucanContractRegistry.sol';
import '../../interfaces/ICarbonOffsetBatches.sol';
import './ICarbonOffsetBadges.sol';
import '../../CarbonProjects.sol';
import '../../CarbonProjectVintages.sol';
import '../../CarbonProjectVintageTypes.sol';
import '../../ToucanCarbonOffsetsStorage.sol'; /// @dev Has not been changed
import './ToucanCarbonOffsetsFactoryV1Test.sol';
import '../../CarbonOffsetBatchesTypes.sol';
import '../../ToucanCarbonOffsetsFactory.sol';

/// @notice Implementation contract of the TCO2 tokens (ERC20)
/// These tokenized carbon offsets are specific to a vintage and its associated attributes
/// In order to mint TCO2s a user must deposit a matching CarbonOffsetBatch
/// @dev Each TCO2 contract is deployed via a Beacon Proxy in `ToucanCarbonOffsetsFactory`
contract ToucanCarbonOffsetsV1Test is
    ERC20Upgradeable,
    IERC721Receiver,
    ToucanCarbonOffsetsStorage
{
    event Retired(address sender, uint256 tokenId);

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

    /// @notice name getter overriden to return the a name based on the carbon project data
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

    /// @notice symbol getter overriden to return the a symbol based on the carbon project data
    function symbol() public view virtual override returns (string memory) {
        string memory globalProjectId;
        string memory vintageName;
        (globalProjectId, vintageName) = getGlobalProjectVintageIdentifiers();
        return
            string(
                abi.encodePacked('TCO2-', globalProjectId, '-', vintageName)
            );
    }

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

    // Function to get corresponding attributes from the CarbonProjects
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

    /**
     * @dev function is called with `operator` as `_msgSender()` in a reference implementation by OZ
     * `from` is the previous owner, not necessarily the same as operator
     *  Function checks if NFT collection is whitelisted and next if attributes are matching this erc20 contract
     **/
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

        //slither-disable-next-line reentrancy-no-eth
        (
            uint256 projectVintageTokenId,
            uint256 quantity,
            RetirementStatus status
        ) = ICarbonOffsetBatches(msg.sender).getBatchNFTData(tokenId);
        require(
            checkMatchingAttributes(projectVintageTokenId),
            'Error: non-matching NFT'
        );
        require(
            status == RetirementStatus.Confirmed,
            'BatchNFT not yet confirmed'
        );

        minterToId[from] = tokenId;
        /// @dev multiply tonne quantity with decimals
        quantity = quantity * 10**decimals();

        uint256 remainingSpace = getRemaining();
        require(
            remainingSpace > quantity,
            'Error: Quantity in batch is higher than total vintages'
        );
        _mint(from, quantity);
        return this.onERC721Received.selector;
    }

    // Check if CarbonOffsetBatches is whitelisted (official)
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

    /**
     * @dev Checks if attributes of sent NFT are matching the attributes of this ERC20
     **/
    function checkMatchingAttributes(uint256 NFTprojectVintageTokenId)
        internal
        view
        virtual
        returns (bool)
    {
        if (NFTprojectVintageTokenId == projectVintageTokenId) {
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

    // Retirement of TCUs (the actual offsetting)
    function retire(uint256 amount) external virtual whenNotPaused {
        _retire(_msgSender(), amount);
    }

    /// @dev Allow for pools or third party contracts to retire for the user
    // Requires approve
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

    // Alternative flow, where tokens are sent to a "retirement contract"
    function _retire(address account, uint256 amount) internal virtual {
        _burn(account, amount);
        retiredAmount[account] += amount;
        emit Retired(account, amount);
    }

    // Mint the Badge NFT showing how many tokens have been retired
    function mintBadgeNFT(address to, uint256 amount)
        external
        virtual
        whenNotPaused
    {
        address badgeAddr = IToucanContractRegistry(contractRegistry)
            .carbonOffsetBadgesAddress();
        require(
            retiredAmount[msg.sender] >= amount,
            'Error: Cannot mint more than user has retired'
        );

        retiredAmount[msg.sender] -= amount;
        ICarbonOffsetBadgesTest(badgeAddr).mintBadge(
            to,
            projectVintageTokenId,
            amount
        );
    }

    // -----------------------------
    //      Locked ERC20 safety
    // -----------------------------

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
