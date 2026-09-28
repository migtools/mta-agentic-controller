# Downstream Goose patch: system crypto

Applies to Goose 1.51.0 at submodule revision
`7343b6f43276ec45ae10df10d6e591f91edd05e9`. Keep the submodule unmodified --
the Containerfile applies the patch to its own copy of the source.

## What this is for

`openshift/check-payload` scans release images for crypto that is not the
system FIPS module. For a Rust binary it fails on crypto compiled *into* the
executable, which it detects by looking for defined symbols with known
prefixes: `ring_core_`/`GFp_` (ring), `aws_lc_`/`AWSLC_` (aws-lc-rs),
`BORINGSSL_` (boring), and `OPENSSL_` (statically vendored OpenSSL). A binary
with none of those that lists `libcrypto` in `DT_NEEDED` passes.

Stock Goose fails: the default `rustls-tls` feature pulls in aws-lc-rs, and
`rcgen` links ring or aws-lc-rs to generate the self-signed transport
certificate. Three things move it onto system OpenSSL:

- The build selects `--no-default-features --features
  native-tls,aws-providers,disable-update`, so the TLS stack is OpenSSL rather
  than rustls.
- The patch drops `rcgen` from the `native-tls` feature and builds the
  self-signed certificate with OpenSSL instead. Without this, enabling
  `native-tls` still drags ring in through `rcgen`.
- `OPENSSL_NO_VENDOR=1` in the Containerfile stops `openssl-sys` from falling
  back to `openssl-src`, which would compile OpenSSL into the binary and define
  the `OPENSSL_*` symbols the scan rejects.

`verify-dependencies.sh` asserts the resolved graph still has no such crate,
and the `ldd | grep -q libcrypto.so.3` in the Containerfile asserts the
finished binary really does link the system library. Those two checks are the
pass condition, so keep them in the build rather than relying on the feature
list alone.

## Scope

This makes the binary carry no crypto of its own and route TLS through system
OpenSSL. It is not an audit of every cryptographic call site. Goose still
compiles pure-Rust primitives (`sha2`, `hmac`) for OAuth PKCE, pairing codes
and similar; those define no scanned symbol, and check-payload only reaches its
crate-name denylist through a `cargo auditable` SBOM, which this binary does
not embed. If Goose gains an embedded SBOM, or the scan grows a source-level
check, those call sites become the next thing to move onto OpenSSL.

## Maintenance

The patch touches only `crates/goose/Cargo.toml` (`[features]`) and
`crates/goose/src/acp/transport/tls.rs`. It deliberately does not touch
`Cargo.lock`: a `[features]` edit does not change dependency resolution, so
`cargo build --locked` still holds and the build needs no network beyond the
normal crate fetch.

The image cache key (`cache-key.sh`) covers the submodule revision, the Goose
build region of the Containerfile, and these patch files. Regenerate and
revalidate the patch whenever the submodule revision changes.
