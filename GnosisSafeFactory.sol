pragma solidity 0.4.19;
import "./GnosisSafe.sol";
import "./Proxy.sol";


contract GnosisSafeFactory {

    event GnosisSafeCreation(GnosisSafe gnosisSafe);

    GnosisSafe public masterCopy; 

    function GnosisSafeFactory()
        public
    {
        address[] memory owners = new address[](1);
        owners[0] = this;
        masterCopy = new GnosisSafe(owners, 1, Extension(0));
    }

    function createGnosisSafe(address[] owners, uint8 threshold, address extensionFactory, bytes extensionData)
        public
        returns (GnosisSafe gnosisSafe)
    {
        Extension extension;
        if (extensionFactory != 0)
            extension = createExtension(extensionFactory, extensionData);
        // Create Gnosis Safe
        gnosisSafe = GnosisSafe(new Proxy(masterCopy));
        gnosisSafe.setup(owners, threshold, extension);
        GnosisSafeCreation(gnosisSafe);
        // Update extension owner
        if (address(extension) > 0)
            extension.changeGnosisSafe(gnosisSafe);
    }

    function createExtension(address extensionFactory, bytes extensionData)
        internal
        returns (Extension extension)
    {
        // Create extension
        bool success;
        uint256 extensionDataLength = extensionData.length;
        assembly {
            let output := mload(0x40)
            success := call(
                sub(gas, 34710),
                extensionFactory,
                0,
                add(extensionData, 32),
                extensionDataLength,
                output,
                32
            )
            extension := and(mload(output), 0xffffffffffffffffffffffffffffffffffffffff)
        }
        require(success);
    }
}
