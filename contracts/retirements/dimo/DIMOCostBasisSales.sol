// SPDX-FileCopyrightText: 2024 Toucan Labs
//
// SPDX-License-Identifier: UNLICENSED

// If you encounter a vulnerability or an issue, please contact <security@toucan.earth> or visit security.toucan.earth
pragma solidity 0.8.14;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/token/ERC721/IERC721Upgradeable.sol';

import '../../bases/RoleInitializer.sol';
import '../interfaces/IRetirementCertificateFractionalizer.sol';
import './interfaces/IDIMOCostBasisSales.sol';
import './DIMOCostBasisSalesStorage.sol';

contract DIMOCostBasisSales is
    IDIMOCostBasisSales,
    UUPSUpgradeable,
    PausableUpgradeable,
    RoleInitializer,
    DIMOCostBasisSalesStorage
{
    /// @dev Version-related parameters. VERSION keeps track of production
    /// releases. VERSION_RELEASE_CANDIDATE keeps track of iterations
    /// of a VERSION in our staging environment.
    string public constant VERSION = '1.0.0';
    uint256 public constant VERSION_RELEASE_CANDIDATE = 1;

    bytes32 public constant PAUSER_ROLE = keccak256('PAUSER_ROLE');
    bytes32 public constant MANAGER_ROLE = keccak256('MANAGER_ROLE');

    event ListingUpdated(
        address sender,
        uint256 indexed vintageId,
        uint256 amount,
        uint256 pricePerUnit
    );

    event ListingBought(
        address indexed beneficiary,
        uint256 indexed vintageId,
        uint256 amount,
        uint256 fractionTokenId,
        uint256 price
    );

    event ToucanRegistrySet(address contractRegistry);
    event ListerSet(address newLister);
    event DIMOUserProfileSet(address dimoUserProfile);

    function initialize(
        address[] calldata accounts,
        bytes32[] calldata roles,
        address contractRegistry_,
        address paymentToken_
    ) external initializer {
        __UUPSUpgradeable_init_unchained();
        __Pausable_init_unchained();
        __RoleInitializer_init_unchained(accounts, roles);

        contractRegistry = IToucanContractRegistry(contractRegistry_);
        paymentToken = IERC20(paymentToken_);
    }

    // ----------------------------------------
    //      Pausable
    // ----------------------------------------

    function pause() external onlyRole(PAUSER_ROLE) {
        super._pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        super._unpause();
    }

    // ----------------------------------------
    //      Admin
    // ----------------------------------------

    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    {}

    function setToucanContractRegistry(address toucanContractRegistry)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        contractRegistry = IToucanContractRegistry(toucanContractRegistry);
        emit ToucanRegistrySet(toucanContractRegistry);
    }

    function setLister(address lister_) external onlyRole(DEFAULT_ADMIN_ROLE) {
        lister = lister_;
        emit ListerSet(lister_);
    }

    function setDIMOUserProfile(address dimoUserProfile_)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        dimoUserProfile = IDIMOUserProfile(dimoUserProfile_);
        emit DIMOUserProfileSet(dimoUserProfile_);
    }

    // ----------------------------------------
    //      Permissioned
    // ----------------------------------------

    /**
     * Increments the listing amount of a given vintage id
     * @param vintageId the vintage id
     * @param amount increment
     * @param pricePerUnit price (as `paymentToken`) per 1 unit of vintage.
     * The new price per unit will be calculated as an weighted average
     * of old and new price.
     */
    function list(
        uint256 vintageId,
        uint256 amount,
        uint256 pricePerUnit
    ) external whenNotPaused {
        // we use a pre-defined lister instead of the OZ access control roles
        // in order to make the lister easy to discover in the DIMO frontend.
        // initially, only one lister will exist, but as soon as we move
        // to a permissionless version of this method, lister will be deprecated and
        // and account will be able to call list. This will be enabled by updating buy()
        // to accept one or more listers from where buyers can consume balances.
        require(msg.sender == lister, 'invalid lister');
        require(amount > 0, 'invalid amount');
        require(pricePerUnit > 0, 'invalid price per unit');
        VintageListing storage vintage = listing[vintageId][msg.sender];

        vintage.pricePerUnit =
            (vintage.pricePerUnit * vintage.amount + amount * pricePerUnit) /
            (vintage.amount + amount);
        vintage.amount += amount;

        emit ListingUpdated(
            msg.sender,
            vintageId,
            vintage.amount,
            vintage.pricePerUnit
        );
    }

    // ----------------------------------------
    //      Permissionless
    // ----------------------------------------

    function totalSold() external view override returns (uint256) {
        return _totalSold;
    }

    /**
     * Calculate the price to buy a certain fraction, defined by the request data
     * @notice price is expressed in the unit of the `paymentToken`
     * @param from the address of the account from whom the fraction is bought
     * @param params the fraction request for which the quote needs to be
     * made
     * @return quote the quote
     */
    function quoteBuy(address from, FractionRequestData calldata params)
        public
        view
        returns (uint256 quote)
    {
        quote =
            (params.amount *
                listing[params.projectVintageTokenId][from].pricePerUnit) /
            1e18;
    }

    /**
     * Performs the purchase of a fraction, according to the fraction request params
     * @notice `maxPrice` is expressed in the unit of the `paymentToken`
     * @param params the fraction request for which the purchase is made
     * @param maxPrice the maximum price the buyer is willing to spend
     */
    function buy(FractionRequestData calldata params, uint256 maxPrice)
        external
        whenNotPaused
        returns (uint256 fractionTokenId)
    {
        address from = lister;
        uint256 listedAmount = listing[params.projectVintageTokenId][from]
            .amount;
        uint256 pricePerUnit = listing[params.projectVintageTokenId][from]
            .pricePerUnit;
        require(listedAmount > 0 && pricePerUnit > 0, 'vintage not listed');
        require(listedAmount >= params.amount, 'amount too large');

        uint256 finalPrice = quoteBuy(from, params);
        require(finalPrice <= maxPrice, 'price too high');

        listedAmount -= params.amount;
        listing[params.projectVintageTokenId][from].amount = listedAmount;
        _totalSold += params.amount;

        require(
            paymentToken.transferFrom(msg.sender, from, finalPrice),
            'payment transfer failed'
        );

        fractionTokenId = IRetirementCertificateFractionalizer(
            contractRegistry.retirementCertificateFractionalizerAddress()
        ).mintFractionFrom(from, params);

        // the statement is only added to optimize storage and has no effect on
        // the method logic
        if (listedAmount == 0) {
            //slither-disable-next-line reentrancy-no-eth
            delete listing[params.projectVintageTokenId][from];
        }

        _mintUserProfile(params.beneficiary);

        emit ListingBought(
            msg.sender,
            params.projectVintageTokenId,
            params.amount,
            fractionTokenId,
            finalPrice
        );
    }

    /// @dev Mint a user profile if the user does not have one
    function _mintUserProfile(address user) internal {
        require(
            dimoUserProfile != IDIMOUserProfile(address(0)),
            'invalid user profile contract'
        );
        // slither-disable-next-line incorrect-equality
        if (dimoUserProfile.balanceOf(user) == 0) {
            // slither-disable-next-line unused-return
            dimoUserProfile.mint(user);
        }
    }
}
