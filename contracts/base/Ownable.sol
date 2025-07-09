// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./Errors.sol";

abstract contract Ownable is Errors, Initializable {
    address private _owner;
    address private _pendingOwner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    modifier onlyOwner() {
        if (owner() != msg.sender) revert CallerNotAllowed();
        _;
    }

    modifier onlyPendingOwner() {
        if (pendingOwner() != msg.sender) revert CallerNotAllowed();
        _;
    }

    modifier onlyOwnerOrInitializing() {
        if (!_isInitializing() && owner() != msg.sender) revert CallerNotAllowed();
        _;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function pendingOwner() public view virtual returns (address) {
        return _pendingOwner;
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address _newOwner) external virtual onlyOwner {
        if (_newOwner == address(0)) revert AddressNotAllowed();
        _pendingOwner = _newOwner;
    }

    /**
     * @dev Accept ownership of the contract.
     * Can only be called by the current pending owner.
     */
    function acceptOwnership() external virtual onlyPendingOwner {
        address oldOwner = _owner;
        _owner = _pendingOwner;
        _pendingOwner = address(0);

        emit OwnershipTransferred(oldOwner, _owner);
    }

    /**
     * @dev Init owner of the contract (`newOwner`).
     */
    function _initOwner(address _newOwner) internal virtual onlyInitializing {
        _owner = _newOwner;
    }
}
