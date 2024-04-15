// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.8.15;

import "@openzeppelin/contracts/access/Ownable.sol";

interface IUsdcProxy {
    function changeAdmin(address newAdmin) external;
}

interface IUsdcImpl {
    function transferOwnership(address newOwner) external;
}

interface IMasterMinter {
    function configureController(address, address) external;
    function configureMinter(uint256) external;
    function removeMinter() external returns (bool);
}

contract UsdcManager is Ownable {
    address whitelistedTakeoverOrigin;
    address tokenProxyAddress;
    address masterMinterAddress;
    address bridgeAddress;

    constructor(address initialOwner) Ownable() {
        transferOwnership(initialOwner);
    }

    /// @notice Initializes the contract with the given addresses. Also configured the bridge
    ///         as a minter. Note that this contract is expected to have been assigned
    ///         the ownership of the USDC proxy, implementation, and master minter roles.
    /// @param _bridgeAddress The L2 bridge address.
    /// @param _masterMinterAddress The MasterMinter address.
    /// @param _tokenProxyAddress The address of the USDC token proxy.
    function initialize(
        address _bridgeAddress,
        address _masterMinterAddress,
        address _tokenProxyAddress
    )
        public
        onlyOwner
    {
        tokenProxyAddress = _tokenProxyAddress;
        bridgeAddress = _bridgeAddress;
        masterMinterAddress = _masterMinterAddress;
        IMasterMinter(masterMinterAddress).configureController(address(this), bridgeAddress);
        IMasterMinter(masterMinterAddress).configureMinter(type(uint256).max);
    }

    /// @notice Allows the given address to take over the USDC roles. Note that this
    ///         function can only be called once.
    /// @param _whitelistedTakeoverOrigin Address to be whitelisted.
    function allowTakeover(address _whitelistedTakeoverOrigin) public onlyOwner {
        require(whitelistedTakeoverOrigin == address(0), "Whitelist address already set");
        whitelistedTakeoverOrigin = _whitelistedTakeoverOrigin;
    }

    /// @notice Transfers USDC roles to a pre-whitelisted account and removes minting
    ///         privileges from the bridge.
    /// @param owner Address to transfer the roles to.
    function transferUSDCRoles(address owner) external {
        require(msg.sender == whitelistedTakeoverOrigin, "Unauthorized transfer");
        require(owner != address(0), "Can not transfer ownership to the zero address");

        // Change proxy admin
        IUsdcProxy(tokenProxyAddress).changeAdmin(owner);

        // remove minter
        IMasterMinter(masterMinterAddress).removeMinter();

        // Transfer implementation owner
        IUsdcImpl(tokenProxyAddress).transferOwnership(owner);
    }
}
