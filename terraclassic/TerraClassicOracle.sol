// SPDX-License-Identifier: MIT
pragma solidity ^0.8.13;

/**
 * @title TerraClassicOracle
 * @notice Oracle de gas para Terra Classic (domain 132556).
 *         Implementa a interface getExchangeRateAndGasPrice usada pelo TerraClassicIGPStandalone.
 *         Owner pode atualizar exchange_rate e gas_price via setRemoteGasData.
 */
contract TerraClassicOracle {

    address public owner;

    // exchange_rate: (NATIVE_USD / LUNC_USD) — sem escala adicional, já está em unidades 1e0
    // O IGP divide por TOKEN_EXCHANGE_RATE_SCALE = 1e10 internamente
    uint128 public exchangeRate;

    // gasPrice: gas price da Terra Classic em wei-equivalente
    uint128 public gasPrice;

    uint32 public constant TERRA_CLASSIC_DOMAIN = 1325;

    event GasDataUpdated(uint32 indexed domain, uint128 exchangeRate, uint128 gasPrice);
    event OwnershipTransferred(address indexed previous, address indexed newOwner);

    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }

    constructor(uint128 _exchangeRate, uint128 _gasPrice) {
        owner = msg.sender;
        exchangeRate = _exchangeRate;
        gasPrice = _gasPrice;
        emit GasDataUpdated(TERRA_CLASSIC_DOMAIN, _exchangeRate, _gasPrice);
    }

    /// @notice Atualiza os parâmetros de gas para a Terra Classic
    function setRemoteGasData(uint32, uint128 _exchangeRate, uint128 _gasPrice) external onlyOwner {
        exchangeRate = _exchangeRate;
        gasPrice = _gasPrice;
        emit GasDataUpdated(TERRA_CLASSIC_DOMAIN, _exchangeRate, _gasPrice);
    }

    /// @notice Interface consultada pelo TerraClassicIGPStandalone
    function getExchangeRateAndGasPrice(uint32) external view returns (uint128, uint128) {
        return (exchangeRate, gasPrice);
    }

    function transferOwnership(address _newOwner) external onlyOwner {
        require(_newOwner != address(0), "zero address");
        emit OwnershipTransferred(owner, _newOwner);
        owner = _newOwner;
    }
}
