#!/usr/bin/env bash

set -euo pipefail

base_path="/Users/garnetuniverse/Dropbox/auto.transcribe.agent"
cert_dir="$base_path/certs"
cert_file="$cert_dir/mobile-recorder.crt"
key_file="$cert_dir/mobile-recorder.key"
config_file="$cert_dir/mobile-recorder.cnf"

mkdir -p "$cert_dir"

local_ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
if [ -z "$local_ip" ]; then
    local_ip="$(ipconfig getifaddr en1 2>/dev/null || true)"
fi
if [ -z "$local_ip" ]; then
    local_ip="127.0.0.1"
fi

cat >"$config_file" <<EOF
[req]
default_bits = 2048
prompt = no
default_md = sha256
x509_extensions = v3_req
distinguished_name = dn

[dn]
CN = $local_ip

[v3_req]
subjectAltName = @alt_names

[alt_names]
IP.1 = $local_ip
IP.2 = 127.0.0.1
DNS.1 = localhost
EOF

openssl req -x509 -nodes -days 825 \
    -newkey rsa:2048 \
    -keyout "$key_file" \
    -out "$cert_file" \
    -config "$config_file"

echo "Created:"
echo "  $cert_file"
echo "  $key_file"
echo
echo "If Safari warns about the certificate, you will need to trust it on the iPhone before mic access works."
