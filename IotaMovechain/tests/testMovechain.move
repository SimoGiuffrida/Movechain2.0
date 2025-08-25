#[test_only]
module movechain::supply_chain_tests {
    use movechain::SupplyChain;

    const ETestFailed: u64 = 0;

    #[test]
    fun test_create_product() {
        let mut ctx = tx_context::dummy();
        let producer_address = tx_context::sender(&mut ctx);

        SupplyChain::create_product(10, 50, &mut ctx);
        
        let product = object::borrow_global<SupplyChain::Product>(object::last_created());

        assert!(product.owner == producer_address, ETestFailed);
        assert!(product.state == SupplyChain::STATE_OWNED, ETestFailed);
        assert!(product.min_sensor_data == 10 && product.max_sensor_data == 50, ETestFailed);
        assert!(product.product_validity == true, ETestFailed);
    }

    #[test]
    fun test_assign_distributor() {
        let mut ctx = tx_context::dummy();
        let distributor_address = @0x1;

        SupplyChain::create_product(10, 50, &mut ctx);
        let mut product = object::borrow_global_mut<SupplyChain::Product>(object::last_created());

        SupplyChain::assign_distributor(&mut product, distributor_address, &mut ctx);

        assert!(product.distributor == distributor_address, ETestFailed);
    }

    #[test]
    fun test_assign_buyer() {
        let mut ctx = tx_context::dummy();
        let buyer_address = @0x2;

        SupplyChain::create_product(10, 50, &mut ctx);
        let mut product = object::borrow_global_mut<SupplyChain::Product>(object::last_created());

        SupplyChain::assign_buyer(&mut product, buyer_address, &mut ctx);

        assert!(product.buyer == buyer_address, ETestFailed);
    }

    #[test]
    fun test_change_to_shared() {
        let mut ctx = tx_context::dummy();
        let distributor_address = @0x1;
        let buyer_address = @0x2;

        SupplyChain::create_product(10, 50, &mut ctx);
        let mut product = object::borrow_global_mut<SupplyChain::Product>(object::last_created());

        SupplyChain::assign_distributor(&mut product, distributor_address, &mut ctx);
        SupplyChain::assign_buyer(&mut product, buyer_address, &mut ctx);
        SupplyChain::change_to_shared(&mut product, &mut ctx);

        assert!(product.state == SupplyChain::STATE_SHARED, ETestFailed);
    }

    #[test]
    fun test_update_sensor_data() {
        let mut ctx = tx_context::dummy();
        let distributor_address = @0x1;
        let buyer_address = @0x2;

        SupplyChain::create_product(10, 50, &mut ctx);
        let mut product = object::borrow_global_mut<SupplyChain::Product>(object::last_created());

        SupplyChain::assign_distributor(&mut product, distributor_address, &mut ctx);
        SupplyChain::assign_buyer(&mut product, buyer_address, &mut ctx);
        SupplyChain::change_to_shared(&mut product, &mut ctx);

        SupplyChain::update_sensor_data(&mut product, 30, &mut ctx);
        assert!(product.sensor_data == 30, ETestFailed);
        assert!(product.product_validity == true, ETestFailed);

        SupplyChain::update_sensor_data(&mut product, 5, &mut ctx);
        assert!(product.product_validity == false, ETestFailed);
    }

    #[test]
    fun test_confirm_delivery() {
        let mut ctx = tx_context::dummy();
        let distributor_address = @0x1;
        let buyer_address = @0x2;

        SupplyChain::create_product(10, 50, &mut ctx);
        let mut product = object::borrow_global_mut<SupplyChain::Product>(object::last_created());

        SupplyChain::assign_distributor(&mut product, distributor_address, &mut ctx);
        SupplyChain::assign_buyer(&mut product, buyer_address, &mut ctx);
        SupplyChain::change_to_shared(&mut product, &mut ctx);

        tx_context::set_sender(&mut ctx, buyer_address);
        SupplyChain::confirm_delivery(&mut product, &mut ctx);

        assert!(product.state == SupplyChain::STATE_OWNED, ETestFailed);
        assert!(product.owner == buyer_address, ETestFailed);
        assert!(product.distributor == @0x0, ETestFailed);
        assert!(product.buyer == @0x0, ETestFailed);
    }

    #[test, expected_failure(abort_code = ETestFailed)]
    fun test_fail_condition() {
        abort ETestFailed;
    }
}
