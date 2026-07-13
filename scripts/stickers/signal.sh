#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/stickers/signal.sh URL [OUTPUT.zip]

Download and decrypt a Signal sticker pack into a Parla sticker archive.

Arguments:
  URL         A signal.art sticker-pack URL containing pack_id and pack_key
  OUTPUT.zip  Archive path (default: <pack-id>.zip)

Find public Signal sticker-pack links at https://signalstickers.org/.
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

download_encrypted() {
    local url="$1"
    local output="$2"
    local description="$3"

    if ! curl -fsS \
            --retry 3 \
            --retry-delay 1 \
            --connect-timeout 20 \
            "$url" \
            --output "$output"; then
        die "could not download $description"
    fi
}

# Signal derives separate AES and HMAC keys from the URL's pack key. Each CDN
# object is IV || AES-256-CBC(ciphertext) || HMAC-SHA256(IV || ciphertext).
decrypt_file() {
    local encrypted="$1"
    local decrypted="$2"

    python3 - "$encrypted" "$decrypted" "$pack_key" <<'PY'
import hashlib
import hmac
from pathlib import Path
import subprocess
import sys

source, destination, pack_key_hex = sys.argv[1:]
data = Path(source).read_bytes()
if len(data) < 64:
    raise SystemExit("encrypted Signal sticker object is too short")

ikm = bytes.fromhex(pack_key_hex)
info = b"Sticker Pack"
prk = hmac.new(bytes(hashlib.sha256().digest_size), ikm, hashlib.sha256).digest()
t1 = hmac.new(prk, info + b"\x01", hashlib.sha256).digest()
t2 = hmac.new(prk, t1 + info + b"\x02", hashlib.sha256).digest()
aes_key, hmac_key = (t1 + t2)[:32], (t1 + t2)[32:64]

iv = data[:16]
ciphertext = data[16:-32]
expected_mac = data[-32:]
if not ciphertext or len(ciphertext) % 16:
    raise SystemExit("invalid Signal sticker ciphertext length")
actual_mac = hmac.new(hmac_key, iv + ciphertext, hashlib.sha256).digest()
if not hmac.compare_digest(actual_mac, expected_mac):
    raise SystemExit("Signal sticker authentication failed (wrong pack key?)")

result = subprocess.run(
    ["openssl", "enc", "-d", "-aes-256-cbc",
     "-K", aes_key.hex(), "-iv", iv.hex()],
    input=ciphertext,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
)
if result.returncode:
    detail = result.stderr.decode("utf-8", "replace").strip()
    raise SystemExit(f"could not decrypt Signal sticker object: {detail}")
Path(destination).write_bytes(result.stdout)
PY
}

# Decode Signal's tiny Stickers.proto manifest without requiring the external
# protobuf Python package. Unknown protobuf fields are skipped for forwards
# compatibility.
parse_manifest() {
    local input="$1"
    local output="$2"

    python3 - "$input" "$output" "$pack_id" "$pack_key" <<'PY'
import json
from pathlib import Path
import sys

source, destination, pack_id, pack_key = sys.argv[1:]

def varint(data, offset):
    value = 0
    shift = 0
    while offset < len(data) and shift < 70:
        byte = data[offset]
        offset += 1
        value |= (byte & 0x7f) << shift
        if not byte & 0x80:
            return value, offset
        shift += 7
    raise ValueError("invalid protobuf varint")

def fields(data):
    offset = 0
    while offset < len(data):
        tag, offset = varint(data, offset)
        number, wire_type = tag >> 3, tag & 7
        if not number:
            raise ValueError("invalid protobuf field number")
        if wire_type == 0:
            value, offset = varint(data, offset)
        elif wire_type == 1:
            end = offset + 8
            value, offset = data[offset:end], end
        elif wire_type == 2:
            length, offset = varint(data, offset)
            end = offset + length
            value, offset = data[offset:end], end
        elif wire_type == 5:
            end = offset + 4
            value, offset = data[offset:end], end
        else:
            raise ValueError(f"unsupported protobuf wire type {wire_type}")
        if offset > len(data):
            raise ValueError("truncated protobuf field")
        yield number, wire_type, value

def sticker(data):
    result = {}
    for number, wire_type, value in fields(data):
        if number == 1 and wire_type == 0:
            result["id"] = value
        elif number == 2 and wire_type == 2:
            result["emoji"] = value.decode("utf-8")
    if "id" not in result:
        raise ValueError("sticker manifest entry has no id")
    return result

raw = Path(source).read_bytes()
pack = {
    "pack_id": pack_id,
    "pack_key": pack_key,
    "title": "",
    "author": "",
    "cover": None,
    "stickers": [],
}
try:
    for number, wire_type, value in fields(raw):
        if number == 1 and wire_type == 2:
            pack["title"] = value.decode("utf-8")
        elif number == 2 and wire_type == 2:
            pack["author"] = value.decode("utf-8")
        elif number == 3 and wire_type == 2:
            pack["cover"] = sticker(value)
        elif number == 4 and wire_type == 2:
            pack["stickers"].append(sticker(value))
except (UnicodeDecodeError, ValueError) as error:
    raise SystemExit(f"could not parse Signal sticker manifest: {error}")

if not pack["stickers"]:
    raise SystemExit("Signal sticker manifest contains no stickers")
Path(destination).write_text(
    json.dumps(pack, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
PY
}

inspect_image() {
    local path="$1"

    python3 - "$path" <<'PY'
from pathlib import Path
import sys

data = Path(sys.argv[1]).read_bytes()
animated = False
if data.startswith(b"\x89PNG\r\n\x1a\n"):
    extension = "png"
    animated = b"acTL" in data
elif data.startswith(b"RIFF") and data[8:12] == b"WEBP":
    extension = "webp"
    animated = b"ANIM" in data
elif data.startswith((b"GIF87a", b"GIF89a")):
    extension = "gif"
    animated = True
elif data.startswith(b"\xff\xd8\xff"):
    extension = "jpg"
else:
    raise SystemExit("unsupported image format in Signal sticker pack")
print(extension)
print("true" if animated else "false")
PY
}

download_sticker() {
    local sticker_id="$1"
    local relative_stem="$2"
    local encrypted="$work_dir/sticker-$sticker_id.encrypted"
    local decrypted="$work_dir/sticker-$sticker_id.decrypted"
    local inspection
    local extension

    download_encrypted \
        "$cdn_base/full/$sticker_id" \
        "$encrypted" \
        "Signal sticker $sticker_id"
    decrypt_file "$encrypted" "$decrypted"
    inspection="$(inspect_image "$decrypted")"
    extension="${inspection%%$'\n'*}"
    downloaded_animated="${inspection#*$'\n'}"
    downloaded_relative="$relative_stem.$extension"
    mv "$decrypted" "$pack_dir/$downloaded_relative"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    usage >&2
    exit 2
}

source_url="$1"
source_base="${source_url%%#*}"
source_base="${source_base%%\?*}"
source_base="${source_base%/}"
case "$source_base" in
    https://signal.art/addstickers|sgnl://addstickers) ;;
    *) die "expected a https://signal.art/addstickers#pack_id=...&pack_key=... URL" ;;
esac

parameters="${source_url#*#}"
if [ "$parameters" = "$source_url" ]; then
    parameters="${source_url#*\?}"
fi
parameters="${parameters#\?}"
pack_id=""
pack_key=""
IFS='&' read -r -a fields <<<"$parameters"
for field in "${fields[@]}"; do
    case "$field" in
        pack_id=*) pack_id="${field#pack_id=}" ;;
        pack_key=*) pack_key="${field#pack_key=}" ;;
    esac
