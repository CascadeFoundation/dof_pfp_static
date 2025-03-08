module dof_pfp_static::pfp;

use codec::base64;
use dof_pfp_static::registry::Registry;
use dos_attribute::attribute::{Self, Attribute};
use dos_collection::collection::{Self, Collection, CollectionAdminCap};
use dos_image::image::Image;
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
    image: Option<Image>,
    image_uri: String,
    attributes: VecMap<String, Attribute>,
    provenance_hash: String,
}

public struct InitializeCollectionCap has key, store {
    id: UID,
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

    transfer::public_transfer(display, ctx.sender());
    transfer::public_transfer(publisher, ctx.sender());
    transfer::public_transfer(collection_admin_cap, ctx.sender());

    transfer::public_freeze_object(collection);
}

//=== Public Function ===

public fun new(
    cap: &CollectionAdminCap<PfpType>,
    name: String,
    description: String,
    provenance_hash: String,
    collection: &Collection<PfpType>,
    registry: &mut Registry,
    ctx: &mut TxContext,
): PfpType {
    assert!(registry.size() < collection.supply(), ECollectionSupplyReached);

    let pfp = PfpType {
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

    registry.add_pfp(pfp.number, pfp.id());

    pfp
}

public fun receive<T: key + store>(self: &mut PfpType, obj_to_receive: Receiving<T>): T {
    transfer::public_receive(&mut self.id, obj_to_receive)
}

public fun reveal(
    self: &mut PfpType,
    _: &CollectionAdminCap<PfpType>,
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

    emit(PfpRevealedEvent {
        collection_id: self.collection_id,
        pfp_id: self.id(),
    });

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

public fun id(self: &PfpType): ID {
    self.id.to_inner()
}

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

public fun image(self: &PfpType): &Option<Image> {
    &self.image
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
        attribute::new(b"aura".to_string(), b"none".to_string()),
        attribute::new(b"background".to_string(), b"green".to_string()),
        attribute::new(b"clothing".to_string(), b"none".to_string()),
        attribute::new(b"decal".to_string(), b"none".to_string()),
        attribute::new(b"headwear".to_string(), b"classic-antenna".to_string()),
        attribute::new(b"highlight".to_string(), b"green".to_string()),
        attribute::new(b"internals".to_string(), b"gray".to_string()),
        attribute::new(b"mask".to_string(), b"hyottoko".to_string()),
        attribute::new(b"screen".to_string(), b"tamashi-eyes".to_string()),
        attribute::new(b"skin".to_string(), b"silver".to_string()),
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
