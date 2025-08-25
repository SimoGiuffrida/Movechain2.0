# SupplyChain Module for Sui MOVE

This `SupplyChain` module is designed for managing products in a supply chain system on the Sui blockchain, with a focus on tracking product states, ownership, and monitoring environmental conditions (like temperature) throughout their lifecycle. It includes key functionalities for producers to create products, assign buyers and distributors, change the product state, monitor sensor data, and confirm final delivery to the buyer.

### Setting up the SUI Environment

To set up the SUI development environment, follow the tutorial provided at the following link:

[Set up SUI Environment - Sui Book](https://intro.sui-book.com/unit-one/lessons/1_set_up_environment.html)

This tutorial provides a step-by-step guide to installing and configuring all necessary components, enabling you to start working with the SUI blockchain.


## Overview of Main Components

### Constants

- **State Constants**:
  - `STATE_OWNED`: Product is owned by a specific entity.
  - `STATE_SHARED`: Product is shared among different participants.

- **Error Codes**:
  Various error codes are defined to handle specific exceptions, such as unauthorized actions, invalid state transitions, and incorrect sensor data ranges.

### Structures

- **Product**:
  Represents a product in the supply chain, holding attributes like unique ID, current owner, state, producer, distributor, buyer, sensor data (e.g., temperature), and product validity status.

- **StateChangedEvent**:
  Event structure that emits information when a product's state changes, specifying the product address and new state.

### Key Functions

1. **`create_product`**:
   - Initializes a product with the producer's address, initial state as `STATE_OWNED`, and specified minimum and maximum sensor data limits.
   - Emits a `StateChangedEvent` indicating the creation.
   - Transfers the product to the producer's ownership.

2. **`assign_distributor`**:
   - Allows the producer (owner) to assign a distributor to the product.
   - Ensures that only the owner can assign and that a distributor is not already assigned.

3. **`assign_buyer`**:
   - Allows the producer to assign a buyer to the product.
   - Ensures that only the owner can assign and that a buyer is not already assigned.

4. **`change_to_shared`**:
   - Changes the product’s state from `STATE_OWNED` to `STATE_SHARED`.
   - Verifies both distributor and buyer are assigned before sharing.
   - Creates a shared copy of the product and emits an event for the state change.

5. **`update_sensor_data`**:
   - Updates the sensor data for the product in the `STATE_SHARED` state.
   - Validates the new sensor data is within defined thresholds; if out of range, marks the product as invalid.

6. **`confirm_delivery`**:
   - Finalizes the product transfer by confirming delivery to the buyer.
   - Sets the state back to `STATE_OWNED`, transfers ownership to the buyer, and clears distributor and buyer fields.
   - Emits a state change event indicating the product is now fully delivered.

## Example Usage

1. **Product Creation**:
   ```move
   SupplyChain::create_product(10, 50, &mut ctx);

2. **Assign Distributor and Buyer:**:
    ```move
    SupplyChain::assign_distributor(&mut product, distributor_address, &mut ctx);
    SupplyChain::assign_buyer(&mut product, buyer_address, &mut ctx);
3.  **Change to Shared State:**
     ```move
    SupplyChain::change_to_shared(&mut product, &mut ctx);
4.  **Update Sensor Data:**
     ```move
      SupplyChain::update_sensor_data(&mut product, 45, &mut ctx);
5.  **Confirm Delivery**
     ```move
      SupplyChain::confirm_delivery(&mut product, &mut ctx);

## Error Handling
Each function uses assert! statements to enforce specific checks and validate input, with error codes used to capture and manage issues, ensuring robustness and correctness.

# Events
The module emits StateChangedEvent whenever the product's state changes, allowing participants to monitor significant events and transitions.

# Security Considerations
**Access Control**: Each function checks the caller’s address to ensure only authorized entities (producer, distributor, or buyer) can perform specific actions.
**Data Validation**: The module enforces range checks for sensor data to ensure that environmental conditions meet required standards.
