// SPDX-License-Identifier: MIT

/**
 constructor()
 receive func
 fallback func
 external
 public
 internal
 private
 view and pure funcs
 */

import {VRFCoordinatorV2Interface} from "@chainlink/contracts/src/v0.8/interfaces/VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "@chainlink/contracts/src/v0.8/VRFConsumerBaseV2.sol";
import {console} from "forge-std/console.sol"; // make sure to remove this because it will absolutely cost gas;

pragma solidity ^0.8.19;

event EnteredRaffle(address indexed player);
event PickedWinner(address indexed winner);

error Raffle__NotEnoughEthSent();
error Raffle__TransferFailed();
error Raffle__RaffleNotOpen();
error Raffle__UpkeepNotNeeded();

// error Raffle__NotEnoughEthSent();
// error Raffle__TransferFailed();
// error Raffle__RaffleNotOpen();
// error Raffle__UpkeepNotNeeded();

/**
 * @title A sample Raffle Contract
 * @author Amin Sammara
 * @notice This contract is for creating a sample raffle
 * @dev Implements Chainlink VRFv2
 */
contract Raffle is VRFConsumerBaseV2 {

    /** Type Declarations */
    // In solidity enum types are explicitly convertible to integeres but *NOT* implicitly. 
    // Clarifying Code: Enums help to clarify what values are acceptable in your code, making it more readable and maintainable.
    // Gas Savings: Enums are more gas efficient than strings

    event RequestedRaffleWinner(uint256 indexed requestId);
    
    enum RaffleState {
        OPEN, // 0
        CALCULATING // 1
        // 2
        // 3
    }


    /** State Variables */
    uint16 private constant REQUEST_CONFIRMATIONS = 3;
    uint32 private constant NUM_WORDS = 1;

    uint32 private immutable i_callbackGasLimit;
    uint64 private immutable i_subscriptionId;
    uint256 private immutable i_entranceFee; 
    // @dev: duration of the lottery in seconds
    uint256 private immutable i_interval;
    VRFCoordinatorV2Interface private immutable i_vfCoordinator;
    bytes32 private immutable i_gasLane;
    

    address payable[] private s_players;
    uint256 private s_lastTimeStamp;
    address private s_recentWinner;
    RaffleState private s_raffleState;


    // We're doing the VRFConsumerBaseV2() thing after constructor because that contract (which we inherited) has it's own constructor which needs variables to be passed into this. 
    constructor (
        uint256 entranceFee,
        uint256 interval,
        address vfCoordinator,
        bytes32 gasLane,
        uint64 subscriptionId,
        uint32 callbackGasLimit
        ) VRFConsumerBaseV2(vfCoordinator) {
        i_entranceFee = entranceFee;
        i_interval = interval;
        s_lastTimeStamp = block.timestamp;
        i_vfCoordinator = VRFCoordinatorV2Interface(vfCoordinator);
        i_gasLane = gasLane; // this is chain-dependent
        i_subscriptionId = subscriptionId;
        i_callbackGasLimit = callbackGasLimit;

        s_raffleState = RaffleState.OPEN;
    }

    receive() external payable {

    }


// external is more gas efficient than public. If you KNOW that your contract won't call it, drop 'public' in favor of 'external'
    function enterRaffle() payable external {
        // conditionals + custom error is more gas efficient than a require statement
        // require(msg.value >= i_entranceFee, "Not Enough ETH");
        if (msg.value < i_entranceFee) revert Raffle__NotEnoughEthSent(); //same line so did not put the braces
        if (s_raffleState != RaffleState.OPEN) revert Raffle__RaffleNotOpen();
        s_players.push(payable(msg.sender));
        // as a rule of thumb, whenever we make a storage update we should emit an event
        emit EnteredRaffle(msg.sender);
    }

    // 1. Pick a random number
    // 2. Use the random number to pick a player
    // 3. Be automatically called

    function checkUpkeep(bytes memory /*checkData*/) public view returns (bool upkeepNeeded, bytes memory /*performData*/) {
        bool timePassed = (block.timestamp - s_lastTimeStamp >= i_interval);
        bool raffleOpen = RaffleState.OPEN == s_raffleState;
        bool hasPlayers = s_players.length > 0;
        bool hasEth = address(this).balance > 0;

        upkeepNeeded = (timePassed && raffleOpen && hasPlayers && hasEth);
        return (upkeepNeeded, "0x0"); // passed in the empty bytes object "0x0" to conform with func definition. 
    }

    function performUpkeep(bytes calldata /*performData*/) external  {
        (bool upkeepNeeded,) = checkUpkeep("");
        if (!upkeepNeeded) {
            revert Raffle__UpkeepNotNeeded();
            
        } else {
        s_raffleState = RaffleState.CALCULATING;
        // Get a random number.
        // Chainlink VRF is a two tx. 1. Request RNG (we send this) 2. Get the random number (chainlink node sends this)
        uint256 requestId = i_vfCoordinator.requestRandomWords(
            i_gasLane, // gas lane
            i_subscriptionId, // ID funded with link
            REQUEST_CONFIRMATIONS, // number of blockconfirmations before random number is good
            i_callbackGasLimit, // to make sure we don't overspenc on the callback function (chainlink Nodes actually sending us the random number)
            NUM_WORDS
        );
        emit RequestedRaffleWinner(requestId);
        }
        
    }

    // CEI: Checks, Effects, Interactions design partners
    function fulfillRandomWords(
        uint256 /*requestId*/,
        uint256[] memory randomWords
    ) internal override {
        // checks - more gas efficient to do the checks first
        // require, (if -> errors).
        // Effects (our own contract)
        uint256 indexOfWinner = randomWords[0] % s_players.length;
        address payable winner = s_players[indexOfWinner];
        s_recentWinner = winner;
        s_raffleState = RaffleState.OPEN;

        // resetting the s_players array to start over again
        s_players = new address payable[](0); // The (0) means start at size 0
        s_lastTimeStamp = block.timestamp;
        emit PickedWinner(winner);
        // Interactions (other contracts)
        (bool success, ) = winner.call{value: address(this).balance}(""); // blank bytes for the object
        if (!success) revert Raffle__TransferFailed();

    }

    /** Getter Functions */

    function getEntranceFee() external view returns (uint256) {
        return i_entranceFee;
    }

    function getRaffleState() external view returns (RaffleState) {
        return s_raffleState;
    }

    function getPlayer(uint256 indexOfPlayer) external view returns (address) {
        return s_players[indexOfPlayer];
    }

    function getRecentWinner() external view returns (address) {
        return s_recentWinner;
    }

    function getLengthOfPlayers() external view returns (uint256) {
        return s_players.length;
    }

    function getLastTimeStamp() external view returns (uint256) {
        return s_lastTimeStamp;
    }
}

// ([0xcd6e45c8998311cab7e9d4385596cac867e20a0587194b954fa3a731c93ce78b, 0x0000000000000000000000000000000000000000000000000000000000000001], 0x, 0xDB8cFf278adCCF9E9b5da745B44E754fC4EE3C76)]