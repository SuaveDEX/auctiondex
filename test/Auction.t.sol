// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "suave-std/Test.sol";
import "suave-std/suavelib/Suave.sol";
import {Auction} from "../src/Auction.sol";

contract TestForge is Test, SuaveEnabled {
    function testCancelOffer() public {
        Auction auction = new Auction();

        bytes memory o1 = auction.placeOffer("bid", "oid1", 50, 100);
        address(auction).call(o1);
        bytes memory o2 = auction.placeOffer("ask", "oid4", 50, 50);
        address(auction).call(o2);
        bytes memory o3 = auction.cancelOffer("oid1");
        address(auction).call(o3);

        // Shouldn't match!
        bytes memory s = auction.settleAuction();
        address(auction).call(s);
    }

    function testPlaceOffer() public {
        Auction auction = new Auction();

        bytes memory o1 = auction.placeOffer("bid", "oid1", 50, 100);
        address(auction).call(o1);
        bytes memory o2 = auction.placeOffer("bid", "oid2", 55, 200);
        address(auction).call(o2);
        bytes memory o3 = auction.placeOffer("bid", "oid3", 25, 100);
        address(auction).call(o3);

        bytes memory o4 = auction.placeOffer("ask", "oid4", 50, 50);
        address(auction).call(o4);
        bytes memory o5 = auction.placeOffer("ask", "oid5", 60, 50);
        address(auction).call(o5);
        bytes memory o6 = auction.placeOffer("ask", "oid5", 70, 250);
        address(auction).call(o6);

        // should match the 55 buy with the 50 sell, rounded midpoint is 52
        bytes memory s = auction.settleAuction();
        address(auction).call(s);

        uint64 blockHeight = auction.blockHeight();
        assertEq(blockHeight, 1);
    }
}
