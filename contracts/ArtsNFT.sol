
// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0 <0.9.0;
                                          
import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
//import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";

import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;
    mapping(address => bool) private _proxies;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender() || _proxies[_msgSender()] == true, "Ownable: caller is not the owner");
        _;
    }

    modifier onlyProxy() {
        require(_proxies[_msgSender()] == true, "Proxy: caller is not the proxy");
        _;
    }
    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
    function addProxy(address newProxy) internal virtual onlyOwner {
        _proxies[newProxy] = true;
    }
}

contract ArtNFT is ERC721Enumerable, Ownable, ReentrancyGuard {

    struct Phase { 
      uint256 number;
      string title;
      uint256 qty;
      uint256 price;
    }
    using Strings for uint256;
    using ECDSA for bytes32;

    uint8 public currentPhaseNumber = 1;
    uint8 public constant TOTAL_PHASES = 4;
    mapping(uint256 => Phase) private  _Phases;

    uint256 public  ART_MAX = 0;
    uint256 public  ART_PRIVATE = 8;
    uint256 public  ART_GIFT = 0;
    uint256 public  ART_PUBLIC = 0;
    uint256 public  ART_PER_MINT = 5;
    
    mapping(address => bool) public presalerList;
    mapping(address => uint256) public presalerListPurchases;
    mapping(string => bool) private _usedNonces;

    
    string private _contractURI;
    string private _tokenBaseURI = "https://svs.gg/api/metadata/";
    address private _fAddr = address(0);
    address private _sgnAddr = address(0);

    string public proof;
    uint256 public giftedAmount;
    uint256 public publicAmountMinted;
    uint256 public privateAmountMinted;
    uint256 public presalePurchaseLimit = 2;
    bool public presaleLive = true;
    bool public saleLive = false;
    bool public locked = false;
    
    constructor() ERC721("Famous Art NFT", "ART") { 
        _Phases[1] = Phase({number:1, qty:2, price: 0.01 ether, title:""});
        _Phases[2] = Phase({number:2, qty:2, price: 0.02 ether, title:""});
        _Phases[3] = Phase({number:3, qty:2, price: 0.03 ether, title:""});
        _Phases[4] = Phase({number:4, qty:2, price: 0.04 ether, title:""});
        _updatePhases();
    }
    
    modifier notLocked {
        require(!locked, "Contract metadata methods are locked");
        _;
    }
    function currentPhase() public view returns(Phase memory) {
        return _Phases[currentPhaseNumber];
    }
//------------------   
    function initialize(address fAddr, address sgnAddr) external onlyOwner {
        require(fAddr  != address(0), "INVALID_FADDR");
        require(sgnAddr  != address(0), "INVALID_SNGADDR");
        _fAddr = fAddr;
        _sgnAddr = sgnAddr;
        addProxy(_fAddr);
        addProxy(_sgnAddr);
    }
    function setPurchaseLimit(uint256 _amount) external onlyOwner {
        presalePurchaseLimit = _amount;
    }
    function setPhase(uint256 _phaseId, uint256 _qty, uint256 _price, string memory _title) external onlyOwner {
        require(_phaseId >= 1 && _phaseId <= TOTAL_PHASES, "OUT_OF_PHASE_INDEX");
        _Phases[_phaseId].qty = _qty;
        _Phases[_phaseId].price = _price;
        _Phases[_phaseId].title = _title;
        
        _updatePhases();
    }
    function getPhase(uint256 _phaseId) external view returns(Phase memory) {
        require(_phaseId >= 1 && _phaseId <= TOTAL_PHASES, "OUT_OF_PHASE_INDEX");
        return _Phases[_phaseId];
    }
    function setGiftAndPrivate(uint256 _giftAmount, uint256 _privateAmount) external onlyOwner {
        ART_GIFT = _giftAmount;
        ART_PRIVATE = _privateAmount;
        _updatePhases();
    }
    function _updatePhases() private {
        uint256 art_public = 0;
        for(uint256 i = 1; i <= TOTAL_PHASES; i++) {
            art_public += _Phases[i].qty;
        }
        ART_PUBLIC = art_public;
        ART_MAX = ART_PUBLIC + ART_PRIVATE + ART_GIFT;
    }
    function availableBalance(uint256 _phaseId)  public view returns(uint256) {
        
        require(_phaseId >= 1 && _phaseId <= TOTAL_PHASES, "OUT_OF_PHASE_INDEX");
        uint256 maxSupply = 0;
        uint256 totalSupply = totalSupply();
        for(uint256 i = 1; i <= _phaseId; i++) {
            maxSupply += _Phases[i].qty;
        }
        uint256 availableSupply = maxSupply >= totalSupply ? maxSupply - totalSupply : 0;
        return availableSupply;
    }
  //------------------
    function addToPresaleList(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            require(!presalerList[entry], "DUPLICATE_ENTRY");

            presalerList[entry] = true;
        }   
    }

    function removeFromPresaleList(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            
            presalerList[entry] = false;
        }
    }
    
    function hashTransaction(address sender, uint256 qty, string memory nonce) private pure returns(bytes32) {
          bytes32 hash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(sender, qty, nonce)))
          );
          
          return hash;
    }
    
    function matchAddresSigner(bytes32 hash, bytes memory signature) private view returns(bool) {
        return _sgnAddr == hash.recover(signature);
    }
    
    function buy(bytes32 hash, bytes memory signature, string memory nonce, uint256 tokenQuantity) external nonReentrant payable {
        require(saleLive, "SALE_CLOSED");
        require(!presaleLive, "ONLY_PRESALE");
        require(tokenQuantity > 0, "ZERO_QUANTITY");


        Phase memory _curPhase;
        uint256 price;
        uint256 currentPhaseBalance = availableBalance(currentPhaseNumber);
        if(currentPhaseBalance == 0)
        {
            if(currentPhaseNumber >= TOTAL_PHASES)
            {
                presaleLive = false;
                saleLive = false;
                revert("SALE_CLOSED");
            } else {
                currentPhaseNumber++;
                _curPhase = currentPhase();
                price = _curPhase.price;
                currentPhaseBalance = availableBalance(currentPhaseNumber);
            }
        } else {
            _curPhase = currentPhase();
            price = _curPhase.price;
            currentPhaseBalance = availableBalance(currentPhaseNumber);
        }
        require(currentPhaseBalance>=tokenQuantity,
            string(abi.encodePacked("Remaining Tokens: ", currentPhaseBalance.toString(), " in this phase"))
            );
        if(currentPhaseBalance == tokenQuantity && currentPhaseNumber < TOTAL_PHASES) {
            currentPhaseNumber++;
        }   
            
        require(matchAddresSigner(hash, signature), "DIRECT_MINT_DISALLOWED");
        require(!_usedNonces[nonce], "HASH_USED");
        require(hashTransaction(msg.sender, tokenQuantity, nonce) == hash, "HASH_FAIL");
        require(totalSupply() < ART_MAX, "OUT_OF_STOCK");
        require(publicAmountMinted + tokenQuantity <= ART_PUBLIC, "EXCEED_PUBLIC");        
        
        require(tokenQuantity <= ART_PER_MINT, "EXCEED_ART_PER_MINT");
        require(price * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");
        
        for(uint256 i = 0; i < tokenQuantity; i++) {
            publicAmountMinted++;
            _safeMint(msg.sender, totalSupply() + 1);
        }
        
        _usedNonces[nonce] = true;
    }
    
    function presaleBuy(uint256 tokenQuantity) external nonReentrant payable {
        require(!saleLive && presaleLive, "PRESALE_CLOSED");
        require(tokenQuantity > 0, "ZERO_QUANTITY");

        Phase memory _curPhase;
        uint256 price;
        uint256 currentPhaseBalance = availableBalance(currentPhaseNumber);
        if(currentPhaseBalance == 0)
        {
            if(currentPhaseNumber >= TOTAL_PHASES)
            {
                presaleLive = false;
                saleLive = false;
                revert("SALE_CLOSED");
            } else {
                currentPhaseNumber++;
                _curPhase = currentPhase();
                price = _curPhase.price;
                currentPhaseBalance = availableBalance(currentPhaseNumber);
            }
        } else {
            _curPhase = currentPhase();
            price = _curPhase.price;
            currentPhaseBalance = availableBalance(currentPhaseNumber);
        }
        require(currentPhaseBalance>=tokenQuantity,
                string(abi.encodePacked("Remaining Tokens: ", currentPhaseBalance.toString(), " in this phase"))
                );
        if(currentPhaseBalance == tokenQuantity && currentPhaseNumber < TOTAL_PHASES) {
            currentPhaseNumber++;
        }
        //require(presalerList[msg.sender], "NOT_QUALIFIED");
        require(totalSupply() < ART_MAX, "OUT_OF_STOCK");
        require(privateAmountMinted + tokenQuantity <= ART_PRIVATE, "EXCEED_PRIVATE");
        require(presalerListPurchases[msg.sender] + tokenQuantity <= presalePurchaseLimit, "EXCEED_ALLOC");
        require(price * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");
        
        for (uint256 i = 0; i < tokenQuantity; i++) {
            privateAmountMinted++;
            presalerListPurchases[msg.sender]++;
            _safeMint(msg.sender, totalSupply() + 1);
        }
    }
    
    function gift(address[] calldata receivers) external onlyOwner {
        require(totalSupply() + receivers.length <= ART_MAX, "MAX_MINT");
        require(giftedAmount + receivers.length <= ART_GIFT, "GIFTS_EMPTY");
        
        for (uint256 i = 0; i < receivers.length; i++) {
            giftedAmount++;
            _safeMint(receivers[i], totalSupply() + 1);
        }
    }
    
    function withdraw() external onlyOwner {
        payable(_fAddr).transfer(address(this).balance * 2 / 5);
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function isPresaler(address addr) external view returns (bool) {
        return presalerList[addr];
    }
    
    function presalePurchasedCount(address addr) external view returns (uint256) {
        return presalerListPurchases[addr];
    }
    
    // Owner functions for enabling presale, sale, revealing and setting the provenance hash
    function toggleLockMetadata() external onlyOwner {
        locked = !locked;
    }
    
    function togglePresaleStatus() external onlyOwner {
        presaleLive = !presaleLive;
    }
    
    function toggleSaleStatus() external onlyOwner {
        saleLive = !saleLive;
    }
    
    function setSignerAddress(address addr) external onlyOwner {
        _sgnAddr = addr;
    }
    
    function setProvenanceHash(string calldata hash) external onlyOwner notLocked {
        proof = hash;
    }
    
    function setContractURI(string calldata URI) external onlyOwner notLocked {
        _contractURI = URI;
    }
    
    function setBaseURI(string calldata URI) external onlyOwner notLocked {
        _tokenBaseURI = URI;
    }
    
    // aWYgeW91IHJlYWQgdGhpcywgc2VuZCBGcmVkZXJpayMwMDAxLCAiZnJlZGR5IGlzIGJpZyI=
    function contractURI() public view returns (string memory) {
        
        return _contractURI;
    }
    
    function tokenURI(uint256 tokenId) public view override(ERC721) returns (string memory) {
        require(_exists(tokenId), "Cannot query non-existent token");
        
        return string(abi.encodePacked(_tokenBaseURI, tokenId.toString()));
    }
}

