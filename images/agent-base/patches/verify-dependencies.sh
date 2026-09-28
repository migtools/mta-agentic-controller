#!/usr/bin/env bash
# Fails the build if the Goose dependency graph resolves to a crate that
# carries its own crypto, or stops resolving to the OpenSSL bindings. The
# feature set is what keeps those crates out; this is the assertion that it
# still does. Run from the Goose source root, or pass it as $1.
set -euo pipefail
cd "${1:-.}"
packages=$(cargo tree --locked -p goose-cli --no-default-features \
    --features native-tls,aws-providers,disable-update --edges normal,build \
    --prefix none --format '{p}' | awk '{print $1}' | sort -u)
for forbidden in rustls ring aws-lc-rs aws-lc-sys aws-lc-fips-sys openssl-src; do
    if grep -Fxq "$forbidden" <<< "$packages"; then
        echo "Unexpected crypto dependency: $forbidden" >&2
        exit 1
    fi
done
for required in openssl openssl-sys; do
    if ! grep -Fxq "$required" <<< "$packages"; then
        echo "Missing system crypto dependency: $required" >&2
        exit 1
    fi
done