done

[[ "$pack_id" =~ ^[[:xdigit:]]{32}$ ]] \
    || die "Signal pack_id must contain exactly 32 hexadecimal characters"
[[ "$pack_key" =~ ^[[:xdigit:]]{64}$ ]] \
    || die "Signal pack_key must contain exactly 64 hexadecimal characters"
pack_id="$(printf '%s' "$pack_id" | tr '[:upper:]' '[:lower:]')"
pack_key="$(printf '%s' "$pack_key" | tr '[:upper:]' '[:lower:]')"

require_command curl
require_command jq
require_command openssl
require_command python3
require_command zip

output="${2:-$pack_id.zip}"
output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
output="$output_dir/$(basename "$output")"
[ ! -d "$output" ] || die "output path is a directory: $output"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/parla-signal-stickers.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
pack_dir="$work_dir/$pack_id"
mkdir -p "$pack_dir/stickers"

canonical_url="https://signal.art/addstickers/#pack_id=$pack_id&pack_key=$pack_key"
cdn_base="https://cdn.signal.org/stickers/$pack_id"
encrypted_manifest="$work_dir/manifest.encrypted"
manifest="$work_dir/manifest.proto"

echo "Fetching Signal sticker pack $pack_id" >&2
download_encrypted "$cdn_base/manifest.proto" "$encrypted_manifest" \
    "Signal sticker manifest"
decrypt_file "$encrypted_manifest" "$manifest"
parse_manifest "$manifest" "$pack_dir/signal.json"

jq \
    --arg source_url "$canonical_url" \
    --arg downloaded_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    '{
        archive_version: 1,
        source: "signal",
        source_url: $source_url,
        downloaded_at: $downloaded_at,
        sticker_set: {
            name: .pack_id,
            title: .title,
            author: .author,
            sticker_type: "regular",
            thumbnail: .cover,
            stickers: .stickers
        }
    }' "$pack_dir/signal.json" > "$pack_dir/metadata.json"

sticker_count="$(jq -er '.stickers | length' "$pack_dir/signal.json")"
index=0
while [ "$index" -lt "$sticker_count" ]; do
    sticker_id="$(jq -er --argjson index "$index" '.stickers[$index].id' \
        "$pack_dir/signal.json")"
    printf -v stem 'stickers/%03d' "$((index + 1))"
    echo "Downloading sticker $((index + 1))/$sticker_count" >&2
    download_sticker "$sticker_id" "$stem"

    jq \
        --argjson index "$index" \
        --arg local_file "$downloaded_relative" \
        --argjson animated "$downloaded_animated" \
        '.sticker_set.stickers[$index] += {
            local_file: $local_file,
            is_animated: $animated,
            is_video: false,
            type: "regular"
        }' "$pack_dir/metadata.json" > "$work_dir/metadata.json"
    mv "$work_dir/metadata.json" "$pack_dir/metadata.json"
    index=$((index + 1))
done

cover_id="$(jq -r '.cover.id // empty' "$pack_dir/signal.json")"
if [ -n "$cover_id" ]; then
    echo "Downloading pack thumbnail" >&2
    download_sticker "$cover_id" "thumbnail"
    jq \
        --arg local_file "$downloaded_relative" \
        --argjson animated "$downloaded_animated" \
        '.sticker_set.thumbnail += {
            local_file: $local_file,
            is_animated: $animated,
            is_video: false
        }' "$pack_dir/metadata.json" > "$work_dir/metadata.json"
    mv "$work_dir/metadata.json" "$pack_dir/metadata.json"
fi

(cd "$work_dir" && zip -q -r archive.zip "$pack_id")
mv "$work_dir/archive.zip" "$output"
echo "$output"
