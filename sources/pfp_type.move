module dof_pfp_static::pfp_type;

use codec::base64;
use dos_collection::collection;
use dos_hash_gated_bucket::hash_gated_bucket::{Self, HashGatedBucket};
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

public struct PFP_TYPE has drop {}

public struct PfpType has key, store {
    id: UID,
    collection_id: ID,
    name: String,
    number: u64,
    description: String,
    image_uri: String,
    provenance_hash: String,
    attributes: VecMap<String, String>,
}

public struct CreatePfpCap has key, store {
    id: UID,
    collection_id: ID,
    created_count: u64,
    target_count: u64,
}

public struct RevealPfpCap has key, store {
    id: UID,
    collection_id: ID,
    revealed_count: u64,
    target_count: u64,
}

public struct PfpCreatedEvent has copy, drop {
    collection_id: ID,
    pfp_id: ID,
    pfp_number: u64,
    pfp_provenance_hash: String,
}

public struct PfpRevealedEvent has copy, drop {
    collection_id: ID,
    pfp_id: ID,
}

//=== Constants ===

const COLLECTION_NAME: vector<u8> = b"<COLLECTION_NAME>";
const COLLECTION_DESCRIPTION: vector<u8> = b"<COLLECTION_DESCRIPTION>";
const COLLECTION_EXTERNAL_URL: vector<u8> = b"<COLLECTION_EXTERNAL_URL>";
const COLLECTION_IMAGE_URI: vector<u8> = b"<COLLECTION_IMAGE_URI>";
const COLLECTION_TOTAL_SUPPLY: u64 = 0;

const HASH_GATED_BUCKET_EXTENSION_EPOCHS: u32 = 2;
const HASH_GATED_BUCKET_EXTENSION_UNLOCK_WINDOW: u32 = 2;

//=== Errors ===

const EProvenanceHashMismatch: u64 = 0;
const ECollectionSupplyReached: u64 = 1;
const ERevealTargetCountNotReached: u64 = 2;

//=== Init Function ===

