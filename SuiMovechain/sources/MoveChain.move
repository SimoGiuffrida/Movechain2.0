module movechain::SupplyChain {

    use sui::object::{Self, UID, new};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer;
    use sui::dynamic_field;

    // --- Error Codes ---
    const E_CALLER_NOT_BUYER: u64 = 1;
    const E_DISTRIBUTOR_ALREADY_ASSIGNED: u64 = 2;
    const E_BUYER_ALREADY_ASSIGNED: u64 = 3;
    const E_CALLER_NOT_OWNER: u64 = 4;
    const E_INVALID_PARTICIPANT: u64 = 5;
    const E_INVALID_SENSOR_DATA_RANGE: u64 = 6;
    const E_BUYER_NOT_ASSIGNED: u64 = 10;
    const E_DISTRIBUTOR_NOT_ASSIGNED: u64 = 11;
    const E_NOT_SHARED: u64 = 12; // Added for consistency, even if not used

    // --- Structs ---

    public struct Sensor has store, drop {
        id: u64,
        sensor_data: u64,
        min_sensor_data: u64,
        max_sensor_data: u64,
        validity: bool,
    }

    public struct Product has key, store {
        id: UID,
        owner: address,
        producer: address,
        distributor: address,
        buyer: address,
    }

    // MODIFICATION: Added the "Wrapper" struct for sharing
    public struct SharedProduct has key {
        id: UID,
        // The Product object is now contained here
        product: Product,
    }

    // --- Entry Functions (Owned Phase) ---

    public entry fun create_product(ctx: &mut TxContext) {
        let producer_address = sender(ctx);
        let mut product = Product {
            id: new(ctx),
            owner: producer_address,
            producer: producer_address,
            distributor: @0x0,
            buyer: @0x0,
        };
        // The counter remains a dynamic field bound to the product ID
        dynamic_field::add(&mut product.id, 0u64, 0u64);
        transfer::transfer(product, producer_address);
    }

    public entry fun add_sensor(
        product: &mut Product,
        min_sensor_data: u64,
        max_sensor_data: u64,
        ctx: &mut TxContext
    ) {
        assert!(sender(ctx) == product.owner, E_CALLER_NOT_OWNER);
        assert!(min_sensor_data <= max_sensor_data, E_INVALID_SENSOR_DATA_RANGE);

        let counter: &mut u64 = dynamic_field::borrow_mut(&mut product.id, 0u64);
        let new_sensor_id = *counter;
        *counter = *counter + 1;

        let sensor = Sensor {
            id: new_sensor_id,
            sensor_data: 0,
            min_sensor_data,
            max_sensor_data,
            validity: true,
        };
        
        dynamic_field::add(&mut product.id, new_sensor_id + 1, sensor);
    }

    public entry fun assign_distributor(product: &mut Product, distributor: address, ctx: &mut TxContext) {
        assert!(sender(ctx) == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.distributor == @0x0, E_DISTRIBUTOR_ALREADY_ASSIGNED);
        product.distributor = distributor;
    }

    public entry fun assign_buyer(product: &mut Product, buyer: address, ctx: &mut TxContext) {
        assert!(sender(ctx) == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.buyer == @0x0, E_BUYER_ALREADY_ASSIGNED);
        product.buyer = buyer;
    }
    
    public entry fun change_to_shared(product: Product, ctx: &mut TxContext) {
        assert!(sender(ctx) == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.distributor != @0x0, E_DISTRIBUTOR_NOT_ASSIGNED);
        assert!(product.buyer != @0x0, E_BUYER_NOT_ASSIGNED);

        // Create the wrapper
        let shared_wrapper = SharedProduct {
            id: new(ctx),
            product: product, // The product is "moved" inside the wrapper
        };

        // Share the wrapper, not the original product
        transfer::share_object(shared_wrapper);
    }

    // --- Entry Functions (Shared Phase) ---

public entry fun update_sensor_data(
        shared_product: &mut SharedProduct, // Accepts the wrapper as a mutable reference
        sensor_id: u64,
        sensor_data: u64,
        ctx: &mut TxContext
    ) {
        let participant = sender(ctx);
        // Access to the product data happens through the wrapper's 'product' field
        let product = &mut shared_product.product;
        assert!(
            participant == product.producer ||
            participant == product.distributor ||
            participant == product.buyer,
            E_INVALID_PARTICIPANT
        );
        
        // The ID to which the dynamic fields are bound is that of the internal product
        let sensor: &mut Sensor = dynamic_field::borrow_mut(&mut product.id, sensor_id + 1);
        
        sensor.sensor_data = sensor_data;
        sensor.validity = sensor_data >= sensor.min_sensor_data && sensor_data <= sensor.max_sensor_data;
    }
    
    public entry fun confirm_delivery(shared_product: SharedProduct, ctx: &mut TxContext) {
        let buyer_address = sender(ctx);
        
        // Extract the product from the wrapper. The wrapper is destroyed.
        let SharedProduct { id: wrapper_id, product: mut product } = shared_product;
        // Delete the wrapper UID to free memory
        object::delete(wrapper_id);

        assert!(buyer_address == product.buyer, E_CALLER_NOT_BUYER);
        
        product.owner = buyer_address;
        product.distributor = @0x0;
        product.buyer = @0x0;
        
        // Transfer the original Product object to the new owner
        transfer::transfer(product, buyer_address);
    }
}
