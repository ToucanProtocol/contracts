// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC721/IERC721.sol';

import '../bases/RoleInitializer.sol';

abstract contract NFTCarbonExtension is
    RoleInitializer,
    PausableUpgradeable,
    UUPSUpgradeable
{
    /// @custom:oz-upgrades-unsafe-allow state-variable-immutable
    IERC20 public immutable pool;

    /// @dev All roles related to accessing this contract
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');
    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');

    // Storage
    IERC721 public erc721;
    uint256 public basePoolTokenAllocationPerNFT;
    uint256 public allocatedSupply;
    mapping(uint256 => uint256) internal _tokenIdBalance;
    bool internal allocationStarted;
    /**
     * @dev This empty reserved space is put in place to allow future versions to add new
     * variables without shifting down storage in the inheritance chain.
     * See https://docs.openzeppelin.com/contracts/4.x/upgradeable#storage_gaps
     */
    uint256[45] private __gap;

    // Events
    event PoolTokenAllocated(uint256 amount);
    event PoolTokenWithdrawn(uint256 amount);
    event ERC721Set(address erc721);
    event BasePoolTokenAllocationPerNFTSet(uint256 allocation);

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor(address pool_) {
        require(pool_ != address(0), 'Empty pool address');
        pool = IERC20(pool_);
        _disableInitializers();
    }

    function __NFTCarbonExtension_initialize(
        uint256 basePoolTokenAllocationPerNFT_,
        address erc721_,
        address[] calldata accounts,
        bytes32[] calldata roles
    ) internal {
        __RoleInitializer_init_unchained(accounts, roles);
        __Pausable_init_unchained();
        __UUPSUpgradeable_init_unchained();

        basePoolTokenAllocationPerNFT = basePoolTokenAllocationPerNFT_;
        erc721 = IERC721(erc721_);
    }

    // Admin functions

    function setErc721(address erc721_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        erc721 = IERC721(erc721_);
        emit ERC721Set(erc721_);
    }

    function setBasePoolTokenAllocationPerNFT(uint256 allocation_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(!allocationStarted, 'allocation started');
        basePoolTokenAllocationPerNFT = allocation_;
        emit BasePoolTokenAllocationPerNFTSet(allocation_);
    }

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}

    function pause() external onlyRole(PAUSER_ROLE) {
        super._pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        super._unpause();
    }

    /** Allows the owner allocate an amount of pool token based on an estimated supply.
     * @notice The caller needs to approve this contract for a sufficient amount of pool
     * tokens before executing it. The method quoteAllocatePoolTokenAmount can be used to get
     * the precise amount needed.
     * @param estimatedSupply Indicates the amount of NFT tokens for which to allocate
     * pool tokens
     *
     */
    function allocatePoolToken(uint256 estimatedSupply)
        external
        onlyRole(MANAGER_ROLE)
    {
        allocationStarted = true;
        allocatedSupply += estimatedSupply;

        uint256 amount = estimatedSupply * basePoolTokenAllocationPerNFT;
        bool success = pool.transferFrom(msg.sender, address(this), amount);
        require(success, 'transfer failed');

        emit PoolTokenAllocated(amount);
    }

    /** Allows the owner to withdraw any exceeding amount of pre-allocated
     * pool tokens.
     * @param supplyToWithdraw the supply to withdraw. It must be less than the
     * allocated supply and at the same time we will not allow withdrawals
     * that violate the carbon backing of the NFTs.
     */
    function withdrawPoolToken(uint256 supplyToWithdraw)
        external
        onlyRole(MANAGER_ROLE)
    {
        uint256 newAllocatedSupply = allocatedSupply - supplyToWithdraw;
        uint256 totalSupply = _getTotalSupply();
        require(newAllocatedSupply >= totalSupply, 'cannot violate backing');

        allocatedSupply = newAllocatedSupply;

        uint256 leftoverTokens = supplyToWithdraw *
            basePoolTokenAllocationPerNFT;
        bool success = pool.transfer(msg.sender, leftoverTokens);
        require(success, 'transfer failed');

        emit PoolTokenWithdrawn(leftoverTokens);
    }

    /// @dev Marketplace-specific contracts need to override this
    /// function to return the final supply of the NFT collection
    /// once a mint has been finalized. In turn this supply variable
    /// is honored by withdrawPoolToken() to ensure that the owner
    /// does not withdraw more tokens than they should.
    function _getTotalSupply() internal view virtual returns (uint256);

    // Permissionless functions

    /** Returns the amount of pool tokens associated to the NFT token id
     * @param tokenId the token id
     * @return balance pool token balance
     */
    function tokenIdBalance(uint256 tokenId)
        external
        view
        returns (uint256 balance)
    {
        require(erc721.ownerOf(tokenId) != address(0), 'non existing token id');
        return _tokenIdBalance[tokenId] + basePoolTokenAllocationPerNFT;
    }

    /** It returns the amount of pool tokens required in the sender account
     * to fulfill an allocation request for the given NFT supply
     * @param estimatedSupply estimated supply for which to allocate tokens
     * @return poolTokenAmount required pool token balance
     */
    function quoteAllocatePoolTokenAmount(uint256 estimatedSupply)
        external
        view
        returns (uint256 poolTokenAmount, bool isSufficientBalance)
    {
        poolTokenAmount = estimatedSupply * basePoolTokenAllocationPerNFT;
        isSufficientBalance = pool.balanceOf(msg.sender) >= poolTokenAmount;
    }

    /** It allows an NFT owner to embed further pool tokens in their NFT
     * @notice The caller needs to approve this contract for a sufficient amount of pool
     * tokens before executing it.
     * @param tokenId the token id where to allocate the pool tokens
     * @param amount amount of pool tokens to associate to the NFT token
     */
    function embed(uint256 tokenId, uint256 amount) external whenNotPaused {
        require(amount > 0, 'invalid amount');
        require(erc721.ownerOf(tokenId) == msg.sender, 'not the owner');

        _tokenIdBalance[tokenId] += amount;

        bool success = pool.transferFrom(msg.sender, address(this), amount);
        require(success, 'transfer failed');
    }
}
