module dat3::dat3_invitation_nft {
    use std::error;
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;

    use aptos_std::simple_map::{Self, SimpleMap};
    use aptos_framework::account::{Self, SignerCapability};

    use aptos_token::token::{Self, TokenMutabilityConfig, create_collection, create_token_mutability_config, create_tokendata, check_collection_exists};

    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_framework::aptos_account::create_account;
    #[test_only]
    use aptos_framework::timestamp;
    #[test_only]
    use aptos_token::token::check_collection_exists;

    struct Collections has key {
        data: SimpleMap<String, CollectionConfig>
    }

    struct CollectionSin has key {
        sinCap: SignerCapability,
    }

    struct CollectionConfig has key, store {
        collection_name: String,
        collection_description: String,
        collection_maximum: u64,
        collection_uri: String,
        tokens_uri: String,
        tokens_uri_suffix: String,
        collection_mutate_config: vector<bool>,
        token_name_base: String,
        token_counter: u64,
        royalty_payee_address: address,
        token_description: String,
        token_maximum: u64,
        token_mutate_config: TokenMutabilityConfig,
        royalty_points_den: u64,
        royalty_points_num: u64,
    }

    const PERMISSION_DENIED: u64 = 1000;
    const NOT_FOUND: u64 = 110u64;


    public entry fun new_collection(admin: &signer,
                                    collection_name: String,
                                    collection_description: String,
                                    collection_maximum: u64,
                                    collection_uri: String,
                                    tokens_uri: String,
                                    tokens_uri_suffix: String,
                                    collection_mutate_config: vector<bool>,
                                    token_mutate_config: vector<bool>,
                                    token_name_base: String,
                                    royalty_payee_address: address,
                                    token_description: String,
                                    token_maximum: u64,
                                    royalty_points_den: u64,
                                    royalty_points_num: u64, ) acquires CollectionSin, Collections
    {
        let addr = signer::address_of(admin);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        if (!exists<CollectionSin>(@dat3_nft)) {
            let (resourceSigner, sinCap) = account::create_resource_account(admin, b"dat3_nft");
            move_to(&resourceSigner, CollectionSin { sinCap });
        };
        let sig = account::create_signer_with_capability(&borrow_global<CollectionSin>(@dat3_nft).sinCap);
        if (!exists<Collections>(addr)) {
            move_to(admin, Collections { data: simple_map::create<String, CollectionConfig>() });
        };
        let coll_map = borrow_global_mut<Collections>(addr);
        if (simple_map::contains_key(&coll_map.data, &collection_name)) {
            let config = simple_map::borrow_mut(&mut coll_map.data, &collection_name);
            config.royalty_payee_address = royalty_payee_address;
            config.token_description = token_description;
            config.token_maximum = token_maximum;
            config.royalty_points_num = royalty_points_num;
        }else {
            simple_map::add(&mut coll_map.data, collection_name, CollectionConfig {
                collection_name,
                collection_description,
                collection_maximum,
                collection_uri,
                tokens_uri,
                tokens_uri_suffix,
                collection_mutate_config,
                // this is base name, when minting, we will generate the actual token name as `token_name_base: sequence number`
                token_name_base,
                token_counter: 0,
                royalty_payee_address,
                token_description,
                royalty_points_den,
                token_maximum,
                token_mutate_config: create_token_mutability_config(&token_mutate_config),
                royalty_points_num,
            });
            if(check_collection_exists(@dat3_nft,  collection_name)){
                create_collection(
                    &sig,
                    collection_name,
                    collection_description,
                    collection_uri,
                    collection_maximum,
                    collection_mutate_config
                );
            }
        };
    }

