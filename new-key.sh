#!/bin/sh
# Generate a new gsr-net signer key with a throwaway regtest node:
#   ./new-key.sh <Bitcoin Core source dir with build/bin> <output dir>
# Writes the private descriptors to <output dir>/signer-descriptors.json and
# prints the signet challenge, message magic and miner payout address. The
# challenge goes into bitcoin.conf, the magic into explorer-compose.yml and the
# address into gsr-net-miner.service.
set -eu
CORE=$1
OUT=$2
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cli() { "$CORE/build/bin/bitcoin-cli" -regtest -datadir="$TMP" -rpcport=18999 "$@"; }
spk() { cli -rpcwallet=signer getaddressinfo "$(cli -rpcwallet=signer getnewaddress "" bech32)" |
    python3 -c 'import json, sys; print(json.load(sys.stdin)["scriptPubKey"])'; }

"$CORE/build/bin/bitcoind" -regtest -datadir="$TMP" -rpcport=18999 -listen=0 -daemonwait >/dev/null
cli createwallet signer >/dev/null
mkdir -p "$OUT"
(umask 077; cli -rpcwallet=signer listdescriptors true | python3 -c '
import json, sys
json.dump([d for d in json.load(sys.stdin)["descriptors"] if d["desc"].startswith("wpkh(")], sys.stdout, indent=1)
' > "$OUT/signer-descriptors.json")
CHALLENGE=$(spk)
PAYOUT=$(spk)
cli stop >/dev/null
sleep 2

python3 - "$CHALLENGE" "$PAYOUT" "$CORE/test/functional" <<'EOF'
import hashlib, sys
sys.path.insert(0, sys.argv[3])
from test_framework.segwit_addr import encode_segwit_address
challenge = bytes.fromhex(sys.argv[1])
magic = hashlib.sha256(hashlib.sha256(bytes([len(challenge)]) + challenge).digest()).digest()[:4]
print("challenge", challenge.hex())
print("magic", magic.hex())
print("miner_address", encode_segwit_address("tb", 0, bytes.fromhex(sys.argv[2])[2:]))
EOF
