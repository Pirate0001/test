// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.7.0;

import "./IERC20.sol";
import "./SafeMath.sol";

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * https://github.com/ethereum/EIPs/blob/master/EIPS/eip-20.md
 */
contract TEST is IERC20 {
  using SafeMath for uint256;

  mapping (address => uint256) public _balances;
  
  mapping (address => mapping (address => uint256)) private _allowed;
  
  mapping (address => uint256) private _distBalances;
  mapping (address => uint256) private _distTime;
  mapping (address => uint256[]) private _releaseRates;
  uint256 private baseTime;

  string private _name;
  string private _symbol;
  uint8 private _decimals;
  uint256 private _totalSupply;
  
  constructor(string memory name, string memory symbol, uint8 decimals, uint256 totalSupply) {
    _name = name;
    _symbol = symbol;
    _decimals = decimals;
    _totalSupply = totalSupply * 10 ** decimals;
    _balances[msg.sender] = _totalSupply;
    baseTime = block.timestamp;
  }
  
  /**
   * @return the name of the token.
   */
  function name() public view returns (string memory) {
    return _name;
  }

  /**
   * @return the symbol of the token.
   */
  function symbol() public view returns (string memory) {
    return _symbol;
  }

  /**
   * @return the number of decimals of the token.
   */
  function decimals() public view returns (uint8) {
    return _decimals;
  }

  /**
  * @dev Total number of tokens in existence
  */
  function totalSupply() public override view returns (uint256) {
    return _totalSupply;
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param owner The address to query the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address owner) public override view returns (uint256) {
    return _balances[owner];
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param owner address The address which owns the funds.
   * @param spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(address owner, address spender) public override view returns (uint256) {
    return _allowed[owner][spender];
  }

  /**
  * @dev Transfer token for a specified address
  * @param to The address to transfer to.
  * @param value The amount to be transferred.
  */
  function transfer(address to, uint256 value) public override returns (bool) {
    require(value <= _balances[msg.sender]);
    require(to != address(0));
    require(to != msg.sender);
    
    uint _freeAmount = freeAmount(msg.sender);
    require(_freeAmount >= value);

    _balances[msg.sender] = _balances[msg.sender].sub(value);
    _balances[to] = _balances[to].add(value);
    emit Transfer(msg.sender, to, value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender's allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param spender The address which will spend the funds.
   * @param value The amount of tokens to be spent.
   */
  function approve(address spender, uint256 value) public override returns (bool) {
    require(spender != address(0));

    _allowed[msg.sender][spender] = value;
    emit Approval(msg.sender, spender, value);
    return true;
  }

  /**
   * @dev Transfer tokens from one address to another
   * @param from address The address which you want to send tokens from
   * @param to address The address which you want to transfer to
   * @param value uint256 the amount of tokens to be transferred
   */
  function transferFrom(address from, address to, uint256 value) public override returns (bool) {
    require(value <= _balances[from]);
    require(value <= _allowed[from][msg.sender]);
    require(to != address(0));
    
    uint _freeAmount = freeAmount(from);
    require(_freeAmount >= value);

    _balances[from] = _balances[from].sub(value);
    _balances[to] = _balances[to].add(value);
    _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
    emit Transfer(from, to, value);
    return true;
  }
  
  /**
   * @dev Transfer tokens from one address to another and lock in period time
   * @param from address The address which you want to send tokens from
   * @param to address The address which you want to transfer to
   * @param value uint256 the amount of tokens to be transferred
   * @param period uint8 token lockup period
   */
  function transferFromAndLock(address from, address to, uint256 value, uint256 period, uint256[] memory releaseRates) public override returns (bool) {
    require(_distBalances[to] == 0);
    require(value <= _balances[from]);
    require(value <= _allowed[from][msg.sender]);
    require(to != address(0));

    _balances[from] = _balances[from].sub(value);
    _balances[to] = _balances[to].add(value);
    _allowed[from][msg.sender] = _allowed[from][msg.sender].sub(value);
    
    _distBalances[to] = _distBalances[to].add(value);
    // _distTime[to] = baseTime.add(period * 1 days);
    _distTime[to] = baseTime.add(period * 1 minutes);
    _releaseRates[to] = releaseRates;
    emit Transfer(from, to, value);
    return true;
  }
  
  /**
  * @dev Check if the specified address has restricted balance
  */
  function hasLocked(address user) public override view returns (bool) {
      if (_distBalances[user] == 0) {
          return false;
      }
      return true;
  }
  
    /**
  * @dev Gets the unrestricted balance of the specified address.
  */
  function freeAmount(address user) internal view returns (uint256 amount) {
    if (_distBalances[user] == 0) {
        return _balances[user];
    }
    
    // no free amount before unlock time;
    if (block.timestamp < _distTime[user]) {
        return _balances[user].sub(_distBalances[user]);
    }

    //2) calculate number of months passed since unlock time;
    uint monthDiff = (block.timestamp.sub(_distTime[user])).div(2 minutes);
    // uint monthDiff = (block.timestamp.sub(_distTime[user])).div(30 days);

    //3) if it is over {unlock period} months, free up everything.
    uint unlockPeriod = _releaseRates[user].length;
    if (monthDiff + 1 >= unlockPeriod) {
        return _balances[user];
    }

    //4) calculate amount of unlocked within distrubute amount.
    uint rate = 0;
    for (uint i = 0; i <= monthDiff; i++) {
        rate = rate.add(_releaseRates[user][i]);
    }
    
    uint unlocked = _distBalances[user].mul(rate).div(1000);
    if (unlocked > _distBalances[user]) {
        unlocked = _distBalances[user];
    }
    
    //5) unrestricted + unlock
    if (unlocked.add(_balances[user]) < _distBalances[user]) {
        amount = 0;
    } else {
        amount = unlocked.add(_balances[user]).sub(_distBalances[user]);
    }
    
    return amount;
  }
}