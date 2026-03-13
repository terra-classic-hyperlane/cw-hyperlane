// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity ^0.8.13;

/**
 * @title TerraClassicIGPStandalone
 * @notice IGP standalone para Terra Classic (sem dependências externas)
 * @dev Hook Type = 4 (INTERCHAIN_GAS_PAYMASTER) ✅
 */
contract TerraClassicIGPStandalone {
    
    // ============ Constants ============
    
    uint256 internal constant TOKEN_EXCHANGE_RATE_SCALE = 1e10;
    uint256 internal constant DEFAULT_GAS_USAGE = 50_000;
    uint8 internal constant IGP_HOOK_TYPE = 4; // INTERCHAIN_GAS_PAYMASTER ✅
    uint32 internal constant TERRA_CLASSIC_DOMAIN = 1325;
    
    // Message offsets
    uint256 private constant DESTINATION_OFFSET = 41;
    uint256 private constant RECIPIENT_OFFSET = 45;
    
    // Metadata offsets
    uint8 private constant GAS_LIMIT_OFFSET = 34;
    
    // ============ Storage ============
    
    address public owner;
    address public beneficiary;
    address public gasOracle;
    uint96 public gasOverhead;
    
    // ============ Events ============
    
    event GasPayment(
        bytes32 indexed messageId,
        uint32 indexed destinationDomain,
        uint256 gasAmount,
        uint256 payment
    );
    
    event GasOracleSet(address indexed gasOracle, uint96 gasOverhead);
    event BeneficiarySet(address indexed beneficiary);
    
    // ============ Modifiers ============
    
    modifier onlyOwner() {
        require(msg.sender == owner, "!owner");
        _;
    }
    
    // ============ Constructor ============
    
    constructor(address _gasOracle, uint96 _gasOverhead, address _beneficiary) {
        require(_gasOracle != address(0), "invalid oracle");
        require(_beneficiary != address(0), "invalid beneficiary");
        
        owner = msg.sender;
        gasOracle = _gasOracle;
        gasOverhead = _gasOverhead;
        beneficiary = _beneficiary;
        
        emit GasOracleSet(_gasOracle, _gasOverhead);
        emit BeneficiarySet(_beneficiary);
    }
    
    // ============ External Functions - IPostDispatchHook ============
    
    function hookType() external pure returns (uint8) {
        return IGP_HOOK_TYPE; // 4 = INTERCHAIN_GAS_PAYMASTER ✅
    }
    
    function supportsMetadata(bytes calldata) external pure returns (bool) {
        return true;
    }
    
    function quoteDispatch(
        bytes calldata metadata,
        bytes calldata message
    ) external view returns (uint256) {
        uint32 destination = _destination(message);
        require(destination == TERRA_CLASSIC_DOMAIN, "destination not supported");
        
        uint256 gasLimit = _gasLimit(metadata);
        uint256 totalGas = gasLimit + uint256(gasOverhead);
        
        return _quoteGasPayment(destination, totalGas);
    }
    
    function postDispatch(
        bytes calldata metadata,
        bytes calldata message
    ) external payable {
        bytes32 messageId = keccak256(message);
        uint32 destination = _destination(message);
        require(destination == TERRA_CLASSIC_DOMAIN, "destination not supported");
        
        uint256 gasLimit = _gasLimit(metadata);
        uint256 totalGas = gasLimit + uint256(gasOverhead);
        
        uint256 requiredPayment = _quoteGasPayment(destination, totalGas);
        require(msg.value >= requiredPayment, "insufficient payment");
        
        uint256 overpayment = msg.value - requiredPayment;
        if (overpayment > 0) {
            address refundAddr = _refundAddress(metadata, message);
            payable(refundAddr).transfer(overpayment);
        }
        
        emit GasPayment(messageId, destination, totalGas, requiredPayment);
    }
    
    // ============ External Functions - Admin ============
    
    function setGasOracle(address _gasOracle, uint96 _gasOverhead) external onlyOwner {
        require(_gasOracle != address(0), "invalid oracle");
        gasOracle = _gasOracle;
        gasOverhead = _gasOverhead;
        emit GasOracleSet(_gasOracle, _gasOverhead);
    }
    
    function setBeneficiary(address _beneficiary) external onlyOwner {
        require(_beneficiary != address(0), "invalid beneficiary");
        beneficiary = _beneficiary;
        emit BeneficiarySet(_beneficiary);
    }
    
    function claim() external {
        uint256 balance = address(this).balance;
        require(balance > 0, "no balance");
        payable(beneficiary).transfer(balance);
    }
    
    // ============ Internal Functions ============
    
    function _destination(bytes calldata message) internal pure returns (uint32) {
        return uint32(bytes4(message[DESTINATION_OFFSET:RECIPIENT_OFFSET]));
    }
    
    function _gasLimit(bytes calldata metadata) internal pure returns (uint256) {
        if (metadata.length < GAS_LIMIT_OFFSET + 32) {
            return DEFAULT_GAS_USAGE;
        }
        return uint256(bytes32(metadata[GAS_LIMIT_OFFSET:GAS_LIMIT_OFFSET + 32]));
    }
    
    function _refundAddress(
        bytes calldata metadata,
        bytes calldata message
    ) internal pure returns (address) {
        uint256 REFUND_ADDRESS_OFFSET = 66;
        
        if (metadata.length < REFUND_ADDRESS_OFFSET + 20) {
            return _senderAddress(message);
        }
        
        return address(bytes20(metadata[REFUND_ADDRESS_OFFSET:REFUND_ADDRESS_OFFSET + 20]));
    }
    
    function _senderAddress(bytes calldata message) internal pure returns (address) {
        uint256 SENDER_OFFSET = 9;
        uint256 DESTINATION_OFFSET_LOCAL = 41;
        bytes32 sender = bytes32(message[SENDER_OFFSET:DESTINATION_OFFSET_LOCAL]);
        return address(uint160(uint256(sender)));
    }
    
    function _quoteGasPayment(
        uint32 destinationDomain,
        uint256 gasLimit
    ) internal view returns (uint256) {
        // Call oracle
        (bool success, bytes memory data) = gasOracle.staticcall(
            abi.encodeWithSignature(
                "getExchangeRateAndGasPrice(uint32)",
                destinationDomain
            )
        );
        
        require(success, "oracle call failed");
        
        (uint128 tokenExchangeRate, uint128 gasPrice) = abi.decode(
            data,
            (uint128, uint128)
        );
        
        uint256 destinationGasCost = gasLimit * uint256(gasPrice);
        
        // IMPORTANTE: usar TOKEN_EXCHANGE_RATE_SCALE (1e10) conforme oficial ✅
        return (destinationGasCost * uint256(tokenExchangeRate)) / TOKEN_EXCHANGE_RATE_SCALE;
    }
    
    receive() external payable {}
}
