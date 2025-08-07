// SPDX-License-Identifier: AGPL-3.0-or-later
// Copyright (C) 2021 Dai Foundation
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU Affero General Public License for more details.
//
// You should have received a copy of the GNU Affero General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

pragma solidity ^0.6.12;

import {UsddJoinAbstract} from "src/interfaces/dss/UsddJoinAbstract.sol";
import {UsddAbstract} from "src/interfaces/dss/UsddAbstract.sol";
import {VatAbstract} from "src/interfaces/dss/VatAbstract.sol";

interface AuthGemJoinAbstract {
    function dec() external view returns (uint256);

    function vat() external view returns (address);

    function ilk() external view returns (bytes32);

    function join(address, uint256, address) external;

    function exit(address, uint256) external;
}

// USDD Peg Stability Module
contract UsddPsm {

    // --- Auth ---
    mapping(address => uint256) public wards;

    function rely(address usr) external auth {wards[usr] = 1;
        emit Rely(usr);}

    function deny(address usr) external auth {wards[usr] = 0;
        emit Deny(usr);}
    modifier auth {require(wards[msg.sender] == 1, "UsddPsm/not-authorized");
        _;}

    VatAbstract immutable public vat;
    AuthGemJoinAbstract immutable public gemJoin;   // Stablecoin Join adapter
    UsddAbstract immutable public usdd;             // USDD token
    UsddJoinAbstract immutable public usddJoin;     // USDD Join adapter
    bytes32 immutable public ilk;                   // Collateral type
    address immutable public vow;                   // System treasury

    uint256 immutable internal to18ConversionFactor;

    // --- State Variables ---
    uint256 public tin;         // Fee in [wad]
    uint256 public tout;        // Fee out [wad]
    uint256 public sellEnabled; // Stablecoin -> USDD enabled
    uint256 public buyEnabled;  // USDD -> Stablecoin enabled

    // --- Events ---
    event Rely(address indexed usr);
    event Deny(address indexed usr);
    event File(bytes32 indexed what, uint256 data);
    event SellGem(address indexed owner, uint256 value, uint256 fee);
    event BuyGem(address indexed owner, uint256 value, uint256 fee);

    // --- Init ---
    constructor(
        address gemJoin_,    // Stablecoin Join adapter
        address usddJoin_,   // USDD Join adapter
        address vow_         // System treasury
    ) public {
        wards[msg.sender] = 1;
        emit Rely(msg.sender);

        AuthGemJoinAbstract gemJoin__ = gemJoin = AuthGemJoinAbstract(gemJoin_);
        UsddJoinAbstract usddJoin__ = usddJoin = UsddJoinAbstract(usddJoin_);
        VatAbstract vat__ = vat = VatAbstract(address(gemJoin__.vat()));
        UsddAbstract usdd__ = usdd = UsddAbstract(address(usddJoin__.usdd()));

        ilk = gemJoin__.ilk();
        vow = vow_;

        // Handle decimals conversion
        to18ConversionFactor = 10 ** (18 - gemJoin__.dec());

        // Set initial state
        sellEnabled = 1;  // Enable by default
        buyEnabled = 1;   // Enable by default

        // Approve max amount for USDD transfers
        usdd__.approve(usddJoin_, uint256(-1));
        vat__.hope(usddJoin_);
    }

    // --- Math ---
    uint256 constant WAD = 10 ** 18;
    uint256 constant RAY = 10 ** 27;

    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "UsddPsm/add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "UsddPsm/sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "UsddPsm/mul-overflow");
    }

    // --- Administration ---
    function file(bytes32 what, uint256 data) external auth {
        if (what == "tin") tin = data;
        else if (what == "tout") tout = data;
        else if (what == "sellEnabled") {
            sellEnabled = data;
        }
        else if (what == "buyEnabled") {
            buyEnabled = data;
        }
        else revert("UsddPsm/file-unrecognized-param");

        emit File(what, data);
    }

    // --- Upgrade Path ---
    function hope(address usr) external auth {
        vat.hope(usr);
    }

    function nope(address usr) external auth {
        vat.nope(usr);
    }

    // --- Primary Functions ---

    // Sell gem for USDD
    function sellGem(address usr, uint256 gemAmt) external {
        require(sellEnabled == 1, "UsddPsm/sell-not-enabled");

        uint256 gemAmt18 = mul(gemAmt, to18ConversionFactor);
        uint256 fee = mul(gemAmt18, tin) / WAD;
        uint256 usddAmt = sub(gemAmt18, fee);

        // Transfer gem in and mint USDD
        gemJoin.join(address(this), gemAmt, msg.sender);
        vat.frob(ilk, address(this), address(this), address(this), int256(gemAmt18), int256(gemAmt18));

        // Send fee to system treasury
        vat.move(address(this), vow, mul(fee, RAY));

        // Send USDD to user
        usddJoin.exit(usr, usddAmt);

        emit SellGem(usr, gemAmt, fee);
    }

    // Buy gem with USDD
    function buyGem(address usr, uint256 gemAmt) external {
        require(buyEnabled == 1, "UsddPsm/buy-not-enabled");

        uint256 gemAmt18 = mul(gemAmt, to18ConversionFactor);
        uint256 fee = mul(gemAmt18, tout) / WAD;
        uint256 usddAmt = add(gemAmt18, fee);

        // Transfer USDD in
        require(usdd.transferFrom(msg.sender, address(this), usddAmt), "UsddPsm/failed-transfer");
        usddJoin.join(address(this), usddAmt);

        // Burn USDD and release gem
        vat.frob(ilk, address(this), address(this), address(this), - int256(gemAmt18), - int256(gemAmt18));
        gemJoin.exit(usr, gemAmt);

        // Send fee to system treasury
        vat.move(address(this), vow, mul(fee, RAY));

        emit BuyGem(usr, gemAmt, fee);
    }
}