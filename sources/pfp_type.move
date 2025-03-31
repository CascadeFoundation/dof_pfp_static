module dof_pfp_static::pfp_type;

use blob_utils::blob_utils::blob_id_b64_to_u256;
use dos_collection::collection::{Self, Collection};
use dos_hash_gated_bucket::hash_gated_bucket::{Self, HashGatedBucket};
use dos_registry::registry::{Self, Registry, RegistryAdminCap};
use dos_static_pfp::static_pfp::{Self, StaticPfp};
use std::string::String;
use sui::display;
use sui::package;
use sui::transfer::Receiving;
use sui::url;
use sui::vec_map::VecMap;

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

const HASH_GATED_BUCKET_EXTENSION_EPOCHS: u32 = 2;
const HASH_GATED_BUCKET_EXTENSION_UNLOCK_WINDOW: u32 = 2;

//=== Init Function ===

fun init(otw: PFP_TYPE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<PfpType>(&publisher, ctx);
    display.add(b"collection_id".to_string(), b"{collection_id}".to_string());
    display.add(b"name".to_string(), b"{pfp.name}".to_string());
    display.add(b"number".to_string(), b"{pfp.number}".to_string());
    display.add(b"description".to_string(), b"{pfp.description}".to_string());
    display.add(b"image_uri".to_string(), b"{pfp.image_uri}".to_string());
    display.add(b"attributes".to_string(), b"{pfp.attributes}".to_string());

    let (collection, collection_admin_cap) = collection::new<PfpType>(
        &publisher,
        COLLECTION_NAME.to_string(),
        @creator,
        COLLECTION_DESCRIPTION.to_string(),
        url::new_unsafe_from_bytes(COLLECTION_EXTERNAL_URL),
        COLLECTION_IMAGE_URI.to_string(),
        COLLECTION_TOTAL_SUPPLY,
        ctx,
    );

    let (hash_gated_bucket, hash_gated_bucket_admin_cap) = hash_gated_bucket::new(
        HASH_GATED_BUCKET_EXTENSION_EPOCHS,
        HASH_GATED_BUCKET_EXTENSION_UNLOCK_WINDOW,
        ctx,
    );

    let (registry, registry_admin_cap) = registry::new<PfpType, u64>(
        registry::new_capped_kind(COLLECTION_TOTAL_SUPPLY),
        ctx,
    );

    transfer::public_transfer(collection_admin_cap, ctx.sender());
    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(hash_gated_bucket_admin_cap, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(registry_admin_cap, ctx.sender());
    transfer::public_freeze_object(collection);
    transfer::public_share_object(hash_gated_bucket);
    transfer::public_share_object(registry);
}

//=== Public Function ===

public fun new(
    name: String,
    description: String,
    external_url: String,
    provenance_hash: String,
    collection: &Collection<PfpType>,
    registry: &mut Registry<PfpType, u64>,
    registry_admin_cap: &RegistryAdminCap<PfpType>,
    ctx: &mut TxContext,
): PfpType {
    let pfp_type = PfpType {
        id: object::new(ctx),
        collection_id: object::id(collection),
        pfp: static_pfp::new(
            name,
            registry.size() + 1,
            description,
            external_url,
            provenance_hash,
        ),
    };

    registry.add(
        registry_admin_cap,
        pfp_type.pfp.number(),
        &pfp_type,
    );

    pfp_type
}

public fun receive<T: key + store>(self: &mut PfpType, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut PfpType,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
    bucket: &HashGatedBucket,
) {
    // Assert a Walrus blob associated with the provided image URI exists.
    bucket.assert_contains_blob(blob_id_b64_to_u256(self.pfp.image_uri()));

    self.pfp.reveal(attribute_keys, attribute_values, image_uri);
}

//=== View Functions ===

public fun collection_id(self: &PfpType): ID {
    self.collection_id
}

public fun name(self: &PfpType): String {
    self.pfp.name()
}

public fun number(self: &PfpType): u64 {
    self.pfp.number()
}

public fun description(self: &PfpType): String {
    self.pfp.description()
}

public fun image_uri(self: &PfpType): String {
    self.pfp.image_uri()
}

public fun attributes(self: &PfpType): VecMap<String, String> {
    self.pfp.attributes()
}

public fun provenance_hash(self: &PfpType): String {
    self.pfp.provenance_hash()
}
