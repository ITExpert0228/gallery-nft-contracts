
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Context.sol";

abstract contract Ownable is Context {
    address internal _owner;
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

/*
    buy 5 nfts get 10% off ----  buy 10 nfts get 15% off ----- buy 25 nfts get 25% off

    pre-sale 400 nfts = $500 each
    phase 1 - 1200 nfts = $1000 each
    final phase 400 nfts = $1500 each 
*/
contract ShareholdersGallery is Ownable, ERC1155Supply, ReentrancyGuard {

    struct Phase { 
      string title;
      uint256 qty;
      uint256 price;
    }

    using Strings for uint256;
    using ECDSA for bytes32;

    uint256 constant NF_TYPE = 1;

    uint8 public currentPhaseNumber = 1;
    uint8 public constant TOTAL_PHASES = 3;
    mapping(uint256 => Phase) private  _Phases;

    uint256 public  ITEM_MAX = 0;
    uint256 public  ITEM_GIFT = 0;
    uint256 public  ITEM_PER_MINT = 25;
    
    mapping(address => bool) public buyerList;
    mapping(address => uint256) public buyerListPurchases;
    mapping(string => bool) private _usedNonces;

    
    string private _contractURI;
    string private _tokenBaseURI = "https://shareholdersgallery.com/";
    address private _fAddr = address(0);
    address private _sgnAddr = address(0);

    string public proof;
    uint256 public giftedAmount;
    uint256 public amountMinted;
    uint256 public buyerPurchaseLimit = 50;
    bool public saleLive = true;
    bool public locked = false;
    bool private _initialized = false;

    constructor() ERC1155("") {}

    function setURI(string memory newuri) public onlyOwner {
        _setURI(newuri);
        _tokenBaseURI = newuri;
    }
    function uri(uint256 typeId) public view override returns (string memory) {
        return string(abi.encodePacked(_tokenBaseURI, typeId.toString()));
    }
    /*
    *   Define Modifiers
    */
    modifier notLocked {
        require(!locked, "Contract metadata methods are locked");
        _;
    }
    /*
    *  Define public and external functions
    */

    function currentPhase() public view returns(Phase memory) {
        return _Phases[currentPhaseNumber];
    }

    function initialize(address ownerAddr, address signerAddr) external onlyOwner {
        require(ownerAddr  != address(0), "INVALID_FADDR");
        require(signerAddr  != address(0), "INVALID_SNGADDR");
        require(!_initialized , "Already initialized");


        _fAddr = ownerAddr;
        _sgnAddr = signerAddr;
        addProxy(_fAddr);
        addProxy(_sgnAddr);

        _Phases[1] = Phase({ qty:4, price: 0.25 ether, title:"" });
        _Phases[2] = Phase({ qty:12, price: 0.5 ether, title:"" });
        _Phases[3] = Phase({ qty:4, price: 0.75 ether, title:"" });
        _updatePhases();
        _initialized = true;

    }
    function setPurchaseLimit(uint256 _amount) external onlyOwner {
        buyerPurchaseLimit = _amount;
    }
    function setPhase(uint256 _phaseId, uint256 _qty, uint256 _price, string memory _title) external onlyOwner {
        require(_initialized , "Not initialized");
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
    function setGift(uint256 _giftAmount) external onlyOwner {
        require(_initialized , "Not initialized");
        ITEM_GIFT = _giftAmount;
        _updatePhases();
    }
    function _updatePhases() private {
        uint256 item_public = 0;
        for(uint256 i = 1; i <= TOTAL_PHASES; i++) {
            item_public += _Phases[i].qty;
        }
        ITEM_MAX = item_public + ITEM_GIFT;
    }
    function availableBalance(uint256 _phaseId)  public view returns(uint256) {
        
        require(_phaseId >= 1 && _phaseId <= TOTAL_PHASES, "OUT_OF_PHASE_INDEX");
        uint256 maxSupply = 0;
        uint256 supplied = totalSupply(NF_TYPE);
        for(uint256 i = 1; i <= _phaseId; i++) {
            maxSupply += _Phases[i].qty;
        }
        uint256 availableSupply = maxSupply >= supplied ? maxSupply - supplied : 0;
        return availableSupply;
    }
  //------------------
    function addBuyerList(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            buyerList[entry] = true;
        }   
    }

    function removeBuyerList(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            
            buyerList[entry] = false;
        }
    }
    function buyPhase(uint256 tokenQuantity) external nonReentrant payable {
        require(saleLive, "SALE_CLOSED");
        require(tokenQuantity > 0, "ZERO_QUANTITY");

        Phase memory _curPhase;
        uint256 price;
        uint256 currentPhaseBalance = availableBalance(currentPhaseNumber);
        if(currentPhaseBalance == 0)
        {
            if(currentPhaseNumber >= TOTAL_PHASES)
            {
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
        //require(buyerList[msg.sender], "NOT_QUALIFIED");
        require(totalSupply(NF_TYPE) < ITEM_MAX, "OUT_OF_STOCK");
        require(tokenQuantity <= ITEM_PER_MINT, "EXCEED_ITEM_PER_MINT");
        require(buyerListPurchases[msg.sender] + tokenQuantity <= buyerPurchaseLimit, "EXCEED_ALLOC");
        require(price * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");

        _mint(msg.sender, NF_TYPE, tokenQuantity, "");
        amountMinted += tokenQuantity;
        buyerListPurchases[msg.sender]+=tokenQuantity;
        buyerList[msg.sender] = true;

    }
    
    function gift(address[] calldata receivers) external onlyOwner {
        require(totalSupply(NF_TYPE) + receivers.length <= ITEM_MAX, "MAX_MINT");
        require(giftedAmount + receivers.length <= ITEM_GIFT, "GIFTS_EMPTY");
        
        for (uint256 i = 0; i < receivers.length; i++) {
            _mint(msg.sender, NF_TYPE, 1, "");
            giftedAmount++;
        }
    }
    
    function withdraw() external onlyOwner {
        require(!saleLive, "Sale in-progress");
        require(_owner != _msgSender(), "The operation is in-progress");
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function isBuyer(address addr) external view returns (bool) {
        return buyerList[addr];
    }
    
    function buyerPurchasedCount(address addr) external view returns (uint256) {
        return buyerListPurchases[addr];
    }
    
    // Owner functions for enabling presale, sale, revealing and setting the provenance hash
    function toggleLockMetadata() external onlyOwner {
        locked = !locked;
    }
    
    function toggleSaleStatus() external onlyProxy {
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
    
    // aWYgeW91IHJlYWQgdGhpcywgc2VuZCBGcmVkZXJpayMwMDAxLCAiZnJlZGR5IGlzIGJpZyI=
    function contractURI() public view returns (string memory) {
        
        return _contractURI;
    }
    /*
    * Define Private and Internal Functions
    */
    function _hashTransaction(address sender, uint256 qty, string memory nonce) private pure returns(bytes32) {
          bytes32 hash = keccak256(abi.encodePacked(
            "\x19Ethereum Signed Message:\n32",
            keccak256(abi.encodePacked(sender, qty, nonce)))
          );
          
          return hash;
    }
    
    function _matchAddresSigner(bytes32 hash, bytes memory signature) private view returns(bool) {
        return _sgnAddr == hash.recover(signature);
    }

    // The following functions are overrides required by Solidity.
}