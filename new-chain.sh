#!/bin/sh
# Start gsr-net from genesis. Run as root on the server after setup.sh:
#   sh /opt/gsr-net/new-chain.sh <signer-descriptors.json>
# This deletes the chain, the miner wallet, the faucet state and the explorer
# data. The descriptors are the signer key from new-key.sh.
set -eu
DESCRIPTORS=$(realpath "$1")
cd /opt/gsr-net
CLI="bin/bitcoin-cli -datadir=/var/lib/gsr-net -conf=/etc/gsr-net/bitcoin.conf"
EXPLORER="docker compose -p gsr-net --env-file /etc/gsr-net/explorer.env -f explorer-compose.yml"
ADDRESS=$(grep -o -- '--address=[a-z0-9]*' gsr-net-miner.service | cut -d= -f2)

systemctl stop gsr-net-faucet gsr-net-miner gsr-net-node
$EXPLORER down
find /var/lib/gsr-net -mindepth 1 -delete
systemctl start gsr-net-node
$CLI -rpcwait getblockcount >/dev/null

$CLI -named createwallet wallet_name=miner blank=true load_on_startup=true >/dev/null
python3 -c '
import json, sys
print(json.dumps([{"desc": d["desc"], "active": d["active"], "internal": d["internal"], "range": d["range"],
                   "next_index": d["next_index"], "timestamp": 0} for d in json.load(open(sys.argv[1]))]))
' "$DESCRIPTORS" | $CLI -rpcwallet=miner -stdin importdescriptors >/dev/null

# Backdate the first 110 blocks so the first coinbase is spendable right away.
NOW=$(date +%s)
for i in $(seq 110 -1 1); do
    core/contrib/signet/miner --quiet "--cli=$CLI -rpcwallet=miner" generate "--grind-cmd=bin/bitcoin-util grind" \
        --address="$ADDRESS" --nbits=1e0377ae --set-block-time=$((NOW - i * 30))
done

systemctl start gsr-net-miner gsr-net-faucet
$EXPLORER up -d
$CLI getblockchaininfo
