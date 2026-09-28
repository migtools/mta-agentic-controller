#!/usr/bin/env bash
# Prints the tag for the prebuilt goose binary: everything the binary is
# built from, hashed. Change any of it and the tag changes, so CI recompiles
# instead of reusing a stale binary.
set -euo pipefail
export LC_ALL=C
cd "$(git rev-parse --show-toplevel)"
revision=$(git ls-files --stage images/agent-base/goose-src | awk '{print $2}')
[[ $revision =~ ^[0-9a-f]{40}$ ]] || { echo "Missing Goose submodule revision" >&2; exit 1; }
region=$(sed -n '/^ARG GOOSE_IMAGE=/,/^FROM .* AS goose$/p' images/agent-base/Containerfile)
case "$(printf '%s\n' "$region" | tail -1)" in
    "FROM "*" AS goose") ;;
    *) echo "Cannot identify Goose build stages" >&2; exit 1 ;;
esac
digest=$({
    printf '%s\n%s\n' "$revision" "$region"
    for file in images/agent-base/patches/*; do
        # Prose and this script do not reach the binary. Hashing them would
        # throw away a 35-minute compile over a typo fix.
        if [[ $file == */README.md || $file == */cache-key.sh ]]; then
            continue
        fi
        printf '%s\n' "$file"
        cat "$file"
    done
} | sha256sum | cut -c1-16)
printf '%s-%s\n' "${revision:0:12}" "$digest"
