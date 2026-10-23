#!/bin/sh
# Set up a gsr-net server on Ubuntu 24.04 or later. Run as root from a clone of
# this repository at /opt/gsr-net:
#   sh /opt/gsr-net/setup.sh
# Safe to rerun after updating the clone; it rebuilds and reinstalls.
set -eu
CORE_REPO=https://github.com/bitcoin-gsr/bitcoin
CORE_COMMIT=de567461d03650535519a2e317a8384650b2ef2a
cd /opt/gsr-net

apt-get update
apt-get install -y build-essential cmake pkgconf git python3 libevent-dev libboost-dev libsqlite3-dev ufw curl gpg
# Keep an existing Docker installation (e.g. docker-ce, which conflicts with docker.io).
command -v docker >/dev/null || apt-get install -y docker.io docker-compose-v2
if [ ! -f /etc/apt/sources.list.d/caddy-stable.list ]; then
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key |
        gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt > /etc/apt/sources.list.d/caddy-stable.list
    apt-get update
fi
apt-get install -y caddy

# The GSR branch of Bitcoin Core plus gsr-net's 30-second signet blocks.
[ -d core/.git ] || git init -q core
git -C core fetch -q --depth 1 "$CORE_REPO" "$CORE_COMMIT"
git -C core reset -q --hard FETCH_HEAD
git -C core apply ../core.patch

# bitcoind, bitcoin-cli and bitcoin-util (the miner's grinder).
cmake -S core -B core/build -DBUILD_TESTS=OFF -DBUILD_UTIL=ON -DBUILD_BITCOIN_BIN=OFF -DENABLE_IPC=OFF
cmake --build core/build -j"$(nproc)"
install -D -m 755 -t bin core/build/bin/bitcoind core/build/bin/bitcoin-cli core/build/bin/bitcoin-util

id gsrnet >/dev/null 2>&1 || useradd --system --home-dir /var/lib/gsr-net --shell /usr/sbin/nologin gsrnet
install -d -o gsrnet -g gsrnet -m 750 /var/lib/gsr-net
install -d -m 755 /etc/gsr-net

# Explorer credentials, generated once. bitcoind only stores the RPC password's hash.
if [ ! -f /etc/gsr-net/explorer.env ]; then
    (umask 077; for v in RPC_PASSWORD MYSQL_PASSWORD MYSQL_ROOT_PASSWORD; do
        echo "$v=$(python3 -c 'import secrets; print(secrets.token_hex(32))')"
    done > /etc/gsr-net/explorer.env)
fi
. /etc/gsr-net/explorer.env
RPCAUTH=$(python3 core/share/rpcauth/rpcauth.py gsr-mempool "$RPC_PASSWORD" | grep '^rpcauth=')
sed "s|^rpcauth=gsr-mempool:REPLACE\$|$RPCAUTH|" bitcoin.conf > /etc/gsr-net/bitcoin.conf

# bitcoind binds RPC on this bridge's gateway for the explorer containers.
docker network inspect gsrnet >/dev/null 2>&1 ||
    docker network create --subnet 172.29.0.0/24 --gateway 172.29.0.1 gsrnet

install -m 644 -t /etc/systemd/system gsr-net-node.service gsr-net-miner.service gsr-net-faucet.service
systemctl daemon-reload
systemctl enable gsr-net-node gsr-net-miner gsr-net-faucet
systemctl restart gsr-net-node
docker compose -p gsr-net --env-file /etc/gsr-net/explorer.env -f explorer-compose.yml up -d

ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443
ufw allow 38333/tcp
ufw allow from 172.29.0.0/24 to 172.29.0.1 port 38332 proto tcp
ufw --force enable

install -m 644 Caddyfile /etc/caddy/Caddyfile
systemctl reload-or-restart caddy
