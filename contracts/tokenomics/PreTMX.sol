import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

contract PreTMX is ERC20, AccessControl {
    bool public transferRestricted;

    mapping(address => bool) public isTransferredFromWhitelisted;
    mapping(address => bool) public isTransferredToWhitelisted;

    error TransferFromNotWhitelisted(address from);
    error TransferToNotWhitelisted(address to);

    constructor(address admin) ERC20("Pre TermMax Token", "pTMX") {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _mint(admin, 1e9 ether);
        transferRestricted = true;
        isTransferredFromWhitelisted[admin] = true;
        isTransferredToWhitelisted[admin] = true;
    }

    function enableTransfer() external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestricted = false;
    }

    function disableTransfer() external onlyRole(DEFAULT_ADMIN_ROLE) {
        transferRestricted = true;
    }

    function whitelistTransferFrom(address from, bool isWhitelisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isTransferredFromWhitelisted[from] = isWhitelisted;
    }

    function whitelistTransferTo(address to, bool isWhitelisted) external onlyRole(DEFAULT_ADMIN_ROLE) {
        isTransferredToWhitelisted[to] = isWhitelisted;
    }

    function transfer(address to, uint256 amount) public override returns (bool) {
        _beforeTokenTransfer(msg.sender, to);
        return super.transfer(to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) public override returns (bool) {
        _beforeTokenTransfer(from, to);
        return super.transferFrom(from, to, amount);
    }

    function mint(address to, uint256 amount) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _mint(to, amount);
    }

    function burn(uint256 amount) external {
        _burn(msg.sender, amount);
    }

    function _beforeTokenTransfer(address from, address to) internal view {
        if (transferRestricted && !isTransferredFromWhitelisted[from]) {
            revert TransferFromNotWhitelisted(from);
        }
        if (transferRestricted && !isTransferredToWhitelisted[to]) {
            revert TransferToNotWhitelisted(to);
        }
    }
}
