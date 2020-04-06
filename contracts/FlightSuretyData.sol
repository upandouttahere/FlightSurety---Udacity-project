// pragma solidity ^0.4.25;
pragma solidity ^0.4.24;

import "../node_modules/openzeppelin-solidity/contracts/math/SafeMath.sol";

contract FlightSuretyData {
    using SafeMath for uint256;

    /********************************************************************************************/
    /*                                       DATA VARIABLES                                     */
    /********************************************************************************************/

    address private contractOwner;                                      // Account used to deploy contract
    bool private operational = true;                                    // Blocks all state changes throughout the contract if false

    uint private balance;                                               // define contract funds
    mapping(address => uint256) private credits;                        // credit balance of an address
    mapping(bytes32 => mapping(address => uint256)) private insurances; // individual insurance balance

    mapping(address => bool) private authorizedContracts;

    struct Flight {
        bool isRegistered;
        uint8 statusCode;
        uint256 departureTimestamp;
        uint256 updatedArrivalTimestamp;
        address airline;
    }
    mapping(bytes32 => Flight) private flights;

    struct Airline {
        bool isRegistered;
        uint256 invitations;
        mapping(address => bool) hasInvited;
        uint256 deposit;
    }
    mapping(address => Airline) private airlines;
    
    uint256 private airlineCount;

    /********************************************************************************************/
    /*                                       EVENT DEFINITIONS                                  */
    /********************************************************************************************/

    // The deploying account becomes contractOwner
    // First airline gets registered and funded automatically
    constructor() public payable {
        contractOwner = msg.sender;
        airlineCount = 1;
        airlines[contractOwner].isRegistered = true;
        fund(msg.value);
    }

    /********************************************************************************************/
    /*                                       FUNCTION MODIFIERS                                 */
    /********************************************************************************************/

    // Modifier that requires the "operational" boolean variable to be "true"
    modifier requireIsOperational() {
        require(operational, "Contract is currently not operational");
        _;
    }

    // Modifier that requires the "ContractOwner" account to be the function caller
    modifier requireContractOwner() {
        require(msg.sender == contractOwner, "Caller is not contract owner");
        _;
    }

    // Added modifier that requires airline to be authorized (registered and funded)
    modifier isCallerAuthorized() {
        require(authorizedContracts[msg.sender], 'Caller is not authorized');
        _;
    }

    /********************************************************************************************/
    /*                                       UTILITY FUNCTIONS                                  */
    /********************************************************************************************/

    // Get operating status of contract and return A bool that is the current operating status 
    function isOperational() public view returns(bool) {
        return operational;
    }

    // Sets contract operations on/off when operational mode is disabled, all write transactions except for this one will fail  
    function setOperatingStatus(bool mode) external requireContractOwner {
        operational = mode;
    }

    /********************************************************************************************/
    /*                                     SMART CONTRACT FUNCTIONS                             */
    /********************************************************************************************/

    // Add an airline to the registration queue
    // Can only be called from FlightSuretyApp contract

    function registerAirline(address airline, address endorsingAirline) external isCallerAuthorized() returns(bool success, uint256 votes) {
        // Only existing airline may register a new airline until there are at least four airlines registered
        if (airlineCount < 4) {
            airlines[endorsingAirline].hasInvited[airline] = true;
            airlineCount++;
            airlines[airline].isRegistered = true;
            airlines[airline].invitations = 1;
            return (true, 1);
        } else {
            // Registration of fifth and subsequent airlines requires multi-party consensus of 50% of registered airlines
            if (airlines[airline].invitations.mul(2) >= airlineCount) {
                airlineCount++;
                airlines[airline].isRegistered = true;
                airlines[airline].invitations += 1;
                return (true, airlines[airline].invitations);
            } else {
                airlines[airline].invitations += 1;
                return (false, airlines[airline].invitations);
            }
        }
    }

    // Register flight
    function registerFlight(address airline, string flight, uint256 departureTimestamp
        ) external isCallerAuthorized() returns(bool) {
        require(airlines[airline].isRegistered, "Airline not found");
        bytes32 flightKey = getFlightKey(airline, flight, departureTimestamp);
        flights[flightKey].isRegistered = true;
        flights[flightKey].departureTimestamp = departureTimestamp;
        return true;
    }

    // Set flight status code
    function setFlightStatus(bytes32 flightKey, uint8 statusCode) external isCallerAuthorized() returns(uint8) {
        flights[flightKey].statusCode = statusCode;
        return statusCode;
    }

    // Buy insurance for a flight
    function buy(address airline, string flight, uint256 timestamp) external payable {
        require(msg.value > 0 && msg.value <= 1 ether, 'Pay up to 1 Ether');
        bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        insurances[flightKey][msg.sender] = msg.value;
    }

    // Credits payouts to insurees
    function creditInsuree(address passenger, address airline, string flight, uint256 departureTimestamp
    ) external isCallerAuthorized() returns(bool) {
        bytes32 flightKey = getFlightKey(airline, flight, departureTimestamp);
        require(flights[flightKey].statusCode == 20, 'Airline has caused no delay');
        uint256 total = insurances[flightKey][passenger];
        require(total > 0, "No insurance purchased");
        // If flight is delayed due to airline fault, passenger receives credit of 1.5X the amount they paid
        uint256 payout = insurances[flightKey][passenger].mul(3).div(2);
        uint256 credit = credits[passenger];
        insurances[flightKey][passenger] = insurances[flightKey][passenger].sub(total);
        credits[passenger] = credit.add(payout);
        require(credit.add(payout) > 0, 'No credits to pay out');
    }

    // Transfers eligible payout funds to insuree
    function pay() external {
        uint256 credit = credits[msg.sender];
        credits[msg.sender] = 0;
        msg.sender.transfer(credit);
    }

    // Initial funding for the insurance. Unless there are too many delayed flights
    // resulting in insurance payouts, the contract should be self-sustaining
    function fund(uint256 amount) internal {
        balance = balance.add(amount);
    }

    function getFlightKey(address airline, string memory flight, uint256 timestamp) pure internal returns (bytes32) {
        return keccak256(abi.encodePacked(airline, flight, timestamp));
    }

    // function isFlight(address airline, string flight, uint256 timestamp) external view returns(bool) {
        // bytes32 flightKey = getFlightKey(airline, flight, timestamp);
        // return flights[flightKey].isRegistered;
    // }

    // function isAirline(address candidateAirline) external view returns(bool) {
        // Airline memory airline = airlines[candidateAirline];
        // return airline.isRegistered && (airline.deposit >= 10 ether);
    // }

    // function isRegistered(address airline) public view returns(bool) {
        // return airlines[airline].isRegistered;
    // }

    // function depositAirlineFee(address airline) external payable requireIsOperational() isCallerAuthorized() returns(bool) {
        // require(airlines[airline].isRegistered, 'Not a registered airline');
        // airlines[airline].deposit += msg.value;
        // return true;
    // }

    // Fallback function for funding smart contract
    function()external payable {
        fund(msg.value);
    }

}
