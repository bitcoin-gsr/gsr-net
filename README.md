# gsr-net

`gsr-net` is a disposable public custom Signet for experimenting with GSR and
Tapleaf 0xC2. It targets 30-second blocks and activates the `tapleaf_0xc2`
deployment from genesis. The chain is restarted from genesis with a new signer
key whenever the GSR branch changes consensus.

This repository holds the deployment. The node software is the `gsr` branch of
[bitcoin-gsr/bitcoin](https://github.com/bitcoin-gsr/bitcoin) at the commit
pinned in `setup.sh`, with `core.patch` applied for 30-second signet blocks.

## Network parameters

- Seed: `204.168.231.217:38333`
- Signet challenge: `0014fc65bb67e5653778c206cfe6aca97084d817cb79`
- Message magic: `21a9c698`
- Block spacing: 30 seconds on average, randomised like proof-of-work mining
- Block weight: 4,000,000 WU (Bitcoin's standard limits)
- Tapleaf 0xC2: always active (`tapleaf_0xc2:-1:0`)

## Public services

- Explorer: `https://gsr-net.204-168-231-217.sslip.io`
  (plain HTTP fallback: `http://204.168.231.217`)
- REST API: `/api/`; broadcast a raw transaction with `POST /api/tx`
- Faucet: `/faucet/`, 1 test BTC per address and client IP per hour

## Connect a node

Build the pinned `gsr` commit with `core.patch` applied; without the patch a
node rejects gsr-net's difficulty at the second retarget. The patch makes every
signet use 30-second spacing, so such builds cannot follow the default signet.

```sh
git clone https://github.com/bitcoin-gsr/bitcoin && cd bitcoin
git checkout de567461d03650535519a2e317a8384650b2ef2a
git apply /path/to/gsr-net/core.patch
cmake -B build -DENABLE_IPC=OFF && cmake --build build -j"$(nproc)"
build/bin/bitcoind -signet \
  -signetchallenge=0014fc65bb67e5653778c206cfe6aca97084d817cb79 \
  -vbparams=tapleaf_0xc2:-1:0 \
  -addnode=204.168.231.217:38333
```
