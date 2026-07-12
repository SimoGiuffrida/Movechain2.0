module movechain::SupplyChain {

    use sui::object::{Self, UID, new};
    use sui::tx_context::{TxContext, sender};
    use sui::transfer;
    use sui::dynamic_field;

    // --- Codici di Errore ---
    const E_CALLER_NOT_BUYER: u64 = 1;
    const E_DISTRIBUTOR_ALREADY_ASSIGNED: u64 = 2;
    const E_BUYER_ALREADY_ASSIGNED: u64 = 3;
    const E_CALLER_NOT_OWNER: u64 = 4;
    const E_INVALID_PARTICIPANT: u64 = 5;
    const E_INVALID_SENSOR_DATA_RANGE: u64 = 6;
    const E_BUYER_NOT_ASSIGNED: u64 = 10;
    const E_DISTRIBUTOR_NOT_ASSIGNED: u64 = 11;
    const E_NOT_SHARED: u64 = 12; // Aggiunto per coerenza, anche se non usato

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

    // MODIFICA: Aggiunta la struct "Wrapper" per la condivisione
    public struct SharedProduct has key {
        id: UID,
        // L'oggetto Product è ora contenuto qui
        product: Product,
    }

    // --- Funzioni Entry (Fase Owned) ---

    public entry fun create_product(ctx: &mut TxContext) {
        let producer_address = sender(ctx);
        let mut product = Product {
            id: new(ctx),
            owner: producer_address,
            producer: producer_address,
            distributor: @0x0,
            buyer: @0x0,
        };
        // Il contatore rimane un campo dinamico legato all'ID del prodotto
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
    
    // MODIFICA: La funzione ora crea e condivide il wrapper SharedProduct
    public entry fun change_to_shared(product: Product, ctx: &mut TxContext) {
        assert!(sender(ctx) == product.owner, E_CALLER_NOT_OWNER);
        assert!(product.distributor != @0x0, E_DISTRIBUTOR_NOT_ASSIGNED);
        assert!(product.buyer != @0x0, E_BUYER_NOT_ASSIGNED);

        // Crea il wrapper
        let shared_wrapper = SharedProduct {
            id: new(ctx),
            product: product, // Il prodotto viene "spostato" dentro il wrapper
        };

        // Condividi il wrapper, non il prodotto originale
        transfer::share_object(shared_wrapper);
    }

    // --- Funzioni Entry (Fase Shared) ---

    // MODIFICA: La funzione ora accetta il wrapper SharedProduct
    public entry fun update_sensor_data(
        shared_product: &mut SharedProduct, // Accetta il wrapper per riferimento mutabile
        sensor_id: u64,
        sensor_data: u64,
        ctx: &mut TxContext
    ) {
        let participant = sender(ctx);
        // L'accesso ai dati del prodotto avviene tramite il campo 'product' del wrapper
        let product = &mut shared_product.product;
        assert!(participant == product.producer || participant == product.distributor || participant == product.buyer, E_INVALID_PARTICIPANT);
        
        // L'ID a cui sono legati i campi dinamici è quello del prodotto interno
        let sensor: &mut Sensor = dynamic_field::borrow_mut(&mut product.id, sensor_id + 1);
        
        sensor.sensor_data = sensor_data;
        sensor.validity = sensor_data >= sensor.min_sensor_data && sensor_data <= sensor.max_sensor_data;
    }
    
    // MODIFICA: La funzione ora consuma il wrapper SharedProduct per completare la consegna
    public entry fun confirm_delivery(shared_product: SharedProduct, ctx: &mut TxContext) {
        let buyer_address = sender(ctx);
        
        // Estrai il prodotto dal wrapper. Il wrapper viene distrutto.
        let SharedProduct { id: wrapper_id, product: mut product } = shared_product;
        // Elimina l'UID del wrapper per liberare memoria
        object::delete(wrapper_id);

        assert!(buyer_address == product.buyer, E_CALLER_NOT_BUYER);
        
        product.owner = buyer_address;
        product.distributor = @0x0;
        product.buyer = @0x0;
        
        // Trasferisci l'oggetto Product originale (ora modificato) al nuovo proprietario
        transfer::transfer(product, buyer_address);
    }
}
