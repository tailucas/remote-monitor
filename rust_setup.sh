#!/usr/bin/env bash
set -eu
set -o pipefail

# curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | bash -s -- -y

# rustup-init.sh acquired from https://sh.rustup.rs does not use the
# triple (arm-unknown-linux-gnueabi) as part of selecting the binary
# to download. Instead, pull the specific binary needed because ostype
# is oncorrectly evaluated and cannot be overriden.
curl --retry 3 -C - --proto =https --tlsv1.2 --ciphers TLS_AES_128_GCM_SHA256:TLS_CHACHA20_POLY1305_SHA256:TLS_AES_256_GCM_SHA384:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384 --silent --show-error --fail --location https://static.rust-lang.org/rustup/dist/arm-unknown-linux-gnueabi/rustup-init --output /home/app/rustup-init
chmod +x /home/app/rustup-init
/home/app/rustup-init -y