    public entry fun add_tokens(admin: &signer, collection_name: String, names: vector<String>)
    acquires Collections, CollectionSin
    {
        let addr = signer::address_of(admin);
        assert!(addr == @dat3, error::permission_denied(PERMISSION_DENIED));
        let coll_s = borrow_global_mut<Collections>(addr);
        assert!(simple_map::contains_key(&coll_s.data, &collection_name), error::not_found(NOT_FOUND));
        let cnf = simple_map::borrow_mut(&mut coll_s.data, &collection_name);
        let sig = account::create_signer_with_capability(&borrow_global<CollectionSin>(@dat3_nft).sinCap);
        let len = vector::length(&names);
        let uri = cnf.tokens_uri;
        let property_keys = vector::empty<String>();
        vector::push_back(&mut property_keys, string::utf8(b"length"));
        let property_types = vector::empty<0x1::string::String>();
        vector::push_back(&mut property_types, string::utf8(b"0x1::string::String"));
        let png = cnf.tokens_uri_suffix;
        let i = 0;
        while (i < len) {
            let name = vector::borrow(&names, i);
            let token_name = cnf.token_name_base;
            string::append(&mut token_name, *name);
            let token_id = token::create_token_id_raw(
                @dat3_nft,
                cnf.collection_name,
                token_name,
                0
            );
            if (token::balance_of(addr, token_id) > 0) {
                i = i + 1;
                continue
            };

            let token_uri = uri ;
            string::append(&mut token_uri, *name);
            string::append(&mut token_uri, png);
            let property_values = vector::empty<vector<u8>>();
            let value = string::bytes(&u64_to_string(string::length(name)));
            vector::push_back(&mut property_values, *value);
            let token_description = cnf.token_description;
            string::append(&mut token_description, *name);
            let token_data_id = create_tokendata(
                &sig,
                cnf.collection_name,
                token_name,
                token_description,
                cnf.token_maximum,
                token_uri,
                cnf.royalty_payee_address,
                cnf.royalty_points_den,
                cnf.royalty_points_num,
                cnf.token_mutate_config,
                property_keys,
                property_values,
                property_types,
            );
            let token_id = token::mint_token(&sig, token_data_id, 1);
            // simple_mapv1::add(&mut cnf.tokens, *name, token_id);
            token::direct_transfer(&sig, admin, token_id, 1);
            i = i + 1;
        };
    }
    #[test(dat3 = @dat3)]
    fun test_resource_account(dat3: &signer)
    {
        let (_, signer_cap) =
            account::create_resource_account(dat3, b"dat3");
        let (_, signer_cap2) =
            account::create_resource_account(dat3, b"dat3_nft");
        let sig = account::create_signer_with_capability(&signer_cap);
        let sig2 = account::create_signer_with_capability(&signer_cap2);
        debug::print(&signer::address_of(dat3));
        debug::print(&signer::address_of(&sig));
        debug::print(&signer::address_of(&sig2));

    }

    #[test(dat3 = @dat3, to = @dat3_admin, fw = @aptos_framework)]
    fun dat3_nft_init(
        dat3: &signer, to: &signer, fw: &signer
    ) acquires CollectionSin, Collections
    {
        timestamp::set_time_has_started_for_testing(fw);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);


        let tb = vector::empty<bool>();
        vector::push_back(&mut tb, false);
        vector::push_back(&mut tb, false);
        vector::push_back(&mut tb, false);
        let tb1 = vector::empty<bool>();
        vector::push_back(&mut tb1, false);
        vector::push_back(&mut tb1, false);
        vector::push_back(&mut tb1, false);
        vector::push_back(&mut tb1, false);
        vector::push_back(&mut tb1, false);
        let c_name = b"new Collection" ;
        new_collection(dat3,
            string::utf8(c_name),
            string::utf8(b"test"),
            11,
            string::utf8(b"new_collection`s url"),
            string::utf8(b"http://name1.com/sdssdsds"),
            string::utf8(b".png"),
            tb,
            tb1,
            string::utf8(b"name -->#"),
            @dat3,
            string::utf8(b"code #"),
            1, 1000, 50
        );
        let check_coll = check_collection_exists(@dat3_nft, string::utf8(c_name));
        debug::print(&check_coll);
        let names = vector::empty<String>();
        vector::push_back(&mut names, string::utf8(b"1"));
        vector::push_back(&mut names, string::utf8(b"2"));
        vector::push_back(&mut names, string::utf8(b"3"));
        vector::push_back(&mut names, string::utf8(b"4"));

        add_tokens(dat3, string::utf8(c_name), names, );

        let i = 1u64;
        while (i <= 4) {
            let name = string::utf8(b"name -->#");
            string::append(&mut name, u64_to_string(i)) ;
            let token_id = token::create_token_id_raw(
                @dat3_nft,
                string::utf8(c_name),
                name,
                0
            );
            debug::print(&token::balance_of(@dat3, token_id));
            let (addr, s1, s2, _s3) = token::get_token_id_fields(&token_id);
            debug::print(&addr);
            debug::print(&s1);
            debug::print(&s2);
            let td = token::get_tokendata_id(token_id);
            let s = token::get_tokendata_uri(@dat3_nft, td);
            debug::print(&s);
            i=i+1;
        };
    }
    fun u64_to_string(value: u64): String
    {
        if (value == 0) {
            return utf8(b"0")
        };
        let buffer = vector::empty<u8>();
        while (value != 0) {
            vector::push_back(&mut buffer, ((48 + value % 10) as u8));
            value = value / 10;
        };
        vector::reverse(&mut buffer);
        utf8(buffer)
    }
}