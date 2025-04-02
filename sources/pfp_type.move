module dof_pfp_static::pfp_type;

use blob_utils::blob_utils::blob_id_b64_to_u256;
use dos_collection::collection::{Self, Collection, CollectionAdminCap};
use dos_static_pfp::static_pfp::{Self, StaticPfp};
use std::string::String;
use sui::display;
use sui::package;
use sui::transfer::Receiving;
use sui::vec_map::VecMap;

//=== Aliases ===

public use fun pfp_name as PfpType.name;
public use fun pfp_number as PfpType.number;
public use fun pfp_description as PfpType.description;
public use fun pfp_image_uri as PfpType.image_uri;
public use fun pfp_attributes as PfpType.attributes;
public use fun pfp_provenance_hash as PfpType.provenance_hash;

//=== Structs ===

public struct PFP_TYPE has drop {}

// A wrapper type around StaticPfp that provides control over a unique type.
public struct PfpType has key, store {
    id: UID,
    collection_id: ID,
    pfp: StaticPfp,
}

//=== Constants ===

const COLLECTION_NAME: vector<u8> = b"<COLLECTION_NAME>";
const COLLECTION_DESCRIPTION: vector<u8> = b"<COLLECTION_DESCRIPTION>";
const COLLECTION_EXTERNAL_URL: vector<u8> = b"<COLLECTION_EXTERNAL_URL>";
const COLLECTION_IMAGE_URI: vector<u8> = b"<COLLECTION_IMAGE_URI>";
const COLLECTION_TOTAL_SUPPLY: u64 = 0;

//=== Errors ===

const EInvalidCollectionAdminCap: u64 = 0;

//=== Init Function ===

#[allow(lint(freeze_wrapped))]
fun init(otw: PFP_TYPE, ctx: &mut TxContext) {
    // Create a new Collection<PfpType>. This requires a reference to the OTW
    // to help ensure that another Collection<PfpType> cannot be created after this contract
    // has been deployed. Technically, you could create multiple Collection<PfpType> instances
    // within this init() function, but why in the world would you want to do that?
    let (collection, collection_admin_cap) = collection::new<PfpType, PFP_TYPE>(
        &otw,
        COLLECTION_NAME.to_string(),
        @creator,
        COLLECTION_DESCRIPTION.to_string(),
        COLLECTION_EXTERNAL_URL.to_string(),
        COLLECTION_IMAGE_URI.to_string(),
        COLLECTION_TOTAL_SUPPLY,
        ctx,
    );

    let publisher = package::claim(otw, ctx);

    let mut display = display::new<PfpType>(&publisher, ctx);
    display.add(b"collection_id".to_string(), b"{collection_id}".to_string());
    display.add(b"name".to_string(), b"{pfp.name}".to_string());
    display.add(b"number".to_string(), b"{pfp.number}".to_string());
    display.add(b"description".to_string(), b"{pfp.description}".to_string());
    display.add(b"external_url".to_string(), b"{pfp.external_url}".to_string());
    display.add(b"image_uri".to_string(), b"{pfp.image_uri}".to_string());
    display.add(b"attributes".to_string(), b"{pfp.attributes}".to_string());

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());

    transfer::public_share_object(collection);

    collection_admin_cap.destroy();
}

//=== Public Function ===

// Create a new PFP.
public fun new(
    cap: &CollectionAdminCap<PfpType>,
    name: String,
    description: String,
    external_url: String,
    provenance_hash: String,
    collection: &mut Collection<PfpType>,
    ctx: &mut TxContext,
): PfpType {
    collection.assert_state_initializing();

    let pfp_type = PfpType {
        id: object::new(ctx),
        collection_id: object::id(collection),
        pfp: static_pfp::new(
            name,
            collection.current_supply() + 1,
            description,
            external_url,
            provenance_hash,
        ),
    };
    collection.register_item(
        cap,
        pfp_type.pfp.number(),
        &pfp_type,
    );

    pfp_type
}

// Create a new PFP and reveal it immediately.
// This function is useful for situations where a PFP is not held in a shared object that
// can be accessed by the creator and buyer before the reveal.
public fun new_with_reveal(
    cap: &CollectionAdminCap<PfpType>,
    name: String,
    description: String,
    external_url: String,
    provenance_hash: String,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
    collection: &mut Collection<PfpType>,
    ctx: &mut TxContext,
): PfpType {
    collection.assert_state_initializing();

    let mut pfp_type = PfpType {
        id: object::new(ctx),
        collection_id: object::id(collection),
        pfp: static_pfp::new(
            name,
            collection.current_supply() + 1,
            description,
            external_url,
            provenance_hash,
        ),
    };

    // Call reveal() directly.
    reveal(
        &mut pfp_type,
        cap,
        attribute_keys,
        attribute_values,
        image_uri,
        collection,
    );

    collection.register_item(
        cap,
        pfp_type.pfp.number(),
        &pfp_type,
    );

    pfp_type
}

public fun receive<T: key + store>(self: &mut PfpType, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

// Reveal a PFP with attributes keys, attribute values, and an image URI.
public fun reveal(
    self: &mut PfpType,
    cap: &CollectionAdminCap<PfpType>,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
    collection: &mut Collection<PfpType>,
) {
    assert!(cap.collection_id() == self.collection_id, EInvalidCollectionAdminCap);

    collection.assert_blob_reserved(blob_id_b64_to_u256(self.pfp.image_uri()));
    self.pfp.reveal(attribute_keys, attribute_values, image_uri);
}

//=== View Functions ===

public fun collection_id(self: &PfpType): ID {
    self.collection_id
}

public fun pfp_number(self: &PfpType): u64 {
    self.pfp.number()
}

public fun pfp_name(self: &PfpType): String {
    self.pfp.name()
}

public fun pfp_description(self: &PfpType): String {
    self.pfp.description()
}

public fun pfp_image_uri(self: &PfpType): String {
    self.pfp.image_uri()
}

public fun pfp_attributes(self: &PfpType): VecMap<String, String> {
    self.pfp.attributes()
}

public fun pfp_provenance_hash(self: &PfpType): String {
    self.pfp.provenance_hash()
}
