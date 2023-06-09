module dat3_owner::dat3_invitation_nft {
    use std::error;
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin;
    use aptos_framework::timestamp;

    use aptos_token::token::{Self, TokenMutabilityConfig, create_token_mutability_config, create_collection, create_tokendata};

    #[test_only]
    use aptos_std::debug;
    #[test_only]
    use aptos_framework::aptos_account::create_account;
    #[test_only]
    use aptos_framework::genesis;
    #[test_only]
    use aptos_framework::reconfiguration;
    #[test_only]
    use aptos_token::token::check_collection_exists;

    struct CollectionSin has key {
        sinCap: SignerCapability,
    }

    struct CollectionConfig has key, store {
        collection_name: String,
        collection_description: String,
        collection_maximum: u64,
        collection_uri: String,
        tokens_uri_prefix: String,
        tokens_uri_suffix: String,
        collection_mutate_config: vector<bool>,
        token_name_base: String,
        royalty_payee_address: address,
        token_description: String,
        token_maximum: u64,
        token_mutate_config: TokenMutabilityConfig,
        royalty_points_den: u64,
        royalty_points_num: u64,
        already_mint: u64,
        whitelist: SmartTable<address, vector<u64>>,
        quantity: u64,
        whitelist_mint_config: WhitelistMintConfig
    }

    struct WhitelistMintConfig has key, store {
        price: u64,
        start_time: u64,
        end_time: u64,
    }


    const PERMISSION_DENIED: u64 = 1000;
    const NOT_FOUND: u64 = 110u64;
    const ALREADY_EXISTS: u64 = 111u64;
    const NOT_STARTED_YET: u64 = 120u64;
    const ALREADY_ENDED: u64 = 121u64;
    const NO_QUOTA: u64 = 122u64;


    //create  or modify collection
    public entry fun new_collection(admin: &signer,
                                    collection_name: String,
                                    collection_description: String,
                                    collection_maximum: u64,
                                    collection_uri: String,
                                    tokens_uri_prefix: String,
                                    tokens_uri_suffix: String,
                                    collection_mutate_config: vector<bool>,
                                    token_mutate_config: vector<bool>,
                                    token_name_base: String,
                                    royalty_payee_address: address,
                                    token_description: String,
                                    token_maximum: u64,
                                    royalty_points_den: u64,
                                    royalty_points_num: u64, ) acquires CollectionSin, CollectionConfig
    {
        let addr = signer::address_of(admin);
        assert!(addr == @dat3_owner, error::permission_denied(PERMISSION_DENIED));
        //Create resource account
        if (!exists<CollectionSin>(@dat3_nft)) {
            let (resourceSigner, sinCap) = account::create_resource_account(admin, b"dat3_nft_v1");
            move_to(&resourceSigner, CollectionSin { sinCap });
        };
        if (exists<CollectionConfig>(@dat3_nft)) {
            let config = borrow_global_mut<CollectionConfig>(@dat3_nft);
            config.royalty_payee_address = royalty_payee_address;
            config.token_description = token_description;
            config.token_maximum = token_maximum;
            config.tokens_uri_prefix = tokens_uri_prefix;
            config.royalty_points_den = royalty_points_den;
            config.royalty_points_num = royalty_points_num;
        }else {
            let sig = account::create_signer_with_capability(&borrow_global<CollectionSin>(@dat3_nft).sinCap);
            move_to(&sig, CollectionConfig {
                collection_name,
                collection_description,
                collection_maximum,
                collection_uri,
                tokens_uri_prefix,
                tokens_uri_suffix,
                collection_mutate_config,
                // this is base name, when minting, we will generate the actual token name as `token_name_base: sequence number`
                token_name_base,
                token_description,
                royalty_payee_address,
                royalty_points_den,
                royalty_points_num,
                token_maximum,
                token_mutate_config: create_token_mutability_config(&token_mutate_config),
                already_mint: 0u64, //big::empty<u64>(),
                whitelist: smart_table::new_with_config<address, vector<u64>>(5, 75, 200), //simple_map::create<address, vector<u64>>(),
                quantity: 0u64,
                whitelist_mint_config: WhitelistMintConfig {
                    price: 0u64,
                    start_time: 0u64,
                    end_time: 0u64, }
            });
            create_collection(
                &sig,
                collection_name,
                collection_description,
                collection_uri,
                collection_maximum,
                collection_mutate_config
            );
        };
    }

    public entry fun whitelist(owner: &signer,
                               whitelist: vector<address>,
                               quantity: u64,
                               whitelist_mint_price: u64,
                               whitelist_minting_start_time: u64,
                               whitelist_minting_end_time: u64, )
    acquires CollectionConfig
    {
        let addr = signer::address_of(owner);
        assert!(addr == @dat3_owner, error::aborted(NOT_FOUND));
        let cnf = borrow_global_mut<CollectionConfig>(@dat3_nft);
        let i = 0u64;
        let len = vector::length(&whitelist);
        while (i < len) {
            let add = *vector::borrow(&whitelist, i);
            // if (!simple_map::contains_key(&cnf.whitelist, &add)) {
            //     simple_map::add(&mut cnf.whitelist, add, vector::empty<u64>())
            // };

            if (!smart_table::contains(&cnf.whitelist, add)) {
                smart_table::add(&mut cnf.whitelist, add, vector::empty<u64>());
            };
            i = i + 1;
        };

        if (quantity > 0 && quantity <= cnf.collection_maximum) {
            cnf.quantity = quantity;
        };
        if (whitelist_mint_price > 0) {
            cnf.whitelist_mint_config.price = whitelist_mint_price;
        };
        if (whitelist_minting_start_time > 0 && whitelist_minting_start_time > timestamp::now_seconds()) {
            cnf.whitelist_mint_config.start_time = whitelist_minting_start_time;
        };
        if (whitelist_minting_end_time > 0
            && whitelist_minting_end_time > timestamp::now_seconds()
            && whitelist_minting_end_time > cnf.whitelist_mint_config.start_time) {
            cnf.whitelist_mint_config.end_time = whitelist_minting_end_time;
        };
    }

    public entry fun mint(owner: &signer)
    acquires CollectionConfig, CollectionSin
    {
        let addr = signer::address_of(owner);
        assert!(exists<CollectionConfig>(@dat3_nft), error::aborted(NOT_FOUND));

        let cnf = borrow_global_mut<CollectionConfig>(@dat3_nft);

        assert!(smart_table::contains(&mut cnf.whitelist, addr), error::aborted(NO_QUOTA));

        let your = smart_table::borrow_mut(&mut cnf.whitelist, addr);
        assert!(vector::length(your) < 1, error::already_exists(ALREADY_EXISTS));
        if (cnf.whitelist_mint_config.start_time > 0) {
            assert!(
                timestamp::now_seconds() > cnf.whitelist_mint_config.start_time,
                error::already_exists(NOT_STARTED_YET)
            );
        };
        if (cnf.whitelist_mint_config.end_time > 0) {
            assert!(
                timestamp::now_seconds() > cnf.whitelist_mint_config.start_time
                    && timestamp::now_seconds() < cnf.whitelist_mint_config.end_time,
                error::already_exists(ALREADY_ENDED)
            );
        };
        //get resourceSigner
        let sig = account::create_signer_with_capability(&borrow_global<CollectionSin>(@dat3_nft).sinCap);

        //let already_mint_size = vector::length(&cnf.already_mint);
        let already_mint_size = cnf.already_mint ;
        let i = 0u64;
        if (already_mint_size > 0) {
            i = already_mint_size;
        };
        i = i + 1;
        if (cnf.quantity > 0) {
            assert!(i <= cnf.quantity, error::out_of_range(NO_QUOTA));
        };

        //get empty property
        let (property_keys, property_types, property_values, ) = empty_property();

        //get token name --> token_name_base+code code=0001/0011/0111/1111
        //token_name -->token_name_base+new_token_name()
        //get token url -->  tokens_uri_prefix +i +tokens_uri_suffix =http://xxxx/111.png
        let (token_name, tokens_uri) =
            get_token_base_info(i, cnf.token_name_base, cnf.tokens_uri_prefix, cnf.tokens_uri_suffix, );

        let token_description = cnf.token_description;
        let token_data_id = create_tokendata(
            &sig,
            cnf.collection_name,
            token_name,
            token_description,
            cnf.token_maximum,
            tokens_uri,
            cnf.royalty_payee_address,
            cnf.royalty_points_den,
            cnf.royalty_points_num,
            cnf.token_mutate_config,
            property_keys,
            property_values,
            property_types,
        );

        if (cnf.whitelist_mint_config.price > 0) {
            coin::transfer<0x1::aptos_coin::AptosCoin>(
                owner,
                cnf.royalty_payee_address,
                cnf.whitelist_mint_config.price
            )
        };
        let token_id = token::mint_token(&sig, token_data_id, 1);
        // token::direct_transfer(&sig, owner, token_id, 1);
        token::direct_transfer(&sig, owner, token_id, 1);
        cnf.already_mint = i;
        vector::push_back(your, i)
    }


    public entry fun mint_tokens(admin: &signer, count: u64)
    acquires CollectionSin, CollectionConfig
    {
        let addr = signer::address_of(admin);
        assert!(addr == @dat3_owner, error::permission_denied(PERMISSION_DENIED));
        let cnf = borrow_global_mut<CollectionConfig>(@dat3_nft);
        //get resourceSigner
        let sig = account::create_signer_with_capability(&borrow_global<CollectionSin>(@dat3_nft).sinCap);


        //Get  interval by mint quantity
        let already_mint_size = cnf.already_mint ;
        let i = 0u64;
        if (already_mint_size > 0) {
            i = cnf.already_mint;
        };
        let len = i + count;
        if (len > cnf.collection_maximum) {
            len = cnf.collection_maximum;
        };
        let add = vector::empty<u64>();
        i = i + 1;
        while (i <= len) {
            //add already_mint
            vector::push_back(&mut add, i);
            //get empty property
            let (property_keys, property_types, property_values, ) = empty_property();

            //get token name --> token_name_base+code code=0001/0011/0111/1111
            //token_name -->token_name_base+new_token_name()
            //get token url -->  tokens_uri_prefix +i +tokens_uri_suffix =http://xxxx/111.png
            let (token_name, tokens_uri) =
                get_token_base_info(i, cnf.token_name_base, cnf.tokens_uri_prefix, cnf.tokens_uri_suffix, );

            let token_description = cnf.token_description;
            //DAT3 Invitation Code:2201
            // string::append(&mut token_description, name);

            let token_data_id = create_tokendata(
                &sig,
                cnf.collection_name,
                token_name,
                token_description,
                cnf.token_maximum,
                tokens_uri,
                cnf.royalty_payee_address,
                cnf.royalty_points_den,
                cnf.royalty_points_num,
                cnf.token_mutate_config,
                property_keys,
                property_values,
                property_types,
            );

            let token_id = token::mint_token(&sig, token_data_id, 1);
            token::direct_transfer(&sig, admin, token_id, 1);

            i = i + 1;
        };
        if (vector::length(&add) > 0) {
            cnf.already_mint = cnf.already_mint + vector::length(&add);
            if (!smart_table::contains(&cnf.whitelist, addr)) {
                smart_table::add(&mut cnf.whitelist, addr, vector::empty<u64>())
            };
            let adds = smart_table::borrow_mut(&mut cnf.whitelist, addr);
            vector::append(adds, add);
        };
    }

    fun empty_property()
    : (vector<String>, vector<String>, vector<vector<u8>>, )
    {
        //property is empty
        let property_keys = vector::empty<String>();
        // vector::push_back(&mut property_keys, string::utf8(b"length"));
        let property_types = vector::empty<0x1::string::String>();
        // vector::push_back(&mut property_types, string::utf8(b"0x1::string::String"));
        let property_values = vector::empty<vector<u8>>();
        (property_keys, property_types, property_values)
    }

    fun get_token_base_info(i: u64, token_name_base: String, tokens_uri_prefix: String, tokens_uri_suffix: String)
    : (String, String)
    {
        let token_name = token_name_base;
        string::append(&mut token_name, new_token_name(i));
        let tokens_uri = tokens_uri_prefix ;
        string::append(&mut tokens_uri, u64_to_string(i));
        string::append(&mut tokens_uri, tokens_uri_suffix);
        (token_name, tokens_uri)
    }

    public fun new_token_name(i: u64): String
    {
        let name = string::utf8(b"");
        if (i >= 1000) {
            name = string::utf8(b"");
        } else if (100 <= i && i < 1000) {
            name = string::utf8(b"0");
        } else if (10 <= i && i < 100) {
            name = string::utf8(b"00");
        } else if (i < 10) {
            name = string::utf8(b"000");
        };
        string::append(&mut name, u64_to_string(i));
        return name
    }

    #[view]
    public fun mint_state(addr: address)
    : (u64, u64, u64, u64, u64, u64, bool, u64, vector<String>)
    acquires CollectionConfig
    {
        let _in_whitelist = false;
        let _mint_num = 0u64;
        let _mint_nft = vector::empty<String>();
        let _collection_maximum = 0u64;
        let _quantity = 0u64;
        let _price = 0u64;
        let _end_time = 0u64;
        let _start_time = 0u64;
        //let already_mint = vector::empty<u64>();
        let _already_mint = 0u64;

        let cnf = borrow_global<CollectionConfig>(@dat3_nft);
        _collection_maximum = cnf.collection_maximum;
        _quantity = cnf.quantity;
        //in_whitelist = simple_map::contains_key(&cnf.whitelist, &addr);
        _in_whitelist = smart_table::contains(&cnf.whitelist, addr);
        _already_mint = cnf.already_mint  ;
        _price = cnf.whitelist_mint_config.price;
        _end_time = cnf.whitelist_mint_config.end_time;
        _start_time = cnf.whitelist_mint_config.start_time;
        if (_in_whitelist) {
            // mint_num = vector::length(simple_map::borrow(&cnf.whitelist, &addr));
            _mint_num = vector::length(smart_table::borrow(& cnf.whitelist, addr));
            let i = 0u64;
            while (i < _mint_num) {
                let code = vector::borrow(smart_table::borrow(& cnf.whitelist, addr), i);
                let name = new_token_name(*code);
                let token_name = cnf.token_name_base;
                string::append(&mut token_name, name, );
                vector::push_back(&mut _mint_nft, token_name);
                i = i + 1;
            }
        };

        return (_collection_maximum, _quantity, _price, _start_time, _end_time, _already_mint,
            _in_whitelist,
            _mint_num,
            _mint_nft)
    }

    #[view]
    public fun collection_config()
    : (String, String, u64, u64, u64, u64)
    acquires CollectionConfig
    {
        let cnf = borrow_global<CollectionConfig>(@dat3_nft);
        return (cnf.collection_name, cnf.token_name_base, cnf.collection_maximum, cnf.token_maximum, cnf.already_mint,
            cnf.quantity
        )
    }

    #[test(dat3 = @dat3_owner)]
    fun test_resource_account(dat3: &signer)
    {
        let (_, _sig1) = account::create_resource_account(dat3, b"dat3_nft_v1");
        let (_, _sig2) = account::create_resource_account(dat3, b"dat3_nft_reward_v1");
        let _sig1 = account::create_signer_with_capability(&_sig1);
        let _sig2 = account::create_signer_with_capability(&_sig2);
        debug::print(&signer::address_of(dat3));
        debug::print(&signer::address_of(&_sig1));
        debug::print(&signer::address_of(&_sig2));
        debug::print(&utf8(b"ni12"));
    }

    #[test_only(dat3 = @dat3_owner, to = @dat3_nft, fw = @aptos_framework)]
    // #[test(dat3 = @dat3_owner, to = @dat3_nft, fw = @aptos_framework)]
    public fun dat3_nft_init(
        dat3: &signer, to: &signer, fw: &signer
    ) acquires
    CollectionSin, CollectionConfig
    {
        genesis::setup();

        timestamp::set_time_has_started_for_testing(fw);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);
        // create_account( signer::address_of(fw));

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
        let collection_maximum = 5000u64;
        new_collection(dat3,
            string::utf8(c_name),
            string::utf8(b"test"),
            collection_maximum,
            string::utf8(b"new_collection`s url"),
            string::utf8(b"http://name1.com/sdssdsds"),
            string::utf8(b".png"),
            tb,
            tb1,
            string::utf8(b"name -->#"),
            @dat3_owner,
            string::utf8(b"code #"),
            1, 1000, 50
        );
        new_collection(dat3,
            string::utf8(c_name),
            string::utf8(b"test"),
            collection_maximum,
            string::utf8(b"new_collection`s url"),
            string::utf8(b"http://name1.com/sdssdsds"),
            string::utf8(b".png"),
            tb,
            tb1,
            string::utf8(b"name -->#"),
            @dat3_owner,
            string::utf8(b"code #"),
            1, 1000, 50
        );
        let check_coll = check_collection_exists(@dat3_nft, string::utf8(c_name));
        debug::print(&check_coll);
        let count = 1000u64;

        whitelist(dat3,
            vector::singleton(to_addr),
            1001,
            0,
            0,
            0);
        // mint(to, string::utf8(c_name));
        mint_tokens(dat3, 500, ) ;
        mint_tokens(dat3, 500, ) ;
        mint(to);
        //mint_tokens(dat3, string::utf8(c_name), 100, );

        let i = 1u64;
        while (i <= count) {
            let name = new_token_name(i);
            let token_name = string::utf8(b"name -->#");
            string::append(&mut token_name, name) ;
            debug::print(&token_name);
            let token_id = token::create_token_id_raw(
                @dat3_nft,
                string::utf8(c_name),
                token_name,
                0
            );
            debug::print(&token::balance_of(@dat3_owner, token_id));
            let (addr, _s1, s2, _s3) = token::get_token_id_fields(&token_id);
            debug::print(&addr);

            debug::print(&s2);
            let td = token::get_tokendata_id(token_id);
            let s = token::get_tokendata_uri(@dat3_nft, td);
            debug::print(&s);
            i = i + 1;
        };

        debug::print(&reconfiguration::current_epoch());
        let (_v1, _v2, _v3, _v4, _v5, _v6, _v7, _v8, _v9, ) = mint_state(addr);
        debug::print(&_v1);
        debug::print(&_v2);
        debug::print(&_v3);
        debug::print(&_v4);
        debug::print(&_v5);
        debug::print(&_v6);
        debug::print(&_v7);
        debug::print(&_v8);
        debug::print(&_v9);
    }

    #[test(dat3 = @dat3_owner, to = @dat3_nft, fw = @aptos_framework)]
    fun dat3_nft_mint(
        dat3: &signer, to: &signer, fw: &signer
    ) acquires
    CollectionSin, CollectionConfig
    {
        genesis::setup();

        timestamp::set_time_has_started_for_testing(fw);
        let addr = signer::address_of(dat3);
        let to_addr = signer::address_of(to);
        create_account(addr);
        create_account(to_addr);
        // create_account( signer::address_of(fw));

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
        let collection_maximum = 5000u64;
        new_collection(dat3,
            string::utf8(c_name),
            string::utf8(b"test"),
            collection_maximum,
            string::utf8(b"new_collection`s url"),
            string::utf8(b"http://name1.com/sdssdsds"),
            string::utf8(b".png"),
            tb,
            tb1,
            string::utf8(b"name -->#"),
            @dat3_owner,
            string::utf8(b"code #"),
            1, 1000, 50
        );

        let check_coll = check_collection_exists(@dat3_nft, string::utf8(c_name));
        debug::print(&check_coll);

        whitelist(dat3,
            vector::singleton(to_addr),
            1002,
            0,
            0,
            0);
        // mint(to, string::utf8(c_name));
        mint_tokens(dat3, 500, ) ;
        mint_tokens(dat3, 500, ) ;
        mint(to);
        let token_id = token::create_token_id_raw(
            @dat3_nft,
            string::utf8(c_name),
            string::utf8(b"name -->#1001"),
            0
        );
        debug::print(&token::balance_of(signer::address_of(to), token_id));
        debug::print(&token::balance_of(signer::address_of(to), token_id));
        let c = borrow_global_mut<CollectionConfig>(@dat3_nft);
        debug::print(&c.whitelist);
    }
    #[view]
    public fun mint_state_s(addr: address)
    : (u64, u64, u64, u64, u64, u64, bool, u64, vector<u64>)
    // acquires CollectionConfig
    {
        let _in_whitelist = false;
        let _mint_num = 0u64;
        let _mint_nft = vector::empty<u64>();
        let _collection_maximum = 0u64;
        let _quantity = 0u64;
        let _price = 0u64;
        let _end_time = 0u64;
        let _start_time = 0u64;
        //let already_mint = vector::empty<u64>();
        let _already_mint = 0u64;
        let _ =addr;
        return (_collection_maximum, _quantity, _price, _start_time, _end_time, _already_mint,
            _in_whitelist,
            _mint_num,
            _mint_nft)
    }


    fun u64_to_string(value: u64)
    : String
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