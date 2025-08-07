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

import "forge-std/Test.sol";
import "ds-value/value.sol";
import "ds-token/token.sol";

import {Vat} from "usddv2/dss/vat.sol";
import {USDT} from "./token/USDT.sol";

import "../src/join-7-auth.sol";

interface Hevm {
    function warp(uint256) external;
    function store(address,bytes32,bytes32) external;
}

contract TestToken is USDT {

    constructor(uint8 decimals_) public USDT(0) {
        decimals = decimals_;
    }

}

contract User {

    AuthGemJoin7 public authGemJoin;
    TestToken     public usdt;

    constructor(AuthGemJoin7 gemJoin_) public {
        authGemJoin = gemJoin_;
        usdt = TestToken(address(authGemJoin.gem()));
    }

    function approveGems(address who, uint256 wad) public {
        usdt.approve(who, wad);
    }

    function try_joinGem(uint256 wad) public returns (bool ok) {
        usdt.approve(address(authGemJoin), wad);
        string memory sig = "join(address,uint256,address)";
        (ok,) = address(authGemJoin).call(abi.encodeWithSignature(sig, address(this), wad, address(this)));
    }

    function joinGem(uint256 wad) public {
        usdt.approve(address(authGemJoin), wad);
        authGemJoin.join(address(this), wad, address(this));
    }

    function exitGem(uint256 wad) public {
        usdt.approve(address(authGemJoin), wad);
        authGemJoin.exit(address(this), wad);
    }

    function setImplementation() public {
        authGemJoin.setImplementation(address(this), 1);
    }

}

