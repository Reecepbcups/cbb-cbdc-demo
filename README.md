# EVM -> Penumbra shielded token demo

This demo walks through launching an ERC20 and sending it to the [shielded Penumbra network](https://members.delphidigital.io/projects/penumbra), with the ability to share a viewing key for balances via [threshold homomorphic encryption](https://protocol.penumbra.zone/main/crypto/flow-encryption/threshold-encryption.html).

Document: https://github.com/reecepbcups/cbb-cbdc-demo

## Architecture

The demo uses 3 networks, a Cosmos EVM, an Intermediate chain, and the destination, Penumbra. The EVM is used for the ERC20 token which is launched. This also has a native token representation via a solidity pointer contract. The intermediate chain is only used for this demo to allow for the EVM to interface with Penumbra. A production based system would remove the need for the intermediate chain and 1 of the relayer processes, reducing the infrastructure complexity.

Learn more about IBC:
- [https://ibcprotocol.dev/](https://ibcprotocol.dev/)
- [Walkthrough video overview](https://www.youtube.com/live/H8-_QqCjG-4?si=WEbHm8oOBLrYl1K7&t=532)

> Note: In production, the EVM could directly interface with Penumbra, this is a limitation of the relayer's bindings between the 2. The ICS20 relayer's both connect well to unique networks, but not to 2 unique networks yet.

This is the current architecture of this demo.

![image](https://github.com/user-attachments/assets/44367f76-5961-4338-985c-91b1ca17c601)

### Setup

The setup for this demo uses the following stack components, running on the ports:

- Hermes & IBC-Go Relayers
- **Sei Network** (EVM):
    * RPC: 27657
    * EVM: 8545
    * GRPC: 9190
    * Chain-ID: `sei`
    * Command: `make run-local-node`
- **CosmosHub** (intermediate for Demo)
    * RPC: 28657
    * GRPC: 9290
    * Chain-ID: `localcosmos-1`
    * Command: `local-ic start cosmoshub --api-port=12345`
- **Penumbra** (shielded destination)
    * RPC: 26657
    * GRPC: 8080
    * Chain-ID: `penumbra-local-devnet-******`
    * Command: `nix develop; just dev`

Sei (EVM) and CosmosHub both are running in docker, while Penumbra is running in a nix shell. The relayers run on the host environment. Work can be done here to integrate all of this into 1 platform, [interchaintest](https://github.com/strangelove-ventures/interchaintest). This would allow 1 command to launch and run this entire workflow and relayers for a local development environment.

## Setup Networks

Install Sei (EVM), CosmosHub (demo intermediate network), and Penumbra (shielded network).

```bash
# Sei (EVM)
git clone git@github.com:Reecepbcups/sei-evm.git --branch reece/cbdc-6-hotfix-6 --depth=1

# Run a local testnet
cd sei-evm; make run-local-node

## --- New Terminal ---

# CosmosHub (intermediate)
wget https://github.com/strangelove-ventures/interchaintest/releases/download/v8.8.1/local-ic -O $(go env GOPATH)/bin/local-ic
chmod +x $(go env GOPATH)/bin/local-ic
local-ic start cosmoshub --api-port=12345

## --- New Terminal ---

# Install Penumbra CLI binaries
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/penumbra-zone/penumbra/releases/latest/download/pcli-installer.sh | sh # installs 0.80.10 to $HOME/.cargo/bin/
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/penumbra-zone/penumbra/releases/latest/download/pd-installer.sh | sh # installs 0.80.10 to $HOME/.cargo/bin/

# reset the old network state data & indexer
pd network unsafe-reset-all
rm -rf ~/.penumbra
rm -rf ~/.local/share/pcli
rm -rf ~/.local/share/pcli-localhost2

git clone git@github.com:Reecepbcups/penumbra.git --single-branch --branch reece/cbb-cbdc-demo --depth=1
cd penumbra
nix develop # https://nixos.org/download/ | sh <(curl -L https://nixos.org/nix/install) --no-daemon
just dev
```

## Penumbra Pre-req setup
<!-- ! NOTE: this section may not be required anymore if it is done down lower -->
<!-- ```bash
# By default is --home is not set in the command, the default  ~/.local/share/pcli is used. For us, this is account #1
cd ./penumbra

# == ACCOUNT 1 (funded, for relaying) ==
pcli init --grpc-url http://localhost:8080 soft-kms import-phrase
# season fiction select similar nut rough network blue ask kiwi magic angry silk armor wisdom wrap urge peasant leaf vital innocent member alert hard

# == ACCOUNT 2 (no funds, receiver) ==
pcli --home ~/.local/share/pcli-localhost2 init --grpc-url http://localhost:8080 soft-kms import-phrase
# room candy egg hair any dice pretty silver prison acquire cake miss owner toss slush oxygen ribbon rent aerobic dinner tourist satoshi perfect again

# this address was put in the network generate command of the penumbra devnet `just dev`
pcli view address 0  # penumbra1cvp32r5wp4lfnnww3g3fytxccqnu2xcj0r2qm0sa8ekjdezlm3gzk34qtg2xscqx9r6yrhz24k3l6j88q98rexyp7dnupq66cxllvpp9v0lw0xuqf0yfhv5ksfxzv0m968tmxn
pcli --home ~/.local/share/pcli-localhost2 view address 0 # penumbra1snux2xkrfujv97k8x2pkchkguudnfyzu8vdcme3er37shlxlwhjxn32648ax938jrjekjsqu4eqkjmdazz86y4yjl3mhh28ncjvkccs6kuqrecktgwn8t3t3mntpp0jhda8l06

pcli view balance --by-note
pcli --home ~/.local/share/pcli-localhost2 view balance --by-note
``` -->


## ERC20 Setup

The EVM network faucets funds to one of the accounts we will use. The dev-private-key is the account we are sending funds to. This account will be used to deploy the ERC20 contract and mint tokens.

```bash
cast wallet address --private-key 57acb95d82739866a5c29e40b0aa2590742ae50425b7dd5b5d279a986370189e # 0xF87A299e6bC7bEba58dbBe5a5Aa21d49bCD16D52
```

### Faucet Funds
```bash
THRESHOLD=100000000000000000000 # 100 Eth
ACCOUNT="0xF87A299e6bC7bEba58dbBe5a5Aa21d49bCD16D52"
DEV_PRIVATE_KEY=57acb95d82739866a5c29e40b0aa2590742ae50425b7dd5b5d279a986370189e
function sei_node_interact() { docker exec --interactive sei-node "$@"; }
function sei_interact_w_password() { printf "12345678\n" | docker exec --interactive sei-node "$@"; }

# Faucet funds from the admin to our EVM account
sei_interact_w_password seid tx evm send $ACCOUNT 100000000000000000000 --from admin --evm-rpc "http://0.0.0.0:8545"
```

### Associate the admin address with the EVM

The EVM network has 2 addresses, native (sei1...) and EVM (0x...). These 2 addresses will be linked together with the associate-address command given our private key.

```bash
ADMIN=`sei_interact_w_password seid keys show admin -a` && echo "Admin: $ADMIN"

# if invalid request, remember to set DEV_PRIVATE_KEY env variable
sei_interact_w_password seid tx evm associate-address ${DEV_PRIVATE_KEY} --from=admin

EVM_ADDR=`seid q evm evm-addr ${ADMIN} -o=json --node=http://127.0.0.1:27657 | jq -r .evm_address` && echo "EVM Addr: $EVM_ADDR"
```

### Deploy ERC20

Deploy the ERC20 using the seid command line.
- Create a tokenfactory token (native token pointer)
- Deploy a standard ERC20 (openzeppelin-contract) and point it to the native token pointer
- Query the native token to get the ERC20 contract address
- Mint tokens and query the balance both in native and in ERC20, these match.

```bash
# Deploy native token
sei_interact_w_password seid tx tokenfactory create-denom cbdc --from=admin --yes --fees 2000usei --node=http://127.0.0.1:27657
DENOM=`sei_node_interact seid q tokenfactory denoms-from-creator ${ADMIN} --node=http://127.0.0.1:27657 -o=json | jq -r .denoms[-1]` && echo "Denom: $DENOM"

# Deploy ERC20 contract that is paired with this native token
sei_interact_w_password seid tx evm call-precompile pointer addNativePointer ${DENOM} --from=admin --fees=2000usei

# Create ERC20 <> Native token pointer
ERC20=`seid q evm pointer NATIVE ${DENOM} --node=http://127.0.0.1:27657 -o=json | jq -r .pointer` && echo "ERC20: $ERC20"
cast call $ERC20 "totalSupply()"

# Mint native tokens
sei_interact_w_password seid tx tokenfactory mint 100${DENOM} --from=admin --fees=2000usei --yes --node=http://127.0.0.1:27657
# You can also mint tokens via the ERC20 here too

# Check value of the native balance
seid q bank balances ${ADMIN} --denom=${DENOM} -o=json --node=http://127.0.0.1:27657

# Value of the ERC20 balance
cast call $ERC20 "balanceOf(address)(uint256)" ${EVM_ADDR}

# Updated ERC20 Total Supply
cast call $ERC20 "totalSupply()"
```

# Setup Evm <> CosmosHub Intermediary

Start the ICS20 relayer to move tokens from the ERC20 on Sei (EVM) to the other network
- Use the Hermes relayer config
- Add relayer accounts to handle the automatic transfers
- Create connection with hermes
- Re-run the relayer config with the go rly relayer to create the token transfer channel
- Start monitoring for pending transfer events

> Typically only 1 relayer would be needed, but there is some odd behavior upstream that would require some relayer modifications. Production would be reduced down to just `hermes create connection` then a `hermes start` command rather than 2 different relayers.

```bash
# Faucet funds to relayer wallet on Sei
# Note: The Cosmoshub is pre-funded in the chains/cosmoshub.json
sei_interact_w_password seid tx bank send admin sei1hj5fveer5cjtn4wd6wstzugjfdxzl0xptqry2z 50000000usei --yes --fees=2000usei --node=http://127.0.0.1:27657

# copy over the sei->hub relayer config
mkdir -p $HOME/.hermes
cp ./relayer/hermes-sei-hub.toml $HOME/.hermes/config.toml

# Create default accounts
# if you get cannot find key file at, fix with: 'mv ~/.hermes/keys/sei/keyring-test/default.json ~/.hermes/keys/sei/keyring-test.json'
hermes keys add --key-name default --chain sei --mnemonic-file ./relayer/mnemonic
hermes keys add --key-name default --chain localcosmos-1 --mnemonic-file ./relayer/mnemonic

# Create connection between sei and the hub
hermes create connection --a-chain=sei --b-chain=localcosmos-1 # stop after ~5-8 seconds

# verify we have a connection
seid q ibc connection connections -o=json --node=http://127.0.0.1:27657 | jq .

# use the relayer to actually link the 2 chain
rm ~/.relayer/config/config.yaml; rly config init
rly chains add --file ./relayer/cosmoshub.json cosmoshub
rly chains add --file ./relayer/sei.json sei
# faster polling for new pending messages
sed -i 's/min-loop-duration: 0s/min-loop-duration: 50ms/g' ~/.relayer/config/config.yaml

# verify balances exist for both
rly q balance cosmoshub
rly q balance sei

rly paths new sei localcosmos-1 cbb-demo-connection

: '
paths:
    cbb-demo-connection:
        src:
            chain-id: sei
            client-id: 07-tendermint-0
            connection-id: connection-0
        dst:
            chain-id: localcosmos-1
            client-id: 07-tendermint-0
            connection-id: connection-0
        src-channel-filter:
            rule: ""
            channel-list: []
'
code ~/.relayer/config/config.yaml

# Link connections to create the token flow channel
rly tx link cbb-demo-connection --block-history=5000 --max-clock-drift=1h --timeout=30s --src-port=transfer --dst-port=transfer --version=ics20-1

# Ensure there is a channel
seid q ibc channel channels -o=json --node=http://127.0.0.1:27657 | jq -r .channels[].channel_id

# Start relaying Sei EVM -> CosmosHub (Intermediary)
rly start cbb-demo-connection
```

# Sent ERC20 from SEI -> Temporary Intermediary

Grab some of the previous information for this new terminal instance. These were set above. Then call the EVM solidity pre-compile to IBC transfer the ERC20 to an intermediary chain. While this is done with the Sei EVM wrapper, it could also be done with a normal `cast call` with the correct hex data input.

The relayer is then flushed to auto handle any packets (else you wait a few seconds for them to be picked up). The balances are then checked on both the ERC20 and the counterparty token.

```bash
# pull previous helpers into this terminal
function sei_node_interact() { docker exec --interactive sei-node "$@"; }
function sei_interact_w_password() { printf "12345678\n" | docker exec --interactive sei-node "$@"; }
ADMIN=`sei_interact_w_password seid keys show admin -a` && echo "Admin: $ADMIN"
DENOM=`sei_node_interact seid q tokenfactory denoms-from-creator ${ADMIN} --node=http://127.0.0.1:27657 -o=json | jq -r .denoms[-1]` && echo "Denom: $DENOM"

# IBC transfer via solidity precompile
sei_interact_w_password seid tx evm call-precompile ibc transferWithDefaultTimeout cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr \
transfer channel-0 ${DENOM} 50 "" --from=admin --evm-rpc="http://0.0.0.0:8545"
# or normally: sei_interact_w_password seid tx ibc-transfer transfer transfer channel-0 cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr 50${DENOM} --node=http://127.0.0.1:27657 --from=admin --fees=2000usei --yes

code ./sei-evm/precompiles/ibc/IBC.sol

# Push the packets through / look at the relayer
rly tx flush cbb-demo-connection

# Validate the ERC20 balance moved over

# ERC20
sei_node_interact seid q bank balances ${ADMIN} --denom=${DENOM} --node=http://127.0.0.1:27657

# Counter party tokens
local-ic interact localcosmos-1 q 'bank balances cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr' --api-address=http://127.0.0.1:12345

# View what the hashed token is
# - https://www.youtube.com/live/H8-_QqCjG-4?si=xOzDLXEnNJP7BEcF&t=2540
local-ic interact localcosmos-1 q 'ibc-transfer denom-trace ibc/55783BC998BF3CB5ACAAF37506E71B7EDAA1E24899A9A86CFB76755F7F7023EB' --api-address=http://127.0.0.1:12345
```

## Transfer from Intermediary to Penumbra

Now move the tokens from the middle chain to Penumbra.

### Setup Hermes Relayer

A different version of the hermes relayer is required here due to some changes in Penumbra. These will be updated upstream to reduce the need for this in a production system. This is the reason that the intermediate chain is required for this demo.

Penumbra accounts are automatically generated with 4 billion addresses. You can send funds to **ANY** of these addresses and it will be accessably by you. This helps increase privacy while maintaining good user experirenece and viewing key sharing.

```bash
# Install the temp hermes relayer for this demo
git clone git@github.com:penumbra-zone/hermes.git penumbra-hermes --depth 1
cd penumbra-hermes
cargo build --release

# Add the key to localcosmos-1 if you have not already
cargo run --release --bin hermes -- \
    --config ../relayer/hermes-hub-penumbra.toml keys add \
    --chain localcosmos-1 --mnemonic-file ../relayer/mnemonic

# == ACCOUNT 1 (funded) ==
# reset wallet state
pcli --home ~/.local/share/pcli init --grpc-url http://localhost:8080 soft-kms import-phrase
# season fiction select similar nut rough network blue ask kiwi magic angry silk armor wisdom wrap urge peasant leaf vital innocent member alert hard

# == ACCOUNT 2 (no funds) ==
pcli --home ~/.local/share/pcli-localhost2 init --grpc-url http://localhost:8080 soft-kms import-phrase
# room candy egg hair any dice pretty silver prison acquire cake miss owner toss slush oxygen ribbon rent aerobic dinner tourist satoshi perfect again

pcli view address 0  # penumbra1cvp32r5wp4lfnnww3g3fytxccqnu2xcj0r2qm0sa8ekjdezlm3gzk34qtg2xscqx9r6yrhz24k3l6j88q98rexyp7dnupq66cxllvpp9v0lw0xuqf0yfhv5ksfxzv0m968tmxn

# penumbra1snux2xkrfujv97k8x2pkchkguudnfyzu8vdcme3er37shlxlwhjxn32648ax938jrjekjsqu4eqkjmdazz86y4yjl3mhh28ncjvkccs6kuqrecktgwn8t3t3mntpp0jhda8l06
PENUMBRA_RECEIVER=`pcli --home ~/.local/share/pcli-localhost2 view address 0`; echo "$PENUMBRA_RECEIVER"

# use the proper chainId for Penumbra
PENUMBRA_CHAIN_ID=`pcli q chain params | jq -r .chainId`; echo "$PENUMBRA_CHAIN_ID"
sed -i "s/id = 'penumbra-local-devnet-.*/id = '${PENUMBRA_CHAIN_ID}'/" ../relayer/hermes-hub-penumbra.toml

# Verify we can query tokens with their viewing keys
pcli --home ~/.local/share/pcli view balance --by-note
pcli --home ~/.local/share/pcli-localhost2 view balance --by-note

# Send some tokens to the 2nd account for the relayer
# pcli --home ~/.local/share/pcli tx send 10000penumbra --to ${PENUMBRA_RECEIVER}

# Perform the create channel
# if error broadcasting, change the config key directory / spender
cargo run --release --bin hermes -- --config ../relayer/hermes-hub-penumbra.toml create channel --a-chain localcosmos-1 --b-chain ${PENUMBRA_CHAIN_ID} --a-port transfer --b-port transfer --new-client-connection --yes

# Validate the connection to Penumbra
pcli query ibc channels
PENUMBRA_CHANNEL=channel-0
COUNTERPARTY_CHANNEl=channel-1


# Get IBC Denom
local-ic interact localcosmos-1 q 'bank balances cosmos1hj5fveer5cjtn4wd6wstzugjfdxzl0xpxvjjvr' --api-address=http://127.0.0.1:12345
ERC20_IBC_DENOM="ibc/55783BC998BF3CB5ACAAF37506E71B7EDAA1E24899A9A86CFB76755F7F7023EB"

cargo run --release --bin hermes -- \
    --config ../relayer/hermes-hub-penumbra.toml tx ft-transfer \
    --src-chain localcosmos-1 --src-port transfer  --src-channel ${COUNTERPARTY_CHANNEl} \
    --dst-chain ${PENUMBRA_CHAIN_ID} --denom ${ERC20_IBC_DENOM} --amount 50 \
    --timeout-height-offset 10000000 --timeout-seconds 10000000 \
    --receiver=${PENUMBRA_RECEIVER}

# start the relayer to transfer packets
cargo run --release --bin hermes -- --config ../relayer/hermes-hub-penumbra.toml start

# Verify the ERC20 was delivered to Penumbra
pcli --home ~/.local/share/pcli-localhost2 view balance --by-note
```

# Summary

An ERC20 was transfered to Penumbra's private shielded pool via IBC. Tokens can now be transfered, staked, traded, or voted with privately. At any time the tokens can be transfered back out from Penumbra to the EVM network (ERC20) to be interacted with, traded, or some other activity.
