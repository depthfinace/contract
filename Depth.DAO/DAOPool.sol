pragma solidity 0.8.3;

library SafeMath {
    
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b != 0, errorMessage);
        return a % b;
    }
}

interface ERC20 {
    function transfer(address _to, uint256 _value) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
    function balanceOf(address _owner) external view returns (uint256 balance);
}

interface MintableToken is ERC20 {
    function mint(address _to, uint256 _amount) external returns (bool);
    function burn(address _to, uint256 _amount) external returns (bool);
}

contract DAOPool {
    
    struct UnlockRequest {
        uint256 amount;
        uint256 unlockTimestamp;
    }
    
    struct UserInfo {
        uint256 amount;     
        uint256 aEpoch;
    }
    
    uint256 public epochLength;
    
    uint256 public startTime;
    
    uint256 public oddRewards;
    
    uint256 public evenRewards;
    
    address[] public addressSet;
    
    uint256 public lockingLength;
    
    mapping(address => UserInfo) public userInfo;
    
    mapping(address => UnlockRequest[]) public userUnlockRequests;
    
    ERC20 public HUSD = ERC20(0x0298c2b32eaE4da002a15f36fdf7615BEa3DA047);
    
    ERC20 public DEP = ERC20(0x48C859531254F25e57D1C1A8E030Ef0B1c895c27);
    
    MintableToken public xDEP;
    
    constructor(address xDEPAddress) {
        epochLength = 1 minutes;
        startTime = block.timestamp;
        oddRewards = 0;
        evenRewards = 0;
        xDEP = MintableToken(xDEPAddress);
        lockingLength = 2 minutes;
    }
    
    function currentEpoch() view public returns(uint256) {
        uint256 period = block.timestamp - startTime;
        return SafeMath.div(period, epochLength);
    }
    
    function _isEven() view private returns (bool) {
        uint256 e = currentEpoch();
        return SafeMath.mod(e, 2) == 0;
    }
    
    function donateHUSD(uint256 amount) public {
        require(HUSD.transferFrom(msg.sender, address(this), amount), "aaaa");
        bool isEven = _isEven();
        if (isEven) {
            evenRewards = evenRewards + amount;
        } else {
            oddRewards = oddRewards + amount;
        }
    }
    
    function _addAddress(address add) private {
        for (uint256 i = 0; i < addressSet.length; i++) {
            if (addressSet[i] == add) return;
        }
        addressSet.push(add);
    }
    
    
    function _totalAmount() public view returns(uint256) {
        if (currentEpoch() == 0) return 0;
        
        uint256 sum = 0;
        for (uint256 i = 0; i < addressSet.length; i++) {
            address add = addressSet[i];
            UserInfo memory user = userInfo[add];
            if (user.aEpoch <= currentEpoch() - 1) sum = sum + user.amount;
        }
        return sum;
    }
    
    function stake(uint256 _amount) public {
        require(_amount > 0);
        
        claim(msg.sender);
        
        UserInfo storage user = userInfo[msg.sender];
        _addAddress(msg.sender);
        require(DEP.transferFrom(msg.sender, address(this), _amount), "bbbb");
        if (user.amount > 0) {
            user.amount = user.amount + _amount;
        } else {
            user.amount = _amount;
        }
        require(xDEP.mint(msg.sender, _amount), "mint failed");
    }
    
    function _totalRewards() public view returns (uint256) {
        if (_isEven()) {
            return oddRewards;
        } else {
            return evenRewards;
        }
    }
    
    function pendingReward(address who) public view returns (uint256) {
        if (currentEpoch() == 0) return 0;
        
        UserInfo storage user = userInfo[who];
        uint256 totalAmount = _totalAmount();
        if (totalAmount != 0 && user.aEpoch <= currentEpoch() - 1) {
            return SafeMath.div(SafeMath.mul(user.amount, _totalRewards()), totalAmount);
        } else {
            return 0;
        }
    }
    
    function _unlockingAmount(address who) public view returns (uint256) {
        UnlockRequest[] memory reqs = userUnlockRequests[who];
        uint256 sum = 0;
        for (uint256 i = 0; i < reqs.length; i++) {
            sum += reqs[i].amount;
        }
        return sum;
    }
    
    function unlock(uint256 _amount) public {
        claim(msg.sender);
        UserInfo storage user = userInfo[msg.sender];
        user.amount = SafeMath.sub(user.amount, _amount);
        userUnlockRequests[msg.sender].push(UnlockRequest({
            amount: _amount,
            unlockTimestamp: block.timestamp
        }));
    }
    
    function _relock(uint256 index) private {
        UserInfo storage user = userInfo[msg.sender];
        UnlockRequest[] storage reqs = userUnlockRequests[msg.sender];
        user.amount = user.amount + reqs[index].amount;
        _deleteRequestAt(index);
    }
    
    function _deleteRequestAt(uint256 index) private {
        UnlockRequest[] storage reqs = userUnlockRequests[msg.sender];
        for (uint256 i = index; i < reqs.length - 1; i++) {
            reqs[i] = reqs[i + 1];
        }
        reqs.pop();
    }
    
    function relock(uint256 index) public {
        claim(msg.sender);
        _relock(index);
    }
    
    function relockAll() public {
        claim(msg.sender);
        uint256 reqsN = userUnlockRequests[msg.sender].length;
        for (uint256 i = 0; i < reqsN; i++) {
            _relock(i);
        }
    }
    
    function lockRequestCount(address who) public view returns (uint256) {
        return userUnlockRequests[who].length;
    }
    
    function unlockableAmount(address who) public view returns (uint256) {
        UnlockRequest[] memory reqs = userUnlockRequests[who];
        uint256 sum = 0;
        for (uint256 i = 0; i < reqs.length; i++) {
            if (block.timestamp - reqs[i].unlockTimestamp > lockingLength) {
                sum += reqs[i].amount;
            }
        }
        uint256 xDEPBalance = xDEP.balanceOf(who);
        if (xDEPBalance < sum) {
            return xDEPBalance;
        } else {
            return sum;
        }
    }

    function unStake() public {
        UnlockRequest[] storage reqs = userUnlockRequests[msg.sender];
        uint256 amount = unlockableAmount(msg.sender);
        require(amount != 0, "No Available Dep");
        DEP.transfer(msg.sender, amount);
        for (uint256 iPlusOne = reqs.length; iPlusOne > 0; iPlusOne--) {
            uint256 i = iPlusOne - 1;
            if (block.timestamp - reqs[i].unlockTimestamp > lockingLength) {
                _deleteRequestAt(i);
            }
        }
        require(xDEP.burn(msg.sender, amount), "burn failed");
    }
    
    function claim(address _user) public {
        UserInfo storage user = userInfo[_user];
        uint256 rewards = pendingReward(_user);
        if (rewards > 0) {
            require(HUSD.transfer(_user, rewards), "HUSD.transfer(msg.sender, rewardAmount)");
            if (_isEven()) {
                oddRewards = SafeMath.sub(oddRewards, rewards);
            } else {
                evenRewards = SafeMath.sub(evenRewards, rewards);
            }
            user.aEpoch = currentEpoch();
        }
    }
    
}