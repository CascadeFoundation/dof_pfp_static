module prime_machin::registry;

use sui::table::{Self, Table};

//=== Structs ===

public struct REGISTRY has drop {}

public struct Registry has key {
    id: UID,
    state: RegistryState,
    pfps: Table<u64, ID>,
}

public enum RegistryState has copy, drop, store {
    INITIALIZING { current_size: u64, target_size: u64 },
    INITIALIZED,
}

//=== Errors ===

const ERegistryAlreadyInitialized: u64 = 0;

//=== Init Function ===

fun init(_otw: REGISTRY, ctx: &mut TxContext) {
    let registry = Registry {
        id: object::new(ctx),
        state: RegistryState::INITIALIZING { current_size: 0, target_size: 0 },
        pfps: table::new(ctx),
    };

    transfer::share_object(registry);
}

//=== Public Functions ===

public fun pfp_id_from_number(self: &Registry, pfp_number: u64): ID {
    *self.pfps.borrow(pfp_number)
}

//=== Package Functions ===

public(package) fun add_pfp(self: &mut Registry, pfp_number: u64, pfp_id: ID) {
    match (&mut self.state) {
        RegistryState::INITIALIZING { current_size, target_size } => {
            self.pfps.add(pfp_number, pfp_id);
            *current_size = *current_size + 1;
            if (current_size == target_size) {
                self.state = RegistryState::INITIALIZED;
            }
        },
        RegistryState::INITIALIZED => abort ERegistryAlreadyInitialized,
    }
}

public(package) fun size(self: &Registry): u64 {
    self.pfps.length()
}
