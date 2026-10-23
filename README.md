# gsr-net

`gsr-net` is a disposable public custom Signet for experimenting with the
[Great Script Restoration](https://github.com/bitcoin-gsr) (GSR) and
Tapleaf 0xC2. It targets 30-second blocks and activates the `tapleaf_0xc2`
deployment from genesis.

This repository holds the deployment. The node software is the `gsr` branch of
[bitcoin-gsr/bitcoin](https://github.com/bitcoin-gsr/bitcoin) at the commit
pinned in `setup.sh`, with `core.patch` applied for 30-second signet blocks.

## What Tapleaf 0xC2 adds

Tapleaf 0xC2 is a second Taproot leaf version. Its scripts get the fifteen
opcodes disabled in Bitcoin 0.3.1 back (`OP_CAT`, `OP_SUBSTR`, `OP_LEFT`,
`OP_RIGHT`, `OP_INVERT`, `OP_AND`, `OP_OR`, `OP_XOR`, `OP_2MUL`, `OP_2DIV`,
`OP_MUL`, `OP_DIV`, `OP_MOD`, `OP_LSHIFT`, `OP_RSHIFT`), arbitrary-length
unsigned numbers, larger stack limits, transaction introspection, signatures
over script-built messages and reusable macros. A varops budget funded by the
transaction's weight bounds the validation cost. Specifications:

- [BIP 440: Varops Budget](https://github.com/jmoik/bips/blob/gsr-full/bip-0440.mediawiki)
- [BIP 441: Restoration of disabled script (Tapleaf 0xC2)](https://github.com/jmoik/bips/blob/gsr-full/bip-0441.mediawiki),
  with [test vectors](https://github.com/jmoik/bips/tree/gsr-full/bip-0441)
- [OP_TX](https://github.com/jmoik/bips/blob/gsr-full/bip-unknown-optx.md) (draft)
- [Extended Primitives](https://github.com/jmoik/bips/blob/gsr-full/bip-unknown-extended-primitives.md)
  (draft): `OP_CHECKSIGFROMSTACK`, `OP_TWEAKADD`, `OP_BYTEREV`
- [Reusable Macros](https://github.com/jmoik/bips/blob/gsr-full/bip-unknown-reusable-macros.md) (draft)

## Network parameters

- Seed: `204.168.231.217:38333`
- Signet challenge: `0014fc65bb67e5653778c206cfe6aca97084d817cb79`
- Message magic: `21a9c698`
- Addresses: signet format (`tb1…`)
- Block spacing: 30 seconds on average, randomised like proof-of-work mining
- Block weight: 4,000,000 WU (Bitcoin's standard limits)
- Tapleaf 0xC2: always active (`tapleaf_0xc2:-1:0`); 0xC2 spends are standard
  and relayed

## Public services

Explorer: <https://gsr-net.204-168-231-217.sslip.io> (plain HTTP fallback:
`http://204.168.231.217`).

Faucet: <https://gsr-net.204-168-231-217.sslip.io/faucet/> sends 1 coin, at
most once per hour per address and per client IP. With JSON it answers
`{"txid": …, "amount": …}` or `{"error": …}`:

```sh
curl -X POST -H 'Content-Type: application/json' -d '{"address": "tb1…"}' \
  https://gsr-net.204-168-231-217.sslip.io/faucet/claim
```

REST API: `https://gsr-net.204-168-231-217.sslip.io/api`, the
[mempool.space REST API](https://mempool.space/docs/api/rest). A spend without
a node needs only:

```sh
API=https://gsr-net.204-168-231-217.sslip.io/api
curl $API/address/<address>/utxo     # coins of an address
curl $API/tx/<txid>                  # a transaction
curl $API/tx/<txid>/status           # its confirmation status
curl $API/blocks/tip/height          # current height
curl -X POST --data <raw tx hex> $API/tx   # broadcast; returns the txid
```

## Make a Tapleaf 0xC2 transaction

No GSR-specific client is needed. A 0xC2 spend is an ordinary Taproot
script-path spend with leaf version `0xc2`: the leaf hash commits to `0xc2`,
the control block starts with `0xc2` or `0xc3` (leaf version plus the output
key's parity), and signatures use the BIP 342 signature message for that leaf.
Any Taproot library that lets you set the leaf version works. Fund your
Taproot address from the faucet, build and sign the spend, and broadcast it
through the API.

For example, the leaf `OP_CAT <"Hello, Tapleaf 0xC2!"> OP_EQUALVERIFY <pubkey>
OP_CHECKSIG` is spent with the witness `<signature> <"Hello, "> <"Tapleaf
0xC2!"> <script> <control block>`. The explorer shows 0xC2 spends as Taproot;
the last witness item, the control block, starting with `c2` or `c3` marks them.

## Run a node

Build the pinned `gsr` commit with `core.patch` applied; without the patch a
node rejects gsr-net's difficulty at the second retarget. The patch makes every
signet use 30-second spacing, so such builds cannot follow the default signet.
Dependencies are listed in Bitcoin Core's
[build notes](https://github.com/bitcoin/bitcoin/tree/master/doc#building).

```sh
git clone https://github.com/bitcoin-gsr/bitcoin gsr-bitcoin && cd gsr-bitcoin
git checkout de567461d03650535519a2e317a8384650b2ef2a
git apply /path/to/gsr-net/core.patch
cmake -B build -DENABLE_IPC=OFF
cmake --build build -j "$(getconf _NPROCESSORS_ONLN)"
```

Use a data directory of its own, so the node never shares one with the default
signet, and put the network options in its `bitcoin.conf`, where `bitcoind`
and `bitcoin-cli` both read them:

```sh
mkdir -p ~/.bitcoin-gsr-net
cat > ~/.bitcoin-gsr-net/bitcoin.conf <<EOF
signet=1
[signet]
signetchallenge=0014fc65bb67e5653778c206cfe6aca97084d817cb79
vbparams=tapleaf_0xc2:-1:0
addnode=204.168.231.217:38333
EOF
build/bin/bitcoind -datadir="$HOME/.bitcoin-gsr-net"
build/bin/bitcoin-cli -datadir="$HOME/.bitcoin-gsr-net" getblockchaininfo
```

## Chain resets

gsr-net restarts from genesis whenever the GSR branch changes consensus. A
reset deletes every coin and transaction and changes the challenge, magic and
pinned commit in this README, which is updated with each reset. If your node's
`signet_challenge` (from `getblockchaininfo`) differs from the one above, it is
on an old chain: pull this repository, rebuild and use a fresh data directory.
