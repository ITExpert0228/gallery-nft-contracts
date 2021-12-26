// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;
pragma experimental ABIEncoderV2;

import "../node_modules/@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";
import "../node_modules/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../node_modules/@openzeppelin/contracts/utils/Counters.sol";
import "../node_modules/@chainlink/contracts/src/v0.8/interfaces/AggregatorV3Interface.sol";

contract LXRNFT is ERC721, Ownable, ReentrancyGuard {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;  
    string baseURI;
    bool isSaleActive;
    int usdPerNft;
    mapping (uint256 => TokenMeta) private _tokenMeta;
    AggregatorV3Interface internal priceFeed;    

    struct TokenMeta {
        uint256 id;
        uint256 price;
        uint power;
        bool sale;
    }

    /**
     * Chainlink for Oracle in BSC
     * Network: Binance Smart Chain
     * Aggregator: BNB/USD
     * Address: 0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE (Mainnet)
     * Address: 0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526 (Testnet)
     * Reference: https://docs.chain.link/docs/binance-smart-chain-addresses/
    */    
    constructor() ERC721("Loxarian NFT", "LXRT") {
        baseURI = "http://loxarian.com/token/";
        isSaleActive = false;
        usdPerNft = 5000000000; // 50 usd
        priceFeed = AggregatorV3Interface(0x2514895c72f50D8bd4B4F9b1110F0D6bD2c97526);
    }
    
    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    function _baseURI() internal view override virtual returns (string memory) {
        return baseURI;
    }

    function setBaseURI(string memory _newBaseURI) public virtual onlyOwner {
        baseURI = _newBaseURI;
    }

    /**
     * @dev Ready Mint Flag for starting Sales.
     * in child contracts.
     */
    function _isSaleActive() internal view returns (bool) {
        return isSaleActive;
    }

    function setSaleActive(bool _newisSaleActive) public onlyOwner {
        isSaleActive = _newisSaleActive;
    }
    
    function getAllOnSale () public view virtual returns( TokenMeta[] memory ) {
        uint256 counter = 0;
        for(uint i = 1; i < _tokenIds.current() + 1; i++) {
            if(_tokenMeta[i].sale == true) {
                counter++;
            }
        }
        TokenMeta[] memory tokensOnSale = new TokenMeta[](counter);
        counter = 0;
        for(uint i = 1; i < _tokenIds.current() + 1; i++) {
            if(_tokenMeta[i].sale == true) {
                tokensOnSale[counter] = _tokenMeta[i];
                counter++;
            }
        }
        return tokensOnSale;
    }

    /**
     * @dev sets maps token to its price
     * @param _tokenId uint256 token ID (token number)
     * @param _sale bool token on sale
     * @param _price unit256 token price
     * 
     * Requirements: 
     * `tokenId` must exist
     * `price` must be more than 0
     * `owner` must the msg.owner
     */
    function setTokenSale(uint256 _tokenId, bool _sale, uint256 _price) public {
        require(_exists(_tokenId), "Sale set of Non Existent Token");
        require(_price > 0, "Price for sale needs to bigger than 0 ether");
        require(ownerOf(_tokenId) == _msgSender());

        _tokenMeta[_tokenId].sale = _sale;
        setTokenPrice(_tokenId, _price);
    }

    /**
     * @dev sets maps token to its price
     * @param _tokenId uint256 token ID (token number)
     * @param _price uint256 token price
     * 
     * Requirements: 
     * `tokenId` must exist
     * `owner` must the msg.owner
     */
    function setTokenPrice(uint256 _tokenId, uint256 _price) public {
        require(_exists(_tokenId), "Price set of Non Existent token");
        require(ownerOf(_tokenId) == _msgSender());
        _tokenMeta[_tokenId].price = _price;
    }

    function tokenPrice(uint256 tokenId) public view virtual returns (uint256) {
        require(_exists(tokenId), "Price query for Non Existent token");
        return _tokenMeta[tokenId].price;
    }

    function tokenMintedCount() public view virtual returns (uint256) {
        return _tokenIds.current();
    }

    /**
     * @dev sets token meta
     * @param _tokenId uint256 token ID (token number)
     * @param _meta TokenMeta 
     * 
     * Requirements: 
     * `tokenId` must exist
     * `owner` must the msg.owner
     */
    function _setTokenMeta(uint256 _tokenId, TokenMeta memory _meta) private {
        require(_exists(_tokenId));
        _tokenMeta[_tokenId] = _meta;
    }

    function tokenMeta(uint256 _tokenId) public view returns (TokenMeta memory) {
        require(_exists(_tokenId), "Meta data query for Non Existent token");
        return _tokenMeta[_tokenId];
    }

    /**
     * @dev purchase _tokenId
     * @param _tokenId uint256 token ID (token number)
     */
    function purchaseToken(uint256 _tokenId) external payable nonReentrant {
        require(msg.sender != address(0) && msg.sender != ownerOf(_tokenId), "Invalid sender");
        require(msg.value >= _tokenMeta[_tokenId].price, "Price needs to bigger than token's price");
        require(_tokenMeta[_tokenId].sale == true, "The token is not sale now.");
        require(isSaleActive == true, "Minting is coming soon.");
        
        address tokenSeller = ownerOf(_tokenId);

        payable(tokenSeller).transfer(msg.value);

        setApprovalForAll(tokenSeller, true);
        _transfer(tokenSeller, msg.sender, _tokenId);
        _tokenMeta[_tokenId].sale = false;
    }

    function mintToken() external payable nonReentrant returns (uint256) {
        require(owner() != address(0), "Invalid Contract Owner");
        require(msg.sender != address(0), "Invalid sender");        
        require(isSaleActive == true, "Minting is not available now.");

        uint _price = uint(_getPrice(usdPerNft));
        require(msg.value >= _price, "Price for sale needs to bigger than 25 USD");

        payable(owner()).transfer(_price);
        setApprovalForAll(owner(), true);
        
        _tokenIds.increment();
        uint256 newItemId = _tokenIds.current();
        _mint(msg.sender, newItemId);
        
        TokenMeta memory meta = TokenMeta(newItemId, _price, _generateRandomPower(), false);
        _setTokenMeta(newItemId, meta);
        
        return newItemId;
    }
    
    function mintAdmin(address _to, uint256 _count)
        external 
        onlyOwner
    {
        require(_to != address(0), "Invalid receiver");
        uint _price = uint(_getPrice(usdPerNft));

        for (uint256 i; i < _count; i++) {
            _tokenIds.increment();
            uint256 newItemId = _tokenIds.current();
            _mint(payable(_to), newItemId);

            TokenMeta memory meta = TokenMeta(newItemId, _price, _generateRandomPower(), false);
            _setTokenMeta(newItemId, meta);
        }
    }

    // Function to generate the hash value
    function _generateRandomPower() internal view returns (uint) 
    {
        uint random = uint(blockhash(block.number));
        uint group = uint(random % 100);
        uint power = 100;
        if (group <= 2) {
            power = random % (250 - 100) + 100;
        }
        else if (group <= 8) {
            power = random % (500 - 250) + 250;
        }
        else if (group <= 25) {
            power = random % (1000 - 500) + 500;
        }
        else {
            power = random % (2000 - 1000) + 1000;
        }
        return power;        
    }

    // _usdPrice: USD Price * 100000000
    // _return: BNB Price (wei)
    function _getPrice(int _usdPrice) internal view returns (int) 
    {
        (
            uint80 roundID,
            int price,
            uint startedAt,
            uint timeStamp,
            uint80 answeredInRound
        ) = priceFeed.latestRoundData();
        return _usdPrice * (10 ** 18) / price;
    }
}