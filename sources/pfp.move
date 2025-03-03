module dof_pfp_static::pfp;

use codec::base64;
use dos_bucket::bucket::{Self, BucketAdminCap};
use dos_collection::collection::{Self, CollectionAdminCap};
use dos_image::image::Image;
use dos_silo::silo::{Self, Silo};
use std::string::String;
use sui::bcs;
use sui::display;
use sui::hash::blake2b256;
use sui::hex;
use sui::package::{Self, Publisher};
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
    attributes: VecMap<String, String>,
    provenance_hash: String,
}

public struct InitializeCollectionCap has key, store {
    id: UID,
}

//=== Errors ===

const EProvenanceHashMismatch: u64 = 0;

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

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
}

//=== Public Function ===

public fun initialize(
    cap: InitializeCollectionCap,
    publisher: &Publisher,
    collection_name: String,
    collection_description: String,
    collection_external_url: String,
    collection_image_uri: String,
    collection_total_supply: u64,
    ctx: &mut TxContext,
): (BucketAdminCap, CollectionAdminCap<Pfp>) {
    // Create a Collection object for the PFP collection.
    let (collection, collection_admin_cap) = collection::new<Pfp>(
        publisher,
        collection_name,
        @creator,
        collection_description,
        url::new_unsafe_from_bytes(collection_external_url.into_bytes()),
        collection_image_uri,
        collection_total_supply,
        ctx,
    );

    // Create a Silo object for the PFP collection.
    let silo = silo::new<Pfp>(collection_total_supply, ctx);

    // Create a Bucket object for the PFP collection.
    let (bucket, bucket_admin_cap) = bucket::new(ctx);

    transfer::public_share_object(bucket);
    transfer::public_share_object(silo);
    transfer::public_freeze_object(collection);

    let InitializeCollectionCap { id } = cap;
    id.delete();

    (bucket_admin_cap, collection_admin_cap)
}

public fun new(
    cap: &CollectionAdminCap<Pfp>,
    name: String,
    description: String,
    provenance_hash: String,
    silo: &mut Silo<Pfp>,
    ctx: &mut TxContext,
): Pfp {
    Pfp {
        id: object::new(ctx),
        collection_id: cap.collection_id(),
        name: name,
        number: silo.size() + 1,
        description: description,
        image: option::none(),
        image_uri: b"".to_string(),
        attributes: vec_map::empty(),
        provenance_hash: provenance_hash,
    }
}

public fun receive<T: key + store>(self: &mut Pfp, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut Pfp,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image: Image,
) {
    let image_uri = base64::encode(bcs::to_bytes(&image.blob().blob_id()));
    let provenance_hash = calculate_provenance_hash(attribute_keys, attribute_values, image_uri);
    assert!(self.provenance_hash == provenance_hash, EProvenanceHashMismatch);

    self.attributes = vec_map::from_keys_values(attribute_keys, attribute_values);
    self.image_uri = image_uri;
    self.image.fill(image);
}

//=== Package Functions ===

public(package) fun calculate_provenance_hash(
    mut attribute_keys: vector<String>,
    mut attribute_values: vector<String>,
    image_uri: String,
): String {
    // Reverse the order of the attribute keys and values so we can use pop_back().
    attribute_keys.reverse();
    attribute_values.reverse();

    // Concatenate the attribute keys and values.
    let mut input = b"".to_string();
    while (!attribute_keys.is_empty()) {
        input.append(attribute_keys.pop_back());
        input.append(attribute_values.pop_back());
    };

    // Concatenate the image URI.
    input.append(image_uri);

    // Calculate the hash, and return hex string representation.
    hex::encode(blake2b256(input.as_bytes())).to_string()
}

//=== Test Functions ===

#[test]
fun test_blob_id_u256_to_b64() {
    let blob_id: u256 =
        26318712447309950621133794408605739963587829295802287350894110878892617743117;
    let encoded = base64::encode(bcs::to_bytes(&blob_id));
    assert!(encoded == b"DbuJ7GRmwjoqo1LDp2qk/H/aI1ycOi2lH3Ka4ATdLzo=".to_string());
}