contract AuthGemJoin7Test is Test {
    
    Hevm hevm;

    address me;

    Vat          vat;
    TestToken      usdt;
    AuthGemJoin7 authGemJoin;

    // CHEAT_CODE = 0x7109709ECfa91a80626fF3989D68f67F5b1DD12D
    bytes20 constant CHEAT_CODE =
        bytes20(uint160(uint256(keccak256('hevm cheat code'))));

    bytes32 constant ilk = "usdt";
    uint256 constant USDT_WAD = 10 ** 6;
    
    function setUp() public {
        hevm = Hevm(address(CHEAT_CODE));

        me = address(this);

        vat = new Vat();

        usdt = new TestToken(6);
        usdt.issue(1000 * 10**6);

        vat.init(ilk);

        authGemJoin = new AuthGemJoin7(address(vat), ilk, address(usdt));
        vat.rely(address(authGemJoin));
        usdt.approve(address(authGemJoin), uint256(-1));
    }

    function try_Join(uint256 wad) internal returns (bool ok) {
        string memory sig = "join(address,uint256,address)";
        (ok,) = address(authGemJoin).call(abi.encodeWithSignature(sig, me, wad, me));
    }
    
    function try_Exit(uint256 wad) internal returns (bool ok) {
        string memory sig = "exit(address,uint256)";
        (ok,) = address(authGemJoin).call(abi.encodeWithSignature(sig, me, wad));
    }

    function testRevert_tooManyDecimals() public {
        TestToken usdt19 = new TestToken(19);
        vm.expectRevert("AuthGemJoin7/decimals-18-or-higher");
        new AuthGemJoin7(address(vat), ilk, address(usdt19));
    }

    function test_setsCurrentImpl() public {
        assertEq(authGemJoin.implementations(address(0)), 1);
    }

    function test_allowsTogglingImpl() public {
        assertEq(authGemJoin.implementations(me), 0);

        authGemJoin.setImplementation(me, 1);
        assertEq(authGemJoin.implementations(me), 1);
        
        authGemJoin.setImplementation(me, 0);
        assertEq(authGemJoin.implementations(me), 0);
    }
    
    function testRevert_unauthorizedTogglingImpl() public {
        User user = new User(authGemJoin);
        vm.expectRevert();
        user.setImplementation();
    }

    function test_join() public {
        assertEq(usdt.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, me), 0);
        uint256 balBefore = usdt.balanceOf(me);

        authGemJoin.join(me, 1 * USDT_WAD, me);

        assertEq(usdt.balanceOf(address(authGemJoin)), 1 * USDT_WAD);
        assertEq(vat.gem(ilk, me), 1 ether);
        assertEq(usdt.balanceOf(me), balBefore - 1 * USDT_WAD);
    }

    function test_joinForOther() public {
        User user = new User(authGemJoin);
        usdt.transfer(address(user), 1 * USDT_WAD);
        user.approveGems(address(authGemJoin), 1 * USDT_WAD);
        
        assertEq(usdt.balanceOf(address(authGemJoin)), 0 * USDT_WAD);
        assertEq(vat.gem(ilk, address(user)), 0 ether);
        assertEq(usdt.balanceOf(address(user)), 1 * USDT_WAD);
        
        authGemJoin.join(address(user), 1 * USDT_WAD, address(user));

        assertEq(usdt.balanceOf(address(authGemJoin)), 1 * USDT_WAD);
        assertEq(vat.gem(ilk, address(user)), 1 ether);
        assertEq(usdt.balanceOf(address(user)), 0);
    }
    
    function test_joinNotAuthorized() public {
        User user = new User(authGemJoin);
        usdt.transfer(address(user), 1 * USDT_WAD);
        // user.approveGems(address(authGemJoin), 1 * USDT_WAD);
        
        assertTrue(!user.try_joinGem(1 * USDT_WAD));
    }

    function test_cannotJoinWithUnauthImpl() public {
        authGemJoin.setImplementation(address(0), 0);
        assertEq(authGemJoin.implementations(address(0)), 0);

        assertTrue(!try_Join(1 * USDT_WAD));
    }

    function test_cannotJoinAfterUpgrade() public {
        usdt.deprecate(address(1));

        assertTrue(!try_Join(1 * USDT_WAD));
    }

    function test_cannotJoinAfterCage() public {
        authGemJoin.cage();
        assertTrue(!try_Join(1 * USDT_WAD));
    }
    
    function test_exit() public {
        authGemJoin.join(me, 1 * USDT_WAD, me);

        assertEq(usdt.balanceOf(address(authGemJoin)), 1 * USDT_WAD);
        assertEq(vat.gem(ilk, me), 1 ether);
        uint256 balBefore = usdt.balanceOf(me);

        authGemJoin.exit(me, 1 * USDT_WAD);

        assertEq(usdt.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(usdt.balanceOf(me), balBefore + 1 * USDT_WAD);
    }
    
    function test_exitAllowedWithBalance() public {
        User user = new User(authGemJoin);
        usdt.transfer(address(user), 1 * USDT_WAD);
        user.approveGems(address(authGemJoin), 1 * USDT_WAD);
        authGemJoin.join(address(user), 1 * USDT_WAD, address(user));

        assertEq(usdt.balanceOf(address(authGemJoin)), 1 * USDT_WAD);
        assertEq(vat.gem(ilk, address(user)), 1 ether);
        assertEq(usdt.balanceOf(address(user)), 0);

        user.exitGem(1 * USDT_WAD);

        assertEq(usdt.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, address(user)), 0);
        assertEq(usdt.balanceOf(address(user)), 1 * USDT_WAD);
    }

    function test_cannotExitWithUnauthImpl() public {
        authGemJoin.join(me, 1 * USDT_WAD, me);

        authGemJoin.setImplementation(address(0), 0);
        assertEq(authGemJoin.implementations(address(0)), 0);

        assertTrue(!try_Exit(1 * USDT_WAD));
    }

    function test_canExitAfterCage() public {
        authGemJoin.join(me, 1 * USDT_WAD, me);

        assertEq(usdt.balanceOf(address(authGemJoin)), 1 * USDT_WAD);
        assertEq(vat.gem(ilk, me), 1 ether);
        uint256 balBefore = usdt.balanceOf(me);

        authGemJoin.cage();

        authGemJoin.exit(me, 1 * USDT_WAD);

        assertEq(usdt.balanceOf(address(authGemJoin)), 0);
        assertEq(vat.gem(ilk, me), 0);
        assertEq(usdt.balanceOf(me), balBefore + 1 * USDT_WAD);
    }
}
