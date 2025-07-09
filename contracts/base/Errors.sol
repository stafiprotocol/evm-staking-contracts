// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.19;

interface Errors {
    error NotInitialized();
    error AddressNotAllowed();
    error AlreadyInitialized();

    error CallerNotAllowed();
    error FailedToCall();
    error AmountNotMatch();

    error AlreadyWithdrawed();
    error RewardAlgorithmNotSupport();
    error UnstakeTimesExceedLimit();
}
