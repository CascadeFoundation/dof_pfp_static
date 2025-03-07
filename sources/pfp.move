module dof_pfp_static::pfp;

use codec::base64;
use dof_pfp_static::registry::Registry;
use dos_attribute::attribute::Attribute;
use dos_bucket::bucket;
use dos_collection::collection::{Self, Collection, CollectionAdminCap};
use dos_image::image::Image;
use dos_silo::silo::{Self, Silo};
use std::string::String;
use sui::bcs;
use sui::display;
use sui::event::emit;
use sui::hash::blake2b256;
use sui::hex;
use sui::package;
use sui::transfer::Receiving;
use sui::url;
use sui::vec_map::{Self, VecMap};

//=== Structs ===

public struct PFP has drop {}

public struct Pfp has key, store {
    id: UID,
    collection_id: ID,
    name: String,
    number: u64,
    description: String,
    image: Option<Image>,
    image_uri: String,
    attributes: VecMap<String, Attribute>,
    provenance_hash: String,
}

public struct InitializeCollectionCap has key, store {
    id: UID,
}

public struct DofStaticPfpDeployedEvent has copy, drop {
    collection_id: ID,
    collection_admin_cap_id: ID,
    bucket_id: ID,
    bucket_admin_cap_id: ID,
    silo_id: ID,
    silo_admin_cap_id: ID,
}

public struct PfpCreatedEvent has copy, drop {
    collection_id: ID,
    pfp_id: ID,
    pfp_number: u64,
    pfp_provenance_hash: String,
}

//=== Constants ===

const COLLECTION_NAME: vector<u8> = b"Prime Machin";
const COLLECTION_DESCRIPTION: vector<u8> = b"Prime Machin is a collection of 100 robots.";
const COLLECTION_EXTERNAL_URL: vector<u8> = b"https://sm.xyz/collections/machin/prime/";
const COLLECTION_IMAGE_URI: vector<u8> = b"";
const COLLECTION_TOTAL_SUPPLY: u64 = 100;

//=== Errors ===

const EProvenanceHashMismatch: u64 = 0;
const ECollectionSupplyReached: u64 = 1;

//=== Init Function ===

fun init(otw: PFP, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<Pfp>(&publisher, ctx);
    display.add(b"collection_id".to_string(), b"{collection_id}".to_string());
    display.add(b"name".to_string(), b"{name}".to_string());
    display.add(b"number".to_string(), b"{number}".to_string());
    display.add(b"description".to_string(), b"{description}".to_string());
    display.add(b"image_uri".to_string(), b"{image_uri}".to_string());
    display.add(b"attributes".to_string(), b"{attributes}".to_string());

    let (collection, collection_admin_cap) = collection::new<Pfp>(
        &publisher,
        COLLECTION_NAME.to_string(),
        @creator,
        COLLECTION_DESCRIPTION.to_string(),
        url::new_unsafe_from_bytes(COLLECTION_EXTERNAL_URL),
        COLLECTION_IMAGE_URI.to_string(),
        COLLECTION_TOTAL_SUPPLY,
        ctx,
    );

    // Create a Silo object for the PFP collection.
    let (silo, silo_admin_cap) = silo::new<Pfp>(COLLECTION_TOTAL_SUPPLY, ctx);

    // Create a Bucket object for the PFP collection.
    let (bucket, bucket_admin_cap) = bucket::new(ctx);

    emit(DofStaticPfpDeployedEvent {
        collection_id: object::id(&collection),
        collection_admin_cap_id: object::id(&collection_admin_cap),
        bucket_id: object::id(&bucket),
        bucket_admin_cap_id: object::id(&bucket_admin_cap),
        silo_id: object::id(&silo),
        silo_admin_cap_id: object::id(&silo_admin_cap),
    });

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(bucket_admin_cap, ctx.sender());
    transfer::public_transfer(collection_admin_cap, ctx.sender());
    transfer::public_transfer(silo_admin_cap, ctx.sender());

    transfer::public_share_object(bucket);
    transfer::public_share_object(silo);

    transfer::public_freeze_object(collection);
}

//=== Public Function ===

public fun new(
    cap: &CollectionAdminCap<Pfp>,
    name: String,
    description: String,
    provenance_hash: String,
    collection: &Collection<Pfp>,
    registry: &mut Registry,
    ctx: &mut TxContext,
): Pfp {
    assert!(registry.size() < collection.supply(), ECollectionSupplyReached);

    let pfp = Pfp {
        id: object::new(ctx),
        collection_id: cap.collection_id(),
        name: name,
        number: registry.size() + 1,
        description: description,
        image: option::none(),
        image_uri: b"".to_string(),
        attributes: vec_map::empty(),
        provenance_hash: provenance_hash,
    };

    emit(PfpCreatedEvent {
        collection_id: object::id(collection),
        pfp_id: object::id(&pfp),
        pfp_number: pfp.number,
        pfp_provenance_hash: pfp.provenance_hash,
    });

    pfp
}

public fun receive<T: key + store>(self: &mut Pfp, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut Pfp,
    _: &CollectionAdminCap<Pfp>,
    attribute_keys: vector<String>,
    attribute_values: vector<Attribute>,
    image: Image,
) {
    let image_uri = base64::encode(bcs::to_bytes(&image.blob().blob_id()));
    let provenance_hash = calculate_provenance_hash(
        self.number,
        attribute_keys,
        attribute_values,
        image_uri,
    );
    assert!(self.provenance_hash == provenance_hash, EProvenanceHashMismatch);

    self.attributes = vec_map::from_keys_values(attribute_keys, attribute_values);
    self.image_uri = image_uri;
    self.image.fill(image);
}

//=== Package Functions ===

public(package) fun calculate_provenance_hash(
    number: u64,
    mut attribute_keys: vector<String>,
    mut attribute_values: vector<Attribute>,
    image_uri: String,
): String {
    // Reverse the order of the attribute keys and values so we can use pop_back().
    attribute_keys.reverse();
    attribute_values.reverse();

    // Initialize input string for hashing.
    let mut input = b"";
    input.append(bcs::to_bytes(&number));

    // Concatenate the attribute keys and values.
    while (!attribute_keys.is_empty()) {
        input.append(attribute_keys.pop_back().into_bytes());
        input.append(attribute_values.pop_back().value().into_bytes());
    };

    // Concatenate the image URI.
    input.append(image_uri.into_bytes());

    // Calculate the hash, and return hex string representation.
    hex::encode(blake2b256(&input)).to_string()
}

//=== Test Functions ===

#[test]
fun test_blob_id_u256_to_b64() {
    let blob_id: u256 =
        26318712447309950621133794408605739963587829295802287350894110878892617743117;
    let encoded = base64::encode(bcs::to_bytes(&blob_id));
    assert!(encoded == b"DbuJ7GRmwjoqo1LDp2qk/H/aI1ycOi2lH3Ka4ATdLzo=".to_string());
}
