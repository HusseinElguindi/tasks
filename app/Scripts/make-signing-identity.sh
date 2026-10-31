#!/bin/zsh
# Creates the "Tasks Local Signing" code-signing identity in the login keychain, once, and points the build at it
# (Signing.local.xcconfig, not checked in). Builds signed with it keep the same designated requirement, so the Keychain
# remembers "Always Allow" for the sync token across builds; ad-hoc builds got a new one each time (v2 feedback 11).
#
#   Scripts/make-signing-identity.sh            make the identity if it's missing, and use it
#   Scripts/make-signing-identity.sh --trust    also mark the certificate trusted for code signing (optional; macOS
#                                               asks for your password; signing works without it)
#
# The certificate is self-signed (20 years, code signing only). The private key is generated in a temporary folder,
# imported into the login keychain where only codesign may use it without asking, and the temporary copy deleted.
set -euo pipefail

NAME="Tasks Local Signing"
APP=${0:A:h:h}
KEYCHAIN=~/Library/Keychains/login.keychain-db
LOCAL=$APP/Signing.local.xcconfig

has_identity() { security find-identity -p codesigning "$KEYCHAIN" | grep -qF "\"$NAME\""; }

if has_identity; then
  echo "\"$NAME\" is already in the login keychain."
else
  tmp=$(mktemp -d)
  trap 'rm -rf "$tmp"' EXIT
  chmod 700 "$tmp"
  cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
  openssl req -x509 -newkey rsa:2048 -nodes -days 7300 -config "$tmp/cert.cnf" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  # A PKCS#12 for `security import`, under a throwaway passphrase (macOS won't import one without).
  pass=$(openssl rand -hex 16)
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
    -passout "pass:$pass" -out "$tmp/identity.p12"
  security import "$tmp/identity.p12" -k "$KEYCHAIN" -P "$pass" -T /usr/bin/codesign >/dev/null
  has_identity || { echo "Imported, but codesign can't find \"$NAME\"." >&2; exit 1; }
  echo "Made \"$NAME\" in the login keychain."
fi

if [[ ${1:-} == --trust ]]; then
  pem=$(mktemp)
  security find-certificate -c "$NAME" -p "$KEYCHAIN" > "$pem"
  security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$pem"
  rm -f "$pem"
  echo "Marked \"$NAME\" trusted for code signing."
fi

printf '// Written by Scripts/make-signing-identity.sh; not checked in.\nCODE_SIGN_IDENTITY = %s\n' "$NAME" > "$LOCAL"
echo "Builds now sign with \"$NAME\" ($LOCAL)."
