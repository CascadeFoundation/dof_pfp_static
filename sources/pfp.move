module dof_pfp_static::pfp;

use codec::base64;
use dos_attribute::attribute::Attribute;
use dos_bucket::bucket;
use dos_collection::collection;
use dos_silo::silo;
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

public struct PfpType has key, store {
    id: UID,
    collection_id: ID,
    name: String,
    number: u64,
    description: String,
    image_uri: String,
    provenance_hash: String,
    attributes: VecMap<String, Attribute>,
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

//=== Errors ===

const EProvenanceHashMismatch: u64 = 0;
const ECollectionSupplyReached: u64 = 1;
const ERevealTargetCountNotReached: u64 = 2;

//=== Init Function ===

fun init(otw: PFP, ctx: &mut TxContext) {
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

    let (bucket, bucket_admin_cap) = bucket::new(ctx);
    let (silo, silo_admin_cap) = silo::new<PfpType>(COLLECTION_TOTAL_SUPPLY, ctx);

    transfer::public_transfer(bucket_admin_cap, ctx.sender());
    transfer::public_transfer(collection_admin_cap, ctx.sender());
    transfer::public_transfer(create_pfp_cap, ctx.sender());
    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(reveal_pfp_cap, ctx.sender());
    transfer::public_transfer(silo_admin_cap, ctx.sender());

    transfer::public_share_object(bucket);
    transfer::public_share_object(silo);

    transfer::public_freeze_object(collection);
}

//=== Public Function ===

const EInvalidDataLength: u64 = 0;

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

public fun new_bulk(
    cap: &mut CreatePfpCap,
    names: vector<String>,
    descriptions: vector<String>,
    provenance_hashes: vector<String>,
    ctx: &mut TxContext,
): vector<PfpType> {
    assert!(names.length() == descriptions.length(), EInvalidDataLength);
    assert!(names.length() == provenance_hashes.length(), EInvalidDataLength);

    assert!(cap.created_count < cap.target_count + names.length(), ECollectionSupplyReached);

    let mut pfps = vector[];

    let collection_id = cap.collection_id;
    let start_number = cap.created_count + 1;
    let end_number = start_number + names.length();

    let mut number = start_number;
    while (number < end_number) {
        let pfp = internal_new(
            collection_id,
            names.pop_back(),
            number,
            descriptions.pop_back(),
            provenance_hashes.pop_back(),
            ctx,
        );

        emit(PfpCreatedEvent {
            collection_id: collection_id,
            pfp_id: object::id(&pfp),
            pfp_number: pfp.number,
            pfp_provenance_hash: pfp.provenance_hash,
        });

        pfps.push_back(pfp);

        number = number + 1;
    };

    cap.created_count = cap.created_count + names.length();

    pfps
}

public fun receive<T: key + store>(self: &mut PfpType, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut PfpType,
    cap: &mut RevealPfpCap,
    attribute_keys: vector<String>,
    attribute_values: vector<Attribute>,
    image_uri: String,
) {
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
    attribute_values: vector<Attribute>,
    image_uri: String,
): String {
    // Initialize input string for hashing.
    let mut input = b"".to_string();
    input.append(number.to_string());

    // Concatenate the attribute keys and values.
    attribute_keys.do!(|v| input.append(v));
    attribute_values.do!(|v| input.append(v.value()));

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

public fun attributes(self: &PfpType): VecMap<String, Attribute> {
    self.attributes
}

public fun provenance_hash(self: &PfpType): String {
    self.provenance_hash
}

//=== Private Functions ===

fun internal_new(
    collection_id: ID,
    name: String,
    number: u64,
    description: String,
    provenance_hash: String,
    ctx: &mut TxContext,
): PfpType {
    PfpType {
        id: object::new(ctx),
        collection_id: collection_id,
        name: name,
        number: number,
        description: description,
        image_uri: b"".to_string(),
        provenance_hash: provenance_hash,
        attributes: vec_map::empty(),
    }
}

//=== Test Functions ===

#[test]
fun test_blob_id_u256_to_b64() {
    let blob_id: u256 =
        26318712447309950621133794408605739963587829295802287350894110878892617743117;
    let encoded = base64::encode(bcs::to_bytes(&blob_id));
    assert!(encoded == b"DbuJ7GRmwjoqo1LDp2qk/H/aI1ycOi2lH3Ka4ATdLzo=".to_string());
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
    let attribute_values: vector<Attribute> = vector[
        dos_attribute::attribute::new(b"aura".to_string(), b"none".to_string()),
        dos_attribute::attribute::new(b"background".to_string(), b"green".to_string()),
        dos_attribute::attribute::new(b"clothing".to_string(), b"none".to_string()),
        dos_attribute::attribute::new(b"decal".to_string(), b"none".to_string()),
        dos_attribute::attribute::new(b"headwear".to_string(), b"classic-antenna".to_string()),
        dos_attribute::attribute::new(b"highlight".to_string(), b"green".to_string()),
        dos_attribute::attribute::new(b"internals".to_string(), b"gray".to_string()),
        dos_attribute::attribute::new(b"mask".to_string(), b"hyottoko".to_string()),
        dos_attribute::attribute::new(b"screen".to_string(), b"tamashi-eyes".to_string()),
        dos_attribute::attribute::new(b"skin".to_string(), b"silver".to_string()),
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