fun init(otw: PFP_TYPE, ctx: &mut TxContext) {
    let publisher = package::claim(otw, ctx);

    let mut display = display::new<PfpType>(&publisher, ctx);
    display.add(b"collection_id".to_string(), b"{collection_id}".to_string());
    display.add(b"name".to_string(), b"{name}".to_string());
    display.add(b"number".to_string(), b"{number}".to_string());
    display.add(b"description".to_string(), b"{description}".to_string());
    display.add(b"image_uri".to_string(), b"{image_uri}".to_string());
    display.add(b"attributes".to_string(), b"{attributes}".to_string());

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

    let create_pfp_cap = CreatePfpCap {
        id: object::new(ctx),
        collection_id: object::id(&collection),
        created_count: 0,
        target_count: COLLECTION_TOTAL_SUPPLY,
    };

    let reveal_pfp_cap = RevealPfpCap {
        id: object::new(ctx),
        collection_id: object::id(&collection),
        revealed_count: 0,
        target_count: COLLECTION_TOTAL_SUPPLY,
    };

    let (hash_gated_bucket, hash_gated_bucket_admin_cap) = hash_gated_bucket::new(
        HASH_GATED_BUCKET_EXTENSION_EPOCHS,
        HASH_GATED_BUCKET_EXTENSION_UNLOCK_WINDOW,
        ctx,
    );

    transfer::public_transfer(collection_admin_cap, ctx.sender());
    transfer::public_transfer(create_pfp_cap, ctx.sender());
    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(hash_gated_bucket_admin_cap, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(reveal_pfp_cap, ctx.sender());

    transfer::public_freeze_object(collection);
    transfer::public_share_object(hash_gated_bucket);
}

//=== Public Function ===

public fun new(
    cap: &mut CreatePfpCap,
    name: String,
    description: String,
    provenance_hash: String,
    ctx: &mut TxContext,
): PfpType {
    assert!(cap.created_count < cap.target_count, ECollectionSupplyReached);

    let pfp = PfpType {
        id: object::new(ctx),
        collection_id: cap.collection_id,
        name: name,
        number: cap.created_count + 1,
        description: description,
        image_uri: b"".to_string(),
        provenance_hash: provenance_hash,
        attributes: vec_map::empty(),
    };

    cap.created_count = cap.created_count + 1;

    emit(PfpCreatedEvent {
        collection_id: cap.collection_id,
        pfp_id: object::id(&pfp),
        pfp_number: pfp.number,
        pfp_provenance_hash: pfp.provenance_hash,
    });

    pfp
}

public fun new_revealed(
    cap: &mut CreatePfpCap,
    name: String,
    description: String,
    provenance_hash: String,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
    ctx: &mut TxContext,
): PfpType {
    assert!(cap.created_count < cap.target_count, ECollectionSupplyReached);

    let pfp = PfpType {
        id: object::new(ctx),
        collection_id: cap.collection_id,
        name: name,
        number: cap.created_count + 1,
        description: description,
        image_uri: image_uri,
        provenance_hash: provenance_hash,
        attributes: vec_map::from_keys_values(attribute_keys, attribute_values),
    };

    cap.created_count = cap.created_count + 1;

    emit(PfpCreatedEvent {
        collection_id: cap.collection_id,
        pfp_id: object::id(&pfp),
        pfp_number: pfp.number,
        pfp_provenance_hash: pfp.provenance_hash,
    });

    pfp
}

public fun receive<T: key + store>(self: &mut PfpType, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut PfpType,
    cap: &mut RevealPfpCap,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
    bucket: &HashGatedBucket,
) {
    assert!(bucket.blob_exists(blob_id_b64_to_u256(image_uri)), 0);

    let provenance_hash = calculate_provenance_hash(
        self.number,
        attribute_keys,
        attribute_values,
        image_uri,
    );

    assert!(self.provenance_hash == provenance_hash, EProvenanceHashMismatch);

    emit(PfpRevealedEvent {
        collection_id: self.collection_id,
        pfp_id: self.id.to_inner(),
    });

    self.attributes = vec_map::from_keys_values(attribute_keys, attribute_values);
    self.image_uri = image_uri;

    cap.revealed_count = cap.revealed_count + 1;
}

public fun create_pfp_cap_destroy(cap: CreatePfpCap) {
    assert!(cap.created_count == cap.target_count, ECollectionSupplyReached);
    let CreatePfpCap { id, .. } = cap;
    id.delete();
}

public fun reveal_pfp_cap_destroy(cap: RevealPfpCap) {
    assert!(cap.revealed_count == cap.target_count, ERevealTargetCountNotReached);
    let RevealPfpCap { id, .. } = cap;
    id.delete();
}

//=== Package Functions ===

public(package) fun calculate_provenance_hash(
    number: u64,
    attribute_keys: vector<String>,
    attribute_values: vector<String>,
    image_uri: String,
): String {
    // Initialize input string for hashing.
    let mut input = b"".to_string();
    input.append(number.to_string());

    // Concatenate the attribute keys and values.
    attribute_keys.do!(|v| input.append(v));
    attribute_values.do!(|v| input.append(v));

    // Concatenate the image URI.
    input.append(image_uri);

    // Calculate the hash, and return hex string representation.
    hex::encode(blake2b256(input.as_bytes())).to_string()
}

//=== View Functions ===

public fun collection_id(self: &PfpType): ID {
    self.collection_id
}

public fun name(self: &PfpType): String {
    self.name
}

public fun number(self: &PfpType): u64 {
    self.number
}

public fun description(self: &PfpType): String {
    self.description
}

public fun image_uri(self: &PfpType): String {
    self.image_uri
}

public fun attributes(self: &PfpType): VecMap<String, String> {
    self.attributes
}

public fun provenance_hash(self: &PfpType): String {
    self.provenance_hash
}

fun blob_id_u256_to_b64(blob_id: u256): String {
    base64::encode(bcs::to_bytes(&blob_id))
}

fun blob_id_b64_to_u256(encoded: String): u256 {
    bcs::peel_u256(&mut bcs::new(base64::decode(encoded)))
}

//=== Test Functions ===

#[test]
fun test_blob_id_u256_to_b64() {
    use codec::base64;
    use sui::bcs;
    let blob_id: u256 =
        26318712447309950621133794408605739963587829295802287350894110878892617743117;
    let encoded = base64::encode(bcs::to_bytes(&blob_id));
    assert!(encoded == b"DbuJ7GRmwjoqo1LDp2qk/H/aI1ycOi2lH3Ka4ATdLzo=".to_string());
}

#[test]
fun test_blob_id_b64_to_u256() {
    use codec::base64;
    use sui::bcs;
    let encoded = b"DbuJ7GRmwjoqo1LDp2qk/H/aI1ycOi2lH3Ka4ATdLzo=".to_string();
    let decoded = base64::decode(encoded);
    let blob_id: u256 = bcs::peel_u256(&mut bcs::new(decoded));
    assert!(
        blob_id == 26318712447309950621133794408605739963587829295802287350894110878892617743117,
    );
}

#[test]
fun test_calculate_provenance_hash() {
    let number = 100;
    let attribute_keys: vector<String> = vector[
        b"aura".to_string(),
        b"background".to_string(),
        b"clothing".to_string(),
        b"decal".to_string(),
        b"headwear".to_string(),
        b"highlight".to_string(),
        b"internals".to_string(),
        b"mask".to_string(),
        b"screen".to_string(),
        b"skin".to_string(),
    ];
    let attribute_values: vector<String> = vector[
        b"none".to_string(),
        b"green".to_string(),
        b"none".to_string(),
        b"none".to_string(),
        b"classic-antenna".to_string(),
        b"green".to_string(),
        b"gray".to_string(),
        b"hyottoko".to_string(),
        b"tamashi-eyes".to_string(),
        b"silver".to_string(),
    ];
    let image_uri = b"MvcX8hU5esyvO1M8NRCrleSQjS9YaH57YBedKIUpYn8".to_string();
    let provenance_hash = calculate_provenance_hash(
        number,
        attribute_keys,
        attribute_values,
        image_uri,
    );
    std::debug::print(&provenance_hash);
}
