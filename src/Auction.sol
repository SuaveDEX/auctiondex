// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;
import "suave-std/suavelib/Suave.sol";
import "forge-std/console.sol";

contract Auction {
    uint64 public blockHeight = 0;
    mapping(string => bool) private cancels;
    address[] addressList;

    event MatchEvent(uint price, uint amount);
    event OfferEvent(string);
    event CancelEvent(string);

    // Should this be an intent instead?
    // extract price and amounts from the intent?
    // If not - how do we store intent?
    // Add a timeout value?
    // Add order types?
    struct Order {
        uint price;
        uint amount;
        string clientId;
    }
    struct Cancel {
        string clientId;
    }

    constructor() {
        addressList = new address[](2);
        addressList[0] = address(this);
        addressList[1] = 0xC8df3686b4Afb2BB53e60EAe97EF043FE03Fb829;
    }

    function emitOffer(string calldata clientId) public payable {
        emit OfferEvent(clientId);
    }

    function emitCancel(string calldata clientId) public payable {
        emit CancelEvent(clientId);
    }

    function auctionSettlement(uint price, uint amount) public payable {
        blockHeight += 1;
        emit MatchEvent(price, amount);
    }

    // function nullCallback() public payable {}

    function placeOffer(
        string calldata offerType,
        string calldata clientId,
        uint price,
        uint amount
    ) external returns (bytes memory) {
        Order memory order = Order(price, amount, clientId);
        bytes memory value = abi.encode(order);

        Suave.DataRecord memory record = Suave.newDataRecord(
            blockHeight,
            addressList,
            addressList,
            offerType // "namespace"
        );

        Suave.confidentialStore(record.id, "suavedex:v0:orders", value);

        return abi.encodeWithSelector(this.emitOffer.selector, clientId);
    }

    function cancelOffer(
        string calldata clientId
    ) external returns (bytes memory) {
        Cancel memory cancel = Cancel(clientId);
        bytes memory value = abi.encode(cancel);

        Suave.DataRecord memory record = Suave.newDataRecord(
            blockHeight,
            addressList,
            addressList,
            "cancel" // "namespace"
        );

        Suave.confidentialStore(record.id, "suavedex:v0:cancels", value);
        return abi.encodeWithSelector(this.emitCancel.selector, clientId);
    }

    function settleAuction() external returns (bytes memory) {
        // TODO - needs to run on 3 second intervals
        // Enforce via timestamps initally?

        Suave.DataRecord[] memory bidRecords = Suave.fetchDataRecords(
            blockHeight,
            "bid"
        );
        Suave.DataRecord[] memory askRecords = Suave.fetchDataRecords(
            blockHeight,
            "ask"
        );
        Suave.DataRecord[] memory cancelRecords = Suave.fetchDataRecords(
            blockHeight,
            "cancel"
        );

        Order[] memory bids = new Order[](bidRecords.length);
        Order[] memory asks = new Order[](askRecords.length);

        for (uint256 i = 0; i < bidRecords.length; i++) {
            bytes memory value = Suave.confidentialRetrieve(
                bidRecords[i].id,
                "suavedex:v0:orders"
            );
            Order memory bid = abi.decode(value, (Order));
            bids[i] = bid;
        }

        for (uint256 i = 0; i < askRecords.length; i++) {
            bytes memory value = Suave.confidentialRetrieve(
                askRecords[i].id,
                "suavedex:v0:orders"
            );
            Order memory bid = abi.decode(value, (Order));
            asks[i] = bid;
        }

        for (uint256 i = 0; i < cancelRecords.length; i++) {
            bytes memory value = Suave.confidentialRetrieve(
                cancelRecords[i].id,
                "suavedex:v0:cancels"
            );
            Cancel memory cancel = abi.decode(value, (Cancel));
            cancels[cancel.clientId] = true;
        }

        quickSort(bids, 0, bids.length - 1);
        quickSort(asks, 0, asks.length - 1);

        // matching logic
        uint matchedVol = 0;
        uint volPrice = 0;
        uint bidI = bids.length - 1;
        uint askI = 0;
        while (bidI >= 0 && askI < asks.length) {
            // skip any cancelled orders
            string memory clientIdAsk = asks[askI].clientId;
            string memory clientIdBid = bids[bidI].clientId;
            if (cancels[clientIdAsk]) {
                askI++;
                continue;
            }
            if (cancels[clientIdBid]) {
                bidI--;
                continue;
            }

            if (asks[askI].price <= bids[bidI].price) {
                // TODO - how should we decide on price?
                uint midPrice = (asks[askI].price + bids[bidI].price) / 2;
                // match up lower of the amounts
                if (asks[askI].amount < bids[bidI].amount) {
                    matchedVol += asks[askI].amount;
                    volPrice += midPrice * asks[askI].amount;
                    bids[bidI].amount -= asks[askI].amount;
                    askI++;
                } else if (bids[bidI].amount < asks[askI].amount) {
                    matchedVol += bids[bidI].amount;
                    volPrice += midPrice * bids[bidI].amount;
                    asks[askI].amount -= bids[bidI].amount;
                    bidI--;
                }
                // Same vol...
                else {
                    matchedVol += bids[bidI].amount;
                    volPrice += midPrice * bids[bidI].amount;
                    bidI--;
                    askI++;
                }
            } else {
                break;
            }
        }

        // Think this would revert in reality but in test it doesn't?
        // Suave.DataId crashId = Suave.DataId.wrap(
        //     0x61626300000000000000000000000000
        // );
        // Suave.confidentialStore(crashId, "suavedex:v0:orders", bytes("abcd"));

        // And now write the unmatched bids+asks back to the datastore to blockHeight+1
        // ISSUE - is it possible for someone to call placeOffer while this is running?
        // we'd effectively delete that offer?
        for (uint256 i = 0; i <= bidI; i++) {
            if (cancels[bids[i].clientId]) {
                continue;
            }

            Suave.DataRecord memory record = Suave.newDataRecord(
                blockHeight + 1,
                addressList,
                addressList,
                "bid"
            );
            bytes memory value = abi.encode(bids[i]);
            Suave.confidentialStore(record.id, "suavedex:v0:orders", value);
        }
        for (uint256 i = askI; i < askRecords.length; i++) {
            if (cancels[asks[i].clientId]) {
                askI++;
            }

            Suave.DataRecord memory record = Suave.newDataRecord(
                blockHeight + 1,
                addressList,
                addressList,
                "ask"
            );

            bytes memory value = abi.encode(asks[i]);
            Suave.confidentialStore(record.id, "suavedex:v0:orders", value);
        }

        uint matchedPrice = volPrice / matchedVol;
        console.log("MATCHED", matchedVol, "AT", matchedPrice);

        // TODO - create, sign, send tx
        // function signEthTransaction(bytes memory txn, string memory chainId, string memory signingKey) view returns (bytes memory)
        // function submitBundleJsonRPC(string memory url, string memory method, bytes memory params) internal view returns (bytes memory)
        // Suave.submitBundleJsonRPC("https://relay-goerli.flashbots.net", "eth_sendBundle", bundleData);

        return
            abi.encodeWithSelector(
                this.auctionSettlement.selector,
                matchedVol,
                matchedPrice
            );
    }

    // Slightly modified from https://gist.github.com/subhodi/b3b86cc13ad2636420963e692a4d896f
    function quickSort(Order[] memory arr, uint left, uint right) internal {
        // 'left' and 'right' are indices
        uint i = left;
        uint j = right;
        if (i == j) return;

        uint pivot = arr[left + (right - left) / 2].price;

        while (i <= j) {
            while (arr[i].price < pivot) i++;
            while (pivot < arr[j].price) j--;
            if (i <= j) {
                (arr[i], arr[j]) = (arr[j], arr[i]);
                i++;
                j--;
            }
        }
        if (left < j) quickSort(arr, left, j);
        if (i < right) quickSort(arr, i, right);
    }
}
