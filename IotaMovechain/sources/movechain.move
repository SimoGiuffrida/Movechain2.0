module 0x0::SupplyChain {
 
    use iota::event;
    use iota::tx_context;
    use iota::object;
    use iota::transfer;
    use std::vector;
 
    /// Definition of states as constants
    const STATE_OWNED: u8 = 1;
    const STATE_SHARED: u8 = 2;
 
    /// Error codes
    const E_CALLER_NOT_BUYER: u64 = 1;
    const E_DISTRIBUTOR_ALREADY_ASSIGNED: u64 = 2;
    const E_BUYER_ALREADY_ASSIGNED: u64 = 3;
    const E_CALLER_NOT_OWNER: u64 = 4;
    const E_INVALID_PARTICIPANT: u64 = 5;
    const E_INVALID_SENSOR_DATA_RANGE: u64 = 6;
    const E_INVALID_ADDRESS: u64 = 7;
    const E_PRODUCT_NOT_IN_SHARED_STATE: u64 = 8;
    const E_INVALID_STATE_TRANSITION: u64 = 9;
    const E_BUYER_NOT_ASSIGNED: u64 = 10;
    const E_DISTRIBUTOR_NOT_ASSIGNED: u64 = 11;
 
    /// Structure representing the product in the supply chain
    public struct Product has key, store {
        id: UID,               // Unique product identifier
        owner: address,        // Current owner's address
        state: u8,             // Product state (STATE_OWNED or STATE_SHARED)
        producer: address,     // Producer's address
        distributor: address,  // Distributor's address (optional)
        buyer: address,        // Buyer's address (optional)
        sensors: vector<Sensor>, // Multiple sensors per product
    }

    /// Structure representing a sensor
    public struct Sensor has key, store {
        id: UID,
        sensor_data: u64,
        min_sensor_data: u64,
        max_sensor_data: u64,
        validity: bool,
    }
 
    /// Event for state change
    public struct StateChangedEvent has store, copy, drop {
        product_address: address,
        new_state: u8,
    }
 
    /// Function to create a new product (executed by the producer)
        /// Function to create a new product (executed by the producer)
    public fun create_product(
        ctx: &mut TxContext,
    ) { 
        let producer_address = tx_context::sender(ctx);

        let product = Product {
            id: object::new(ctx),
            owner: producer_address,
            state: STATE_OWNED,
            producer: producer_address,
            distributor: @0x0,
            buyer: @0x0,
            sensors: vector::empty<Sensor>(),
        };

        event::emit<StateChangedEvent>(
            StateChangedEvent {
                product_address: object::uid_to_address(&product.id),
                new_state: STATE_OWNED,
            }
        );

        transfer::public_transfer(product, producer_address);
    }

    /// Function to assign the distributor (executed by the producer)
    public fun assign_distributor(
        product: &mut Product,
        distributor: address,
        ctx: &mut TxContext
    ) {
        let producer_address = tx_context::sender(ctx);

        assert!(producer_address == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.distributor == @0x0, E_DISTRIBUTOR_ALREADY_ASSIGNED);

        product.distributor = distributor;
    }
 
    /// Function to assign the buyer (executed by the producer)
    public fun assign_buyer(
        product: &mut Product,
        buyer: address,
        ctx: &mut TxContext
    ) {
        let producer_address = tx_context::sender(ctx);

        assert!(producer_address == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.buyer == @0x0, E_BUYER_ALREADY_ASSIGNED);

        product.buyer = buyer;
    }
 
    /// Function to change the product from Owned to Shared
    public fun change_to_shared(
        product: &mut Product,
        ctx: &mut TxContext
    ) {
        let caller_address = tx_context::sender(ctx);

        assert!(caller_address == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.distributor != @0x0, E_DISTRIBUTOR_NOT_ASSIGNED);
        assert!(product.buyer != @0x0, E_BUYER_NOT_ASSIGNED);

        product.state = STATE_SHARED;

        event::emit<StateChangedEvent>(
            StateChangedEvent {
                product_address: object::uid_to_address(&product.id),
                new_state: STATE_SHARED,
            }
        );
    }
 
    /// Function to confirm arrival and transfer ownership to the buyer
    public fun confirm_delivery(
        product: &mut Product,
        ctx: &mut TxContext
    ) {
        let buyer_address = tx_context::sender(ctx);

        assert!(buyer_address == product.buyer, E_CALLER_NOT_BUYER);
        assert!(product.state == STATE_SHARED, E_PRODUCT_NOT_IN_SHARED_STATE);

        product.state = STATE_OWNED;
        product.owner = buyer_address;
        product.distributor = @0x0;
        product.buyer = @0x0;

        event::emit<StateChangedEvent>(
            StateChangedEvent {
                product_address: object::uid_to_address(&product.id),
                new_state: STATE_OWNED,
            }
        );
    }
        /// Function to add a sensor to a product
    public fun add_integer_sensor(
        product: &mut Product,
        min_sensor_data: u64,
        max_sensor_data: u64,
        ctx: &mut TxContext
    ) {
        assert!(min_sensor_data <= max_sensor_data, E_INVALID_SENSOR_DATA_RANGE);

        let sensor = Sensor {
            id: object::new(ctx),
            sensor_data: 0,
            min_sensor_data: min_sensor_data,
            max_sensor_data: max_sensor_data,
            validity: true,
        };

        vector::push_back(&mut product.sensors, sensor);
    }

    /// Function to update a sensor's data
    public fun update_sensor_data(
        product: &mut Product,
        sensor_id: address,
        sensor_data: u64,
        ctx: &mut TxContext
    ) {
        let participant_address = tx_context::sender(ctx);
        assert!(product.state == STATE_SHARED, E_PRODUCT_NOT_IN_SHARED_STATE);

        assert!(
            participant_address == product.producer ||
            participant_address == product.distributor ||
            participant_address == product.buyer,
            E_INVALID_ADDRESS
        );

        let mut i = 0;  // Changed: Added 'mut' keyword
        let len = vector::length(&product.sensors);
        while (i < len) {
            let sensor = vector::borrow_mut(&mut product.sensors, i);
            if (object::uid_to_address(&sensor.id) == sensor_id) {
                sensor.sensor_data = sensor_data;
                sensor.validity = !(sensor_data < sensor.min_sensor_data || sensor_data > sensor.max_sensor_data);
                break
            };
            i = i + 1;
        }
    }
}
