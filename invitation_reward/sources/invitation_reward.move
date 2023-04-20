module dat3_owner::invitation_reward {
    use std::error;
    use std::signer;
    use std::string::{Self, String, utf8};
    use std::vector;

    use aptos_std::smart_table::{Self, SmartTable};
    use aptos_std::smart_vector::{Self, SmartVector};
    use aptos_framework::account::{Self, SignerCapability};
    use aptos_framework::coin::{Self, Coin};

    use aptos_token::token;

    use dat3_owner::dat3_invitation_nft;

    struct FidStore has key, store {
        data: SmartTable<u64, FidReward>,
    }

    struct FidReward has key, store {
        fid: u64,
        spend: u64,
        earn: u64,
        users: SmartVector<address>,
        claim: u64,
        amount: Coin<0x1::aptos_coin::AptosCoin>,
    }

    struct CheckInvitees has key, store {
        users: SmartTable<address, u64>,
    }

    struct FidRewardSin has key {
        sinCap: SignerCapability,
    }

    const PERMISSION_DENIED: u64 = 1000;
    const NOT_FOUND: u64 = 110u64;
    const ALREADY_EXISTS: u64 = 111u64;
    const NOT_STARTED_YET: u64 = 120u64;
    const ALREADY_ENDED: u64 = 121u64;
    const NO_QUOTA: u64 = 122u64;

    //Everyone can initiate, provided they have this nft
    public entry fun claim_invite_reward(account: &signer, fid: u64) acquires FidStore
    {
        let addr = signer::address_of(account);
        let f_s = borrow_global_mut<FidStore>(@dat3_nft_reward);
        let (_collection_name, _token_name_base, _collection_maximum, _token_maximum, _already_mint,
            _quantity,
        ) = dat3_invitation_nft::collection_config();
        //token name
        let token = _token_name_base;
        string::append(&mut token, new_token_name(fid));
        let token_id = token::create_token_id_raw(
            @dat3_nft,
            _collection_name,
            token,
            0
        );
        let fid_r = smart_table::borrow_mut(&mut f_s.data, fid);
        if (token::balance_of(addr, token_id) > 0 && coin::value(&fid_r.amount) > 0) {
            coin::deposit(addr, coin::extract_all(&mut fid_r.amount));
            fid_r.claim = fid_r.claim + coin::value(&fid_r.amount);
        };
    }

    public fun invitation_reward(
        dat3_reward: &signer,
        fid: u64,
        amount: Coin<0x1::aptos_coin::AptosCoin>,
        is_spend: bool
    ) acquires FidStore
    {
        //Only the dat3_routel resource account is allowed to access
        assert!(signer::address_of(dat3_reward) == @dat3_reward, error::permission_denied(PERMISSION_DENIED));
        let f = borrow_global_mut<FidStore>(@dat3_nft_reward);
        //aborted transaction,coins are safe
        assert!(smart_table::contains(&f.data, fid), error::not_found(NOT_FOUND));
        let fr = smart_table::borrow_mut(&mut f.data, fid);
        let val = coin::value(&amount);
        if (is_spend) {
            fr.spend = fr.spend + val;
        }else {
            fr.earn = fr.earn + val;
        };
        coin::merge(&mut fr.amount, amount);
    }

    public entry fun init(dat3_owner: &signer, ) acquires FidRewardSin {
        if (!exists<FidStore>(@dat3_nft_reward)) {
            //get resourceSigner
            if (!exists<FidRewardSin>(@dat3_nft_reward)) {
                let (resourceSigner, sinCap) = account::create_resource_account(dat3_owner, b"dat3_nft_reward_v1");
                move_to(&resourceSigner, FidRewardSin { sinCap });
            };
            let sig = account::create_signer_with_capability(&borrow_global<FidRewardSin>(@dat3_nft_reward).sinCap);

            move_to(&sig, FidStore {
                data: smart_table::new<u64, FidReward>(),
            }) ;
            move_to(&sig, CheckInvitees {
                users: smart_table::new<address, u64>(),
            })
        };
    }

    public fun add_invitee(
        dat3_routel: &signer,
        fid: u64,
        user: address
    ) acquires FidStore, CheckInvitees
    {
        assert!(signer::address_of(dat3_routel) == @dat3_reward, error::permission_denied(PERMISSION_DENIED));


        let f = borrow_global_mut<FidStore>(@dat3_nft_reward);
        let (_collection_name, _token_name_base, _collection_maximum, _token_maximum, _already_mint,
            _quantity,
        ) = dat3_invitation_nft::collection_config();
        assert!(fid <= _already_mint && fid > 0, error::invalid_argument(NOT_FOUND));
        if (!smart_table::contains(&f.data, fid)) {
            smart_table::add(&mut f.data, fid, FidReward {
                fid,
                spend: 0,
                earn: 0,
                users: smart_vector::empty<address>(),
                claim: 0,
                amount: coin::zero<0x1::aptos_coin::AptosCoin>(),
            })
        };
        let fr = smart_table::borrow_mut(&mut f.data, fid);
        //todo Consider turning "contains" into views
        let check = borrow_global_mut<CheckInvitees>(@dat3_nft_reward);
        smart_table::add(&mut check.users, user, fid);
        smart_vector::push_back(&mut fr.users, user);
    }

    #[view]
    public fun fid_reward(
        fid: u64,
        page: u64,
        size: u64
    ): (u64, u64, u64, u64, vector<address>, u64, ) acquires FidStore
    {
        assert!(exists<FidStore>(@dat3_nft_reward), error::not_found(NOT_FOUND));
        let f = borrow_global<FidStore>(@dat3_nft_reward);
        if (smart_table::contains(&f.data, fid)) {
            let fr = smart_table::borrow(&f.data, fid);
            let total = smart_vector::length(&fr.users);
            if (size == 0 || size > 1000) {
                size = 100;
            };
            if (page == 0) {
                page = 1;
            };
            //the last page
            if (total % size > 0 && page - 1 > (total / size)) {
                page = total / size + 1;
            };
            //begin~end curr=end
            let curr = 0u64;
            if (total < size * page) {
                curr = total;
            }else {
                curr = size * page;
            } ;
            //begin~end begin
            let begin = 0u64;
            if (curr - size > 0) {
                begin = curr - size;
                //the last page
                if (total % size > 0 && page - 1 == (total / size)) {
                    begin = curr - (total % size);
                };
            }else {
                begin = 0;
            };
            let users = vector::empty<address>();
            while (begin < curr) {
                let addr = smart_vector::borrow(&fr.users, begin);
                vector::push_back(&mut users, *addr);
                begin = begin + 1;
            };
            return (fr.fid, coin::value(&fr.amount), fr.spend, fr.earn, users, fr.claim)
        };
        return (fid, 0, 0, 0, vector::empty<address>(), 0)
    }

    #[view]
    public fun is_invitee(user: address): u64 acquires CheckInvitees
    {
        assert!(exists<CheckInvitees>(@dat3_nft_reward), error::not_found(NOT_FOUND));
        let check = borrow_global_mut<CheckInvitees>(@dat3_nft_reward);

        if (smart_table::contains(&check.users, user)) {
            return *smart_table::borrow(&mut check.users, user)
        };
        return 0
    }


    fun new_token_name(i: u64)
    : String
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
        name
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