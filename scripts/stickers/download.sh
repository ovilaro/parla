#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: TELEGRAM_BOT_TOKEN=... scripts/stickers/download.sh URL [OUTPUT.zip]

Download a Telegram sticker pack and its metadata into a zip archive.

Arguments:
  URL         A https://t.me/addstickers/<pack-name> URL
  OUTPUT.zip  Archive path (default: <pack-name>.zip)
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

api_call() {
    local method="$1"
    local output="$2"
    shift 2

    if ! curl -sS \
            --retry 3 \
            --retry-delay 1 \
            --connect-timeout 20 \
            --get \
            "$api_base/$method" \
            "$@" \
            --output "$output"; then
        die "could not reach the Telegram API"
    fi

    if ! jq -e '.ok == true' "$output" >/dev/null 2>&1; then
        local description
        description="$(jq -r '.description // "Telegram API request failed"' "$output" 2>/dev/null || true)"
        [ -n "$description" ] || description="Telegram API request failed"
        die "$description"
    fi
}

download_file() {
    local file_id="$1"
    local relative_stem="$2"
    local fallback_extension="$3"
    local response="$work_dir/get-file.json"
    local extension
    local file_path

    api_call getFile "$response" --data-urlencode "file_id=$file_id"
    file_path="$(jq -er '.result.file_path' "$response")"
    extension="${file_path##*.}"
    if [ "$extension" = "$file_path" ] || [[ ! "$extension" =~ ^[A-Za-z0-9]{1,8}$ ]]; then
        extension="$fallback_extension"
    fi
    extension="$(printf '%s' "$extension" | tr '[:upper:]' '[:lower:]')"

    downloaded_relative="$relative_stem.$extension"
    downloaded_file_json="$(jq -c '.result' "$response")"
    curl -fsS \
        --retry 3 \
        --retry-delay 1 \
        --connect-timeout 20 \
        "$file_base/$file_path" \
        --output "$pack_dir/$downloaded_relative"
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
clean_url="${source_url%%\?*}"
clean_url="${clean_url%%\#*}"
clean_url="${clean_url%/}"

case "$clean_url" in
    https://t.me/addstickers/*)
        pack_name="${clean_url#https://t.me/addstickers/}"
        ;;
    https://telegram.me/addstickers/*)
        pack_name="${clean_url#https://telegram.me/addstickers/}"
        ;;
    *)
        die "expected a https://t.me/addstickers/<pack-name> URL"
        ;;
esac

[[ "$pack_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,63}$ ]] \
    || die "invalid Telegram sticker pack name: $pack_name"

[ -n "${TELEGRAM_BOT_TOKEN:-}" ] \
    || die "TELEGRAM_BOT_TOKEN is not set (see scripts/stickers/README.md)"

require_command curl
require_command jq
require_command zip

output="${2:-$pack_name.zip}"
output_dir="$(dirname "$output")"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
output="$output_dir/$(basename "$output")"
[ ! -d "$output" ] || die "output path is a directory: $output"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/parla-stickers.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
pack_dir="$work_dir/$pack_name"
mkdir -p "$pack_dir/stickers"

api_base="https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN"
file_base="https://api.telegram.org/file/bot$TELEGRAM_BOT_TOKEN"
set_response="$work_dir/get-sticker-set.json"
canonical_url="https://t.me/addstickers/$pack_name"

echo "Fetching $canonical_url" >&2
api_call getStickerSet "$set_response" --data-urlencode "name=$pack_name"

jq '.result' "$set_response" > "$pack_dir/telegram.json"
jq \
    --arg source_url "$canonical_url" \
    --arg downloaded_at "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" \
    '{
        archive_version: 1,
        source_url: $source_url,
        downloaded_at: $downloaded_at,
        sticker_set: .result
    }' "$set_response" > "$pack_dir/metadata.json"

sticker_count="$(jq -er '.result.stickers | length' "$set_response")"
index=0
while [ "$index" -lt "$sticker_count" ]; do
    sticker="$(jq -c --argjson index "$index" '.result.stickers[$index]' "$set_response")"
    file_id="$(jq -er '.file_id' <<<"$sticker")"

    if jq -e '.is_animated == true' <<<"$sticker" >/dev/null; then
        fallback_extension="tgs"
    elif jq -e '.is_video == true' <<<"$sticker" >/dev/null; then
        fallback_extension="webm"
    else
        fallback_extension="webp"
    fi

    printf -v stem 'stickers/%03d' "$((index + 1))"
    echo "Downloading sticker $((index + 1))/$sticker_count" >&2
    download_file "$file_id" "$stem" "$fallback_extension"

    jq \
        --argjson index "$index" \
        --arg local_file "$downloaded_relative" \
        --argjson telegram_file "$downloaded_file_json" \
        '.sticker_set.stickers[$index] += {
            local_file: $local_file,
            telegram_file: $telegram_file
        }' "$pack_dir/metadata.json" > "$work_dir/metadata.json"
    mv "$work_dir/metadata.json" "$pack_dir/metadata.json"

    index=$((index + 1))
done

thumbnail_id="$(jq -r '.result.thumbnail.file_id // empty' "$set_response")"
if [ -n "$thumbnail_id" ]; then
    echo "Downloading pack thumbnail" >&2
    download_file "$thumbnail_id" "thumbnail" "webp"
    jq \
        --arg local_file "$downloaded_relative" \
        --argjson telegram_file "$downloaded_file_json" \
        '.sticker_set.thumbnail += {
            local_file: $local_file,
            telegram_file: $telegram_file
        }' "$pack_dir/metadata.json" > "$work_dir/metadata.json"
    mv "$work_dir/metadata.json" "$pack_dir/metadata.json"
fi

(cd "$work_dir" && zip -q -r archive.zip "$pack_name")
mv "$work_dir/archive.zip" "$output"
echo "$output"
