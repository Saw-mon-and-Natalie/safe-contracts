pragma solidity 0.4.19;
import "./Extension.sol";


/// @title Gnosis Safe - A multisignature wallet with support for confirmations using signed messages based on ERC191.
/// @author Stefan George - <stefan@gnosis.pm>
contract GnosisSafe {

    event ContractCreation(address newContract);

    string public constant NAME = "Gnosis Safe";
    string public constant VERSION = "0.0.1";

    GnosisSafe masterCopy;
    uint8 public threshold;
    uint256 public nonce;
    address[] public owners;
    Extension[] public extensions;
    mapping (address => bool) public isOwner;
    mapping (address => bool) public isExtension;
    mapping (address => mapping (bytes32 => bool)) public isConfirmed;

    enum Operation {
        Call,
        DelegateCall,
        Create
    }

    modifier onlyWallet() {
        require(msg.sender == address(this));
        _;
    }

    modifier onlyOwner() {
        require(isOwner[msg.sender]);
        _;
    }

    function ()
        external
        payable
    {

    }

    function GnosisSafe(address[] _owners, uint8 _threshold, address to, bytes data)
        public
    {
        setup(_owners, _threshold, to, data);
    }

    function setup(address[] _owners, uint8 _threshold, address to, bytes data)
        public
    {
        require(threshold == 0);
        require(_threshold <= _owners.length);
        require(_threshold >= 1);
        for (uint256 i = 0; i < _owners.length; i++) {
            require(_owners[i] != 0);
            require(!isOwner[_owners[i]]);
            isOwner[_owners[i]] = true;
        }
        owners = _owners;
        threshold = _threshold;
        if (to != 0)
            require(executeDelegateCall(to, data));
    }

    function changeMasterCopy(GnosisSafe _masterCopy)
        public
        onlyWallet
    {
        require(address(_masterCopy) != 0);
        masterCopy = _masterCopy;
    }

    function addOwner(address owner, uint8 _threshold)
        public
        onlyWallet
    {
        require(owner != 0);
        require(!isOwner[owner]);
        owners.push(owner);
        isOwner[owner] = true;
        if (threshold != _threshold)
            changeThreshold(_threshold);
    }

    function removeOwner(uint256 ownerIndex, uint8 _threshold)
        public
        onlyWallet
    {
        require(owners.length - 1 >= _threshold);
        isOwner[owners[ownerIndex]] = false;
        owners[ownerIndex] = owners[owners.length - 1];
        owners.length--;
        if (threshold != _threshold)
            changeThreshold(_threshold);
    }

    function replaceOwner(uint256 oldOwnerIndex, address newOwner)
        public
        onlyWallet
    {
        require(newOwner != 0);
        require(!isOwner[newOwner]);
        isOwner[owners[oldOwnerIndex]] = false;
        isOwner[newOwner] =  true;
        owners[oldOwnerIndex] = newOwner;
    }

    function changeThreshold(uint8 _threshold)
        public
        onlyWallet
    {
        require(_threshold <= owners.length);
        require(_threshold >= 1);
        threshold = _threshold;
    }

    function addExtension(Extension extension)
        public
        onlyWallet
    {
        require(address(extension) != 0);
        require(!isExtension[extension]);
        extensions.push(extension);
        isExtension[extension] = true;
    }

    function removeExtension(uint256 extensionIndex)
        public
        onlyWallet
    {
        isExtension[extensions[extensionIndex]] = false;
        extensions[extensionIndex] = extensions[extensions.length - 1];
        extensions.length--;
    }

    function confirmTransaction(bytes32 transactionHash)
        public
        onlyOwner
    {
        require(!isConfirmed[msg.sender][transactionHash]);
        isConfirmed[msg.sender][transactionHash] = true;
    }

    function confirmAndExecuteTransaction(address to, uint256 value, bytes data, Operation operation, uint8[] v, bytes32[] r, bytes32[] s, address[] _owners, uint256[] indices)
        public
        onlyOwner
    {
        bytes32 transactionHash = getTransactionHash(to, value, data, operation, nonce);
        confirmTransaction(transactionHash);
        executeTransaction(to, value, data, operation, v, r, s, _owners, indices);
    }

    function executeTransaction(address to, uint256 value, bytes data, Operation operation, uint8[] v, bytes32[] r, bytes32[] s, address[] _owners, uint256[] indices)
        public
    {
        bytes32 transactionHash = getTransactionHash(to, value, data, operation, nonce);
        address lastOwner = address(0);
        address validatedOwner;
        uint256 i = 0;
        for (uint256 j = 0; j < threshold; j++) {
            if (indices.length > i && j == indices[i]) {
                require(isConfirmed[_owners[i]][transactionHash]);
                validatedOwner = _owners[i];
                i += 1;
            }
            else
                validatedOwner = ecrecover(transactionHash, v[j-i], r[j-i], s[j-i]);  
            require(isOwner[validatedOwner]);
            require(validatedOwner > lastOwner);
            lastOwner = validatedOwner;
        }
        nonce += 1;
        execute(to, value, data, operation);
    }

    function executeExtension(address to, uint256 value, bytes data, Operation operation, Extension extension)
        public
    {
        require(isExtension[extension]);
        require(extension.isExecutable(msg.sender, to, value, data, operation));
        execute(to, value, data, operation);
    }

    function execute(address to, uint256 value, bytes data, Operation operation)
        internal
    {
        if (operation == Operation.Call)
            require(executeCall(to, value, data));
        else if (operation == Operation.DelegateCall)
            require(executeDelegateCall(to, data));
        else {
            address newContract = executeCreate(data);
            require(newContract != 0);
            ContractCreation(newContract);
        }
    }

    function executeCall(address to, uint256 value, bytes data)
        internal
        returns (bool success)
    {
        assembly {
            success := call(not(0), to, value, add(data, 0x20), mload(data), 0, 0)
        }
    }

    function executeDelegateCall(address to, bytes data)
        internal
        returns (bool success)
    {
        assembly {
            success := delegatecall(not(0), to, add(data, 0x20), mload(data), 0, 0)
        }
    }

    function executeCreate(bytes data)
        internal
        returns (address newContract)
    {
        assembly {
            newContract := create(0, add(data, 0x20), mload(data))
        }
    }

    function getTransactionHash(address to, uint256 value, bytes data, Operation operation, uint256 _nonce)
        public
        view
        returns (bytes32)
    {
        return keccak256(byte(0x19), this, to, value, data, operation, _nonce);
    }

    function getOwners()
        public
        view
        returns (address[])
    {
        return owners;
    }

    function getExtensions()
        public
        view
        returns (Extension[])
    {
        return extensions;
    }
}
