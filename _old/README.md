# Chains

For now this launches a cosmoshub chain with pre-funded accounts.

- start hermes with timeout of 1 to create the connection (no proper callback because devs broke shit with the .result json response for no reason)
- stop hermes
- copy over the chub and sei configs for the go relayer init
- manually put in the connection & clients
- rly tx link the 2

## From Scratch


###################### TODO: try ! Maybe I do Sei → CosmosHub/Noble → Penumbra?

```bash
# https://github.com/strangelove-ventures/interchaintest/tree/main/local-interchain
# !Start Penumbra here

# install hermes & rly

# faucet funds to relayer wallet
sei_interact_w_password seid tx bank send admin sei1hj5fveer5cjtn4wd6wstzugjfdxzl0xptqry2z 50000000usei --yes --fees=2000usei --node=http://127.0.0.1:27657


cd penumbra-hermes
cargo run --release --bin hermes -- \
    --config ../chains/penumbra-hermes.toml keys add \
    --chain sei --mnemonic-file ../chains/relayer_mnemonic

cp ../chains/penumbra-hermes.toml $HOME/.hermes/config.toml

# start hermes for connection generation without callback

./target/release/hermes keys add --key-name default --chain sei --mnemonic-file ../chains/relayer_mnemonic
# hermes keys add --key-name default --chain penumbra-local-devnet --mnemonic-file ./chains/relayer_mnemonic


./target/release/hermes create connection --a-chain=sei --b-chain=penumbra-local-devnet

cargo run --release --bin hermes -- --config ../chains/penumbra-hermes.toml create channel --a-chain penumbra-local-devnet --b-chain sei --a-port transfer --b-port transfer --new-client-connection

# cancel after waiting for the initconnection on the first time ~8 seconds

# verify it is good
seid q ibc connection connections -o=json | jq -c '.connections[] | pick(.id, .client_id, .counterparty.client_id)' # connection-0 / 07-tendermint-0
# local-ic interact penumbra-local-devnet query 'ibc connection connections' | jq -c '.'

# modify the rly config now
rm ~/.relayer/config/config.yaml
rly config init
rly chains add --file ./chains/relayer_penumbra.json penumbra
rly chains add --file ./chains/relayer_sei.json sei

# ! TODO: IDK if this works
rly keys restore penumbra default "decorate bright ozone fork gallery riot bus exhaust worth way bone indoor calm squirrel merry zero scheme cotton until shop any excess stage laundry"
# penumbra1hj5fveer5cjtn4wd6wstzugjfdxzl0xp9rs2h4

rly q balance penumbra
rly q balance sei

rly paths new sei penumbra-local-devnet demo-path
sed -i 's/min-loop-duration: 0s/min-loop-duration: 50ms/g' ~/.relayer/config/config.yaml

# update the paths to new hardcoded values in the rly config
: '
paths:
    demo-path:
        src:
            chain-id: sei
            client-id: 07-tendermint-0
            connection-id: connection-0
        dst:
            chain-id: penumbra-local-devnet
            client-id: 07-tendermint-0
            connection-id: connection-0
        src-channel-filter:
            rule: ""
            channel-list: []
'
code ~/.relayer/config/config.yaml

rly tx link demo-path --block-history=5000 --max-clock-drift=1h --timeout=30s --src-port=transfer --dst-port=transfer --version=ics20-1

rly start demo-path

seid q ibc channel channels -o=json | jq -r .channels[].channel_id
# sei_interact_w_password seid tx ibc-transfer transfer transfer channel-0 cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr 1usei --from=admin --fees=2000usei --yes
sei_interact_w_password seid tx ibc-transfer transfer transfer channel-0 cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr 1factory/sei10tl944qa0ellc56rhhq6alk0lzf3wu4gzpezdv/native-pointer-test --from=admin --fees=2000usei --yes

rly tx flush demo-path

local-ic interact penumbra-local-devnet q 'bank balances cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr'


# TODO: ibc withdraw
# https://guide.penumbra.zone/pcli/transaction#ibc-withdrawals
# pcli tx withdraw --to <OSMOSIS_ADDRESS> --channel <CHANNEL_ID> 5gm

```


---

# Start counterparty

<!-- ! TODO: migrate this to use penumbra instead -->

