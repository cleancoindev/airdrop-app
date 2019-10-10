pragma solidity ^0.4.24;

import "@aragon/os/contracts/apps/AragonApp.sol";
import "@aragon/apps-token-manager/contracts/TokenManager.sol";

contract Airdrop is AragonApp {

    struct Airdrop {
      bytes32 root;
      string dataURI;
      mapping(address => bool) awarded;
    }

    /// Events
    event Start(uint id);
    event Award(uint id, address recipient, uint amount);

    /// State
    mapping(uint => Airdrop) public airdrops;
    TokenManager public tokenManager;
    uint public airdropsCount;

    /// ACL
    bytes32 constant public START_ROLE = keccak256("START_ROLE");

    // Errors
    string private constant ERROR_AWARDED = "AWARDED";
    string private constant ERROR_INVALID = "INVALID";

    function initialize(address _tokenManager) onlyInit public {
        initialized();

        tokenManager = TokenManager(_tokenManager);
    }

    /**
     * @notice Start a new airdrop `_root` / `_dataURI`
     * @param _root New airdrop merkle root
     * @param _dataURI Data URI for airdrop data
     */
    function start(bytes32 _root, string _dataURI) auth(START_ROLE) public {
        _start(_root, _dataURI);
    }

    function _start(bytes32 _root, string _dataURI) internal returns(uint id){
        id = ++airdropsCount;    // start at 1
        airdrops[id] = Airdrop(_root, _dataURI);
        emit Start(id);
    }

    /**
     * @notice Award from airdrop
     * @param _id Airdrop id
     * @param _recipient Airdrop recipient
     * @param _amount The token amount
     * @param _proof Merkle proof to correspond to data supplied
     */
    function award(uint _id, address _recipient, uint256 _amount, bytes32[] _proof) public {
        Airdrop storage airdrop = airdrops[_id];

        bytes32 hash = keccak256(_recipient, _amount);
        require( validate(airdrop.root, _proof, hash), ERROR_INVALID );

        require( !airdrops[_id].awarded[_recipient], ERROR_AWARDED );

        airdrops[_id].awarded[_recipient] = true;

        tokenManager.mint(_recipient, _amount);

        emit Award(_id, _recipient, _amount);
    }

    /**
     * @notice Award from airdrop
     * @param _ids Airdrop ids
     * @param _recipient Recepient of award
     * @param _amounts The amounts
     * @param _proofs Merkle proofs
     * @param _proofLengths Merkle proof lengths
     */
    function awardFromMany(uint[] _ids, address _recipient, uint[] _amounts, bytes _proofs, uint[] _proofLengths) public {
        uint totalAmount;

        uint marker = 32;

        for (uint i = 0; i < _ids.length; i++) {
            uint id = _ids[i];

            bytes32[] memory proof = extractProof(_proofs, marker, _proofLengths[i]);
            marker += _proofLengths[i]*32;

            bytes32 hash = keccak256(_recipient, _amounts[i]);
            require( validate(airdrops[id].root, proof, hash), ERROR_INVALID );

            require( !airdrops[id].awarded[_recipient], ERROR_AWARDED );

            airdrops[id].awarded[_recipient] = true;

            totalAmount += _amounts[i];

            emit Award(id, _recipient, _amounts[i]);
        }

        tokenManager.mint(_recipient, totalAmount);
    }

    /**
     * @notice Award from airdrop
     * @param _id Airdrop ids
     * @param _recipients Recepients of award
     * @param _amounts The amounts
     * @param _proofs Merkle proofs
     * @param _proofLengths Merkle proof lengths
     */
    function awardToMany(uint _id, address[] _recipients, uint[] _amounts, bytes _proofs, uint[] _proofLengths) public {
        uint marker = 32;

        for (uint i = 0; i < _recipients.length; i++) {
            address recipient = _recipients[i];

            if( recipient == address(0) )
                continue;

            if( airdrops[_id].awarded[recipient] )
                continue;

            airdrops[_id].awarded[recipient] = true;

            bytes32[] memory proof = extractProof(_proofs, marker, _proofLengths[i]);
            marker += _proofLengths[i]*32;

            bytes32 hash = keccak256(recipient, _amounts[i]);
            if( !validate(airdrops[_id].root, proof, hash) )
                continue;

            tokenManager.mint(recipient, _amounts[i]);

            emit Award(_id, recipient, _amounts[i]);
        }
    }

    function extractProof(bytes _proofs, uint _marker, uint proofLength) public pure returns (bytes32[] proof) {

        proof = new bytes32[](proofLength);

        bytes32 el;

        for (uint j = 0; j < proofLength; j++) {
            assembly {
                el := mload(add(_proofs, _marker))
            }
            proof[j] = el;
            _marker += 32;
        }

    }

    function validate(bytes32 root, bytes32[] proof, bytes32 hash) public pure returns (bool) {

        for (uint i = 0; i < proof.length; i++) {
            if (hash < proof[i]) {
                hash = keccak256(hash, proof[i]);
            } else {
                hash = keccak256(proof[i], hash);
            }
        }

        return hash == root;
    }

    /**
     * @notice Check if recipient:`_recipient` awarded from airdrop:`_id`
     * @param _id Airdrop id
     * @param _recipient Recipient to check
     */
    function awarded(uint _id, address _recipient) public view returns(bool) {
        return airdrops[_id].awarded[_recipient];
    }
}
