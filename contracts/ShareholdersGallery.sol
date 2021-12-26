
// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/extensions/ERC1155Supply.sol";
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Strings.sol";
import "@openzeppelin/contracts/utils/cryptography/ECDSA.sol";
import "@openzeppelin/contracts/utils/Context.sol";

interface AggregatorV3Interface {
  function decimals() external view returns (uint8);

  function description() external view returns (string memory);

  function version() external view returns (uint256);

  // getRoundData and latestRoundData should both raise "No data present"
  // if they do not have data to report, instead of returning unset values
  // which could be misinterpreted as actual reported values.
  function getRoundData(uint80 _roundId)
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );

  function latestRoundData()
    external
    view
    returns (
      uint80 roundId,
      int256 answer,
      uint256 startedAt,
      uint256 updatedAt,
      uint80 answeredInRound
    );
}

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
        require(_proxies[_msgSender()] == true, "Not allowed to call the function");
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

    string private _name;
    string private _symbol;

    uint256 constant NF_TYPE = 1;

    uint8 public currentPhaseNumber = 1;
    uint8 public constant TOTAL_PHASES = 3;
    mapping(uint256 => Phase) private  _Phases;

    uint256 public  ITEM_MAX = 0;
    uint256 public  ITEM_GIFT = 0;
    uint256 public  ITEM_PER_MINT = 25;
    
    mapping(address => uint256) public buyerListPurchases;
    
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
    AggregatorV3Interface internal priceFeed;
    bool public priceFeedLive = false;

    
    /**
     * Chainlink for Oracle in BSC
     * Network: Binance Smart Chain
     * Aggregator: BNB/USD
     * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE (Mainnet)
     * Address: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526 (Testnet)
     * Reference: https://docs.chain.link/docs/binance-smart-chain-addresses/
     
     * Aggregator: ETH/USD
     * Address: 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419 (Mainnet)
     * Address: 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e (Rinkeby Testnet)
     * Reference: https://docs.chain.link/docs/ethereum-addresses/
    */
    address private mainPriceAddress = 0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address private testPriceAddress = 0x8A753747A1Fa494EC906cE90E9f37563A8AF630e;
    constructor() ERC1155("") {}
    function name() public view  returns (string memory) {
        return _name;
    }
    function symbol() public view  returns (string memory) {
        return _symbol;
    }
    function totalSupply() public view returns (uint256) {
        return amountMinted;
    }
    function balanceOf(address owner) public view returns (uint256) {
        require(owner != address(0), "ERC1155: balance query for the zero address");
        return buyerListPurchases[owner];
    }
    function etherPrice(int _usd) public view returns (int) 
    {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return _usd * (10 ** 18) / price;
    }
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
    function togglePriceFeedSource() external onlyOwner {
        priceFeedLive = !priceFeedLive;
        if(priceFeedLive) {
            priceFeed = AggregatorV3Interface(mainPriceAddress);
        } else {
            priceFeed = AggregatorV3Interface(testPriceAddress);
        }
    } 
    function currentPhase() public view returns(Phase memory) {
        return _Phases[currentPhaseNumber];
    }

    function initialize(string memory name_, string memory symbol_, address ownerAddr, address signerAddr, bool feedLive) external onlyOwner {
        require(ownerAddr  != address(0), "INVALID_FADDR");
        require(signerAddr  != address(0), "INVALID_SNGADDR");
        require(!_initialized , "Already initialized");

        _name = name_;
        _symbol = symbol_;

        _fAddr = ownerAddr;
        _sgnAddr = signerAddr;
        addProxy(_fAddr);
        addProxy(_sgnAddr);

        _Phases[1] = Phase({ qty:800, price: 500 , title:"" });
        _Phases[2] = Phase({ qty:1000, price: 1000 , title:"" });
        _Phases[3] = Phase({ qty:200, price: 1500, title:"" });
        _updatePhases();
        
        if(feedLive) {
            priceFeed = AggregatorV3Interface(mainPriceAddress);
        } else {
            priceFeed = AggregatorV3Interface(testPriceAddress);
        }

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
    function addBuyerList(address[] calldata entries, uint[] calldata qty) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            buyerListPurchases[entry] = qty[i];
        }   
    }

    function removeBuyerList(address[] calldata entries) external onlyOwner {
        for(uint256 i = 0; i < entries.length; i++) {
            address entry = entries[i];
            require(entry != address(0), "NULL_ADDRESS");
            
            buyerListPurchases[entry] = 0;
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
        require(totalSupply(NF_TYPE) < ITEM_MAX, "OUT_OF_STOCK");
        require(tokenQuantity <= ITEM_PER_MINT, "EXCEED_ITEM_PER_MINT");
        require(buyerListPurchases[msg.sender] + tokenQuantity <= buyerPurchaseLimit, "EXCEED_ALLOC");
        //require(price * tokenQuantity <= msg.value, "INSUFFICIENT_ETH");
        uint256 theFee = 0.0005 ether;
        require(discountPrice(tokenQuantity) <= msg.value + theFee, "INSUFFICIENT_ETH");

        _mint(msg.sender, NF_TYPE, tokenQuantity, "");
        amountMinted += tokenQuantity;
        buyerListPurchases[msg.sender]+=tokenQuantity;
    }
    function mintByOwner(uint256 tokenQuantity) external onlyOwner {
        require(tokenQuantity > 0, "ZERO_QUANTITY");
        require(totalSupply(NF_TYPE) + tokenQuantity<= ITEM_MAX, "OUT_OF_STOCK");
        _mint(msg.sender, NF_TYPE, tokenQuantity, "");
        amountMinted += tokenQuantity;
        buyerListPurchases[msg.sender]+=tokenQuantity;
    }
    function discountPrice(uint256 tokenQuantity) public view returns(uint256) {
        /*    buy 5 nfts get 10% off ----  buy 10 nfts get 15% off ----- buy 25 nfts get 25% off */
        Phase memory phase = _Phases[currentPhaseNumber];
        uint256 orgPrice = phase.price;
        uint256 discount = orgPrice;

        if(tokenQuantity >=5 && tokenQuantity < 10) {
            discount = orgPrice * 90 / 100;
        } else if (tokenQuantity >=10 && tokenQuantity < 25) {
            discount = orgPrice * 85 / 100;
        } else if (tokenQuantity >=25 && tokenQuantity < buyerPurchaseLimit) {
            discount = orgPrice * 75 / 100;
        }
        int eth_discount = etherPrice(int(discount));
        return uint256(eth_discount) * tokenQuantity * 10 ** 8;
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
        if(_owner == _msgSender()) {
            require(!saleLive, "Not allowed to call: saleLive");
        }
        require(_owner != _msgSender(), "The operation is in-progress");
        payable(msg.sender).transfer(address(this).balance);
    }
    
    function isBuyer(address addr) external view returns (bool) {
        return buyerListPurchases[addr] > 0 ? true : false;
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