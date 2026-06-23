#!/bin/bash
# Create a stable self-signed code-signing identity so rebuilds keep the same
# signature — this stops the macOS Keychain from re-prompting after each build.
# Run once. build.sh signs with this identity automatically when present (else ad-hoc).
set -euo pipefail

IDENTITY="Stash Code Signing"
P12_PW="stash-local"

# A self-signed cert isn't "trusted", so find-identity hides it — check the cert.
if security find-certificate -c "$IDENTITY" >/dev/null 2>&1; then
    echo "✓ Signing identity '$IDENTITY' already exists."
    exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/openssl.cnf" <<'CNF'
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = Stash Code Signing
[v3]
basicConstraints = critical, CA:FALSE
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/openssl.cnf" >/dev/null 2>&1

# -legacy + -macalg sha1: Apple's `security import` can't read OpenSSL 3 defaults.
openssl pkcs12 -export -legacy -macalg sha1 -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/id.p12" -passout "pass:$P12_PW" -name "$IDENTITY" >/dev/null 2>&1

security import "$TMP/id.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P "$P12_PW" -A -T /usr/bin/codesign >/dev/null

echo "✓ Created self-signed code-signing identity '$IDENTITY'."
echo "  build.sh will sign with it, keeping the signature stable across rebuilds,"
echo "  so the Keychain only prompts you once (click 'Always Allow')."
