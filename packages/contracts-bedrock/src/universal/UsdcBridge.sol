// SPDX-License-Identifier: MIT
pragma solidity 0.8.15;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC165Checker } from "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import { SafeCall } from "src/libraries/SafeCall.sol";
import { CrossDomainMessenger } from "src/universal/CrossDomainMessenger.sol";
import { Initializable } from "@openzeppelin/contracts/proxy/utils/Initializable.sol";
import { Pausable } from "src/libraries/Pausable.sol";
import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IPartialUsdc } from "src/L1/IPartialUsdc.sol";

/// @custom:upgradeable
/// @title UsdcBridge
/// @notice UsdcBridge is a base contract for the L1 and L2 standard ERC20 bridges. It handles
///         the core bridging logic, including escrowing tokens that are native to the local chain
///         and minting/burning tokens that are native to the remote chain.
abstract contract UsdcBridge is Initializable, Pausable, Ownable {
    using SafeERC20 for IERC20;

    /// @notice The L2 gas limit set when eth is depoisited using the receive() function.
    uint32 internal constant RECEIVE_DEFAULT_GAS_LIMIT = 200_000;

    /// @custom:legacy
    /// @custom:spacer messenger
    /// @notice Spacer for backwards compatibility.
    bytes30 private spacer_0_2_30;

    /// @custom:legacy
    /// @custom:spacer l2TokenBridge
    /// @notice Spacer for backwards compatibility.
    address private spacer_1_0_20;

    /// @notice Mapping that stores deposits for a given pair of local and remote tokens.
    mapping(address => mapping(address => uint256)) public deposits;

    /// @notice Messenger contract on this domain.
    /// @custom:network-specific
    CrossDomainMessenger public messenger;

    /// @notice Corresponding bridge on the other domain.
    /// @custom:network-specific
    UsdcBridge public otherBridge;

    /// @notice Address of the token on L1.
    address public l1Usdc;

    /// @notice Address of the token on L2.
    address public l2Usdc;

    /// @notice Reserve extra slots (to a total of 50) in the storage layout for future upgrades.
    ///         A gap size of 43 was chosen here, so that the first slot used in a child contract
    ///         would be a multiple of 50.
    uint256[43] private __gap;

    /// @notice Emitted when an ERC20 bridge is initiated to the other chain.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 sent.
    /// @param extraData   Extra data sent with the transaction.
    event ERC20BridgeInitiated(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Emitted when an ERC20 bridge is finalized on this chain.
    /// @param localToken  Address of the ERC20 on this chain.
    /// @param remoteToken Address of the ERC20 on the remote chain.
    /// @param from        Address of the sender.
    /// @param to          Address of the receiver.
    /// @param amount      Amount of the ERC20 sent.
    /// @param extraData   Extra data sent with the transaction.
    event ERC20BridgeFinalized(
        address indexed localToken,
        address indexed remoteToken,
        address indexed from,
        address to,
        uint256 amount,
        bytes extraData
    );

    /// @notice Only allow EOAs to call the functions. Note that this is not safe against contracts
    ///         calling code within their constructors, but also doesn't really matter since we're
    ///         just trying to prevent users accidentally depositing with smart contract wallets.
    modifier onlyEOA() {
        require(!Address.isContract(msg.sender), "UsdcBridge: function can only be called from an EOA");
        _;
    }

    /// @notice Ensures that the caller is a cross-chain message from the other bridge.
    modifier onlyOtherBridge() {
        require(
            msg.sender == address(messenger) && messenger.xDomainMessageSender() == address(otherBridge),
            "UsdcBridge: function can only be called from the other bridge"
        );
        _;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        // This contract is intended to be used through a proxy. Prevent this contract from being
        // initialized when not going through a proxy, to prevent problems when people forget to
        // to do so.
        _disableInitializers();
    }

    /// @notice Initializer.
    /// @param _messenger   Contract for CrossDomainMessenger on this network.
    /// @param _otherBridge Contract for the other UsdcBridge contract.
    function __UsdcBridge_init(
        CrossDomainMessenger _messenger,
        UsdcBridge _otherBridge,
        address _l1Usdc,
        address _l2Usdc,
        address _owner
    )
        internal
        onlyInitializing
    {
        messenger = _messenger;
        otherBridge = _otherBridge;
        l1Usdc = _l1Usdc;
        l2Usdc = _l2Usdc;
        _transferOwnership(_owner);
    }

    /// @notice Checks if the given token is the correct l1 token.
    /// @param _token The token to check.
    function _isL2Usdc(address _token) internal view returns (bool) {
        return _token == l2Usdc;
    }

    /// @notice Checks if the given token is the correct l2 token.
    /// @param _token The token to check.
    function _isL1Usdc(address _token) internal view returns (bool) {
        return _token == l1Usdc;
    }

    /// @notice Allows EOAs to bridge ETH by sending directly to the bridge.
    ///         Must be implemented by contracts that inherit.
    receive() external payable {
        revert("Eth transfers not supported");
    }

    /// @notice Getter for messenger contract.
    ///         Public getter is legacy and will be removed in the future. Use `messenger` instead.
    /// @return Contract of the messenger on this domain.
    /// @custom:legacy
    function MESSENGER() external view returns (CrossDomainMessenger) {
        return messenger;
    }

    /// @notice Getter for the other bridge contract.
    ///         Public getter is legacy and will be removed in the future. Use `otherBridge` instead.
    /// @return Contract of the bridge on the other network.
    /// @custom:legacy
    function OTHER_BRIDGE() external view returns (UsdcBridge) {
        return otherBridge;
    }

    /**
     * @dev Function to pause contract. This calls the Pausable contract.
     */
    function pause() external onlyOwner {
        super._pause();
    }

    /**
     * @dev Function to unpause contract. This calls the Pausable contract.
     */
    function unpause() external onlyOwner {
        super._unpause();
    }

    /// @notice Sends ERC20 tokens to the sender's address on the other chain. Note that if the
    ///         ERC20 token on the other chain does not recognize the local token as the correct
    ///         pair token, the ERC20 bridge will fail and the tokens will be returned to sender on
    ///         this chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20(
        address _localToken,
        address _remoteToken,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        public
        virtual
        onlyEOA
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, msg.sender, _amount, _minGasLimit, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain. Note that if the
    ///         ERC20 token on the other chain does not recognize the local token as the correct
    ///         pair token, the ERC20 bridge will fail and the tokens will be returned to sender on
    ///         this chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function bridgeERC20To(
        address _localToken,
        address _remoteToken,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes calldata _extraData
    )
        public
        virtual
    {
        _initiateBridgeERC20(_localToken, _remoteToken, msg.sender, _to, _amount, _minGasLimit, _extraData);
    }

    /// @notice Finalizes an ERC20 bridge on this chain. Can only be triggered by the other
    ///         UsdcBridge contract on the remote chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 being bridged.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function finalizeBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes calldata _extraData
    )
        public
        onlyOtherBridge
    {
        // this check is not strictly required as it should have been ensured by the
        // remote bridge, but doesn't hurt.
        require(_isCorrectUsdcTokenPair(_localToken, _remoteToken), "Invalid token pair");

        if (_isL2Usdc(_localToken) && _isL1Usdc(_remoteToken)) {
            // L1 --> L2
            IPartialUsdc(_localToken).mint(_to, _amount);
        } else if (_isL1Usdc(_localToken) && _isL2Usdc(_remoteToken)) {
            // L2 --> L1
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] - _amount;
            IERC20(_localToken).safeTransfer(_to, _amount);
        } else {
            // should be unreachable
            revert("Invalid token pair");
        }

        // Emit the correct events. By default this will be ERC20BridgeFinalized, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Sends ERC20 tokens to a receiver's address on the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the corresponding token on the remote chain.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of local tokens to deposit.
    /// @param _minGasLimit Minimum amount of gas that the bridge can be relayed with.
    /// @param _extraData   Extra data to be sent with the transaction. Note that the recipient will
    ///                     not be triggered with this data, but it will be emitted and can be used
    ///                     to identify the transaction.
    function _initiateBridgeERC20(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        uint32 _minGasLimit,
        bytes memory _extraData
    )
        internal
        whenNotPaused
    {
        require(_isCorrectUsdcTokenPair(_localToken, _remoteToken), "Invalid token pair");

        if (_isL2Usdc(_localToken) && _isL1Usdc(_remoteToken)) {
            // L2 --> L1
            // usdc has no burnFrom, so first transfer to the contract and then burn.
            IERC20(_localToken).safeTransferFrom(_from, address(this), _amount);
            IPartialUsdc(_localToken).burn(_amount);
        } else if (_isL1Usdc(_localToken) && _isL2Usdc(_remoteToken)) {
            // L1 --> L2
            IERC20(_localToken).safeTransferFrom(_from, address(this), _amount);
            deposits[_localToken][_remoteToken] = deposits[_localToken][_remoteToken] + _amount;
        } else {
            // should be unreachable
            revert("Invalid token pair");
        }

        // Emit the correct events. By default this will be ERC20BridgeInitiated, but child
        // contracts may override this function in order to emit legacy events as well.
        _emitERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);

        messenger.sendMessage({
            _target: address(otherBridge),
            _message: abi.encodeWithSelector(
                this.finalizeBridgeERC20.selector,
                // Because this call will be executed on the remote chain, we reverse the order of
                // the remote and local token addresses relative to their order in the
                // finalizeBridgeERC20 function.
                _remoteToken,
                _localToken,
                _from,
                _to,
                _amount,
                _extraData
                ),
            _minGasLimit: _minGasLimit
        });
    }

    /// @notice Emits the ERC20BridgeInitiated event and if necessary the appropriate legacy
    ///         event when an ERC20 bridge is initiated to the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the ERC20 on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 sent.
    /// @param _extraData   Extra data sent with the transaction.
    function _emitERC20BridgeInitiated(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ERC20BridgeInitiated(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Emits the ERC20BridgeFinalized event and if necessary the appropriate legacy
    ///         event when an ERC20 bridge is initiated to the other chain.
    /// @param _localToken  Address of the ERC20 on this chain.
    /// @param _remoteToken Address of the ERC20 on the remote chain.
    /// @param _from        Address of the sender.
    /// @param _to          Address of the receiver.
    /// @param _amount      Amount of the ERC20 sent.
    /// @param _extraData   Extra data sent with the transaction.
    function _emitERC20BridgeFinalized(
        address _localToken,
        address _remoteToken,
        address _from,
        address _to,
        uint256 _amount,
        bytes memory _extraData
    )
        internal
        virtual
    {
        emit ERC20BridgeFinalized(_localToken, _remoteToken, _from, _to, _amount, _extraData);
    }

    /// @notice Returns whether or not the given tokens match the usdc pair.
    /// @param _localToken  Address of the ERC20 on this chain
    /// @param _remoteToken Address of the ERC20 on the remote chain.
    function _isCorrectUsdcTokenPair(address _localToken, address _remoteToken) internal view virtual returns (bool);
}