```bash
# https://github.com/strangelove-ventures/interchaintest/tree/main/local-interchain
local-ic start cosmoshub
```

# Relayer Setup

<!-- <details>
<summary>Install go relayer</summary>
<br>
```bash
git clone git@github.com:zenrocklabs/cosmos-relayer.git relayer --single-branch --branch hardcoded_unbonding
cd ./relayer/
make install
cd ../
rm -rf ./relayer/
rly version
```
</details> -->

<!-- https://github.com/informalsystems/hermes/issues/3817#issuecomment-1943553905 -->


# Local Hermes based on old working 3.3.0 patch thing
```
wget github.com/informalsystems/hermes/releases/download/v1.2.0/hermes-v1.2.0-x86_64-unknown-linux-gnu.zip
unzip hermes-v1.2.0-x86_64-unknown-linux-gnu.zip
rm hermes-v1.2.0-x86_64-unknown-linux-gnu.zip

./hermes version
```

<details>
<summary>Install hermes relayer</summary>
<br>
```bash
git clone git@github.com:informalsystems/hermes.git --single-branch --branch v1.3.0
cd ./hermes/
cargo clippy --fix --allow-dirty
cargo build --release --no-default-features --bin hermes
cd ../
rm -rf ./hermes/
hermes version
```
</details>

```bash
# cp over the hermes config -> here
cp chains/hermes.toml $HOME/.hermes/config.toml
# code $HOME/.hermes/config.toml # yes trusting_period is 9s for testing here because it must be below 10s unbonding period

hermes keys add --key-name default --chain sei --mnemonic-file ./chains/relayer_mnemonic
hermes keys add --key-name default --chain penumbra-local-devnet --mnemonic-file ./chains/relayer_mnemonic
# rename them to keyring-test.json from default.json where they are at. weird

# Faucet fund the sei relayer wallet since it does not yet exist.
sei_interact_w_password seid tx bank send admin sei1hj5fveer5cjtn4wd6wstzugjfdxzl0xptqry2z 5000000usei --yes --fees=2000usei

hermes create connection --a-chain=sei --b-chain=penumbra-local-devnet

# makes a bunch of connections
hermes create channel --a-chain sei --b-chain penumbra-local-devnet --a-port transfer --b-port transfer --new-client-connection --yes

# hermes start

# now use the connection just made
rm ~/.relayer/config/config.yaml
rly config init
rly chains add --file ./chains/relayer_cosmoshub.json cosmoshub
rly chains add --file ./chains/relayer_sei.json sei
code ~/.relayer/config/config.yaml

seid q ibc connection connections -o=json | jq .

# does not work
hermes create channel --a-chain sei --a-port transfer --b-port transfer --a-connection connection-0

# idk man
rly tx connection demo-path
```

```bash
# Faucet -> Relayer wallet

# dothis outside of the docker exec
rm ~/.relayer/config/config.yaml
rly config init

rly chains add --file ./chains/relayer_cosmoshub.json cosmoshub
rly chains add --file ./chains/relayer_sei.json sei

# go update these to have a faster min-loop-duration (5ms sei, 50ms cosmos)
code ~/.relayer/config/config.yaml


# default acc: chains/cosmoshub.json
# cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr
rly keys restore cosmoshub default "decorate bright ozone fork gallery riot bus exhaust worth way bone indoor calm squirrel merry zero scheme cotton until shop any excess stage laundry"
# sei1hj5fveer5cjtn4wd6wstzugjfdxzl0xptqry2z
rly keys restore sei default "decorate bright ozone fork gallery riot bus exhaust worth way bone indoor calm squirrel merry zero scheme cotton until shop any excess stage laundry"


# Faucet fund the sei relayer wallet since it does not yet exist.
sei_interact_w_password seid tx bank send admin sei1hj5fveer5cjtn4wd6wstzugjfdxzl0xptqry2z 5000000usei --yes --fees=2000usei


rly q balance cosmoshub
rly q balance sei

# Setup & start the demo relayer between both
rly paths new sei penumbra-local-devnet demo-path
rly tx link demo-path --block-history=5000 --max-clock-drift=1h --timeout=30s --src-port=transfer --dst-port=transfer --version=ics20-1
# rly tx channel demo-path --src-port=transfer --dst-port=transfer --order=unordered --version=ics20-1

rly start demo


rly
```

