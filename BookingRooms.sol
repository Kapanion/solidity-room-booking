// SPDX-License-Identifier: GPL-3.0

pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

contract Rooms is ReentrancyGuard{
    struct Room{
        uint64 id;
        uint dailyPrice;
        address payable owner;
        string description;
        // Also some other info if necessary
    }

    mapping(uint64 => bool) public roomIsActive;
    mapping(uint64 => bool) public roomIsBooked;
    mapping(uint64 => address) public roomCurrentGuest;
    Room[] public rooms;
    uint64 private numOfRooms;

    address private constant ADDR_NONE = address(0);

    event NewRoomCreated(address user, uint time, uint64 roomId);
    event RoomDailyPriceUpdated(address user, uint time, uint price);

    event MoneyReceived(address sender, uint moneyAmount);
    event Fallback(address sender, uint moneyAmount);

    modifier roomValid(uint64 _roomId){
        require(_roomId >= 0 && _roomId < numOfRooms, "Invalid room id.");
        _;
    }

    modifier roomActive(uint64 _roomId){
        require(roomIsActive[_roomId], "Room inactive.");
        _;
    }

    modifier roomAvailable(uint64 _roomId){
        require(!roomIsBooked[_roomId], "Room is already booked.");
        _;
    }

    modifier onlyOwner(uint64 _roomId){
        require(rooms[_roomId].owner == msg.sender, "Only the owner can access this.");
        _;
    }

    constructor(){
        numOfRooms = 0;
    }

    receive() external payable{
        emit MoneyReceived(msg.sender, msg.value);
    }

    fallback() external payable{
        emit Fallback(msg.sender, msg.value);
    }

    function addRoom(uint _dailyPrice, string memory _description) public returns(Room memory){
        uint64 newRoomId = numOfRooms;
        numOfRooms++;

        Room memory newRoom = Room(newRoomId, _dailyPrice, payable(msg.sender), _description);
        rooms.push(newRoom);
        roomIsActive[newRoomId] = true;
        roomIsBooked[newRoomId] = false;

        emit NewRoomCreated(msg.sender, block.timestamp, newRoomId);
        
        return newRoom;
    }

    function getRoomData(uint64 _roomId) public view roomValid(_roomId) returns(
        uint64 _id,
        address payable _owner,
        uint _dailyPrice,
        string memory _description,
        bool _availableForBooking
    ){
        Room memory room = rooms[_roomId];
        _id = room.id;
        _owner = room.owner;
        _dailyPrice = room.dailyPrice;
        _description = room.description;
        _availableForBooking = availableForBooking(_roomId);
    }

    function availableForBooking(uint64 _roomId) public view roomValid(_roomId) returns(bool){
        return roomIsActive[_roomId] && !roomIsBooked[_roomId];
    }

    function setRoomDailyPrice(uint64 _roomId, uint _newPrice) public roomValid(_roomId) onlyOwner(_roomId){
        rooms[_roomId].dailyPrice = _newPrice;
        emit RoomDailyPriceUpdated(msg.sender, block.timestamp, _newPrice);
    }

    function setRoomActivity(uint64 _roomId, bool _activity) public roomValid(_roomId) onlyOwner(_roomId){
        if ( !_activity ){
            require(!roomIsBooked[_roomId], "Room is already booked. Use the refund function instead.");
        }
        roomIsActive[_roomId] = _activity;
    }

    function setBooked(uint64 _roomId, bool _booked) internal roomValid(_roomId) {
        roomIsBooked[_roomId] = _booked;   
    }

    function freeRoom(uint64 _roomId) internal{
        setBooked(_roomId, false);
    }
}

contract Bookings is Rooms{
    struct Booking{
        uint64 id;
        uint64 roomId;
        uint date;
        uint moneyPaid;
        address payable guest;
    }

    address owner;
    Booking[] public bookings;
    mapping (uint64 => Booking) roomCurrentBooking;
    uint64 private numOfBookings;

    event NewBookingCreated(address user, uint time, uint64 bookingId);

    modifier onlyGuest(uint64 _roomId){
        require(roomIsBooked[_roomId] && msg.sender == roomCurrentBooking[_roomId].guest,
            "You don't have permission to access this.");
        _;
    }

    constructor(){
        numOfBookings = 0;
        owner = msg.sender;
    }

    function bookingPrice(uint64 _roomId, uint _days) public view roomValid(_roomId) returns(uint){
        return rooms[_roomId].dailyPrice * _days;
    }

    function bookRoom(uint64 _roomId, uint _days) public payable
    roomValid(_roomId)
    roomActive(_roomId)
    roomAvailable(_roomId)
    nonReentrant {
        Room storage room = rooms[_roomId];
        uint price = room.dailyPrice * _days;
        require(_days != 0, "Number of days must be more than 0.");
        require(msg.value == price, "Send the exact required amount. The bookingPrice() function might be helpful");
        
        uint64 newBookingId = numOfBookings;
        numOfBookings++;
        Booking memory newBooking = Booking(newBookingId, _roomId, block.timestamp, price, payable(msg.sender));
        bookings.push(newBooking);
        roomCurrentBooking[_roomId] = newBooking;
        setBooked(_roomId, true);

        emit NewBookingCreated(msg.sender, block.timestamp, newBookingId);

    }

    function refund(uint64 _roomId) public payable
    roomValid(_roomId)
    roomActive(_roomId)
    onlyOwner(_roomId)
    nonReentrant {
        require(roomIsBooked[_roomId], "Room is not booked; no need for a refund.");
        freeRoom(_roomId);
        uint moneyToReturn = roomCurrentBooking[_roomId].moneyPaid;
        roomCurrentBooking[_roomId].guest.transfer(moneyToReturn);
    }

    function checkout(uint64 _roomId) public payable
    roomValid(_roomId)
    roomActive(_roomId)
    onlyGuest(_roomId)
    nonReentrant {
        freeRoom(_roomId);
        rooms[_roomId].owner.transfer(roomCurrentBooking[_roomId].moneyPaid);
    }

    function cancelBooking(uint64 _roomId) public payable
    roomValid(_roomId)
    roomActive(_roomId)
    onlyGuest(_roomId)
    nonReentrant {
        freeRoom(_roomId);
        uint moneyToReturn = roomCurrentBooking[_roomId].moneyPaid / 2; // Can be any other formula
        payable(msg.sender).send(moneyToReturn);
        rooms[_roomId].owner.send(roomCurrentBooking[_roomId].moneyPaid - moneyToReturn);
        // TODO: handle failure conditions of send function.
    }
    
    function projectSubmitted(string memory _codeHash, string memory _authorName, address _sendHashTo) external{
        require(msg.sender == owner, "nope");
        _sendHashTo.call(abi.encodeWithSignature("recieveProjectData(string,string)", _codeHash, _authorName));
    }
}