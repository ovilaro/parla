#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/stickers/convert.sh INPUT.zip [OUTPUT.zip]

Replace TGS files in a downloaded Telegram sticker-pack archive with
transparent GIF animations or static WebP/PNG images. The input is never
modified. VP9 WebM remains available as an option.

Environment:
  RLOTTIE_CONVERTER  Path to rlottie's lottie2gif (default: PATH or .tools)
  ANIMATED_FORMAT    Animated output: gif or webm (default: gif)
  ANIMATED_FPS       Maximum animated output FPS, 1-60 (default: 30)
  ANIMATED_SCALE     Animated dimensions multiplier, >0 through 1 (default: 1)
  WEBM_CRF           libvpx-vp9 quality, 0-63 (default: 32; lower is better)
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

absolute_file () {
    local path="$1"
    local directory
    directory="$(dirname "$path")"
    [ -d "$directory" ] || return 1
    directory="$(cd "$directory" && pwd)"
    printf '%s/%s\n' "$directory" "$(basename "$path")"
}

validate_archive_paths () {
    local entry
    while IFS= read -r entry; do
        case "$entry" in
            ""|/*|../*|*/../*|*/..|*\\*|?:/*)
                die "unsafe path in archive: $entry"
                ;;
        esac
    done < <(unzip -Z1 "$input")
}

render_background () {
    local json="$1"
    local directory="$2"
    local size="$3"
    local color="$4"

    mkdir -p "$directory"
    (
        cd "$directory"
        "$rlottie_converter" "$json" "$size" "$color" >/dev/null
    )
    rendered_gif="$directory/$(basename "$json").gif"
    [ -s "$rendered_gif" ] \
        || die "rlottie did not create the expected GIF for $(basename "$json")"
}

convert_tgs () {
    local source="$1"
    local destination_stem="$2"
    local render_dir="$3"
    local json="$render_dir/animation.json"
    local render_json="$json"
    local black_gif
    local white_gif
    local width
    local height
    local source_fps
    local target_fps
    local target_width
    local target_height
    local frames
    local json_bytes
    local animated

    mkdir -p "$render_dir"
    gzip -dc "$source" > "$json" \
        || die "could not decompress $(basename "$source")"

    json_bytes="$(wc -c < "$json" | tr -d '[:space:]')"
    [ "$json_bytes" -le "$max_json_bytes" ] \
        || die "decompressed TGS exceeds $max_json_bytes bytes: $(basename "$source")"

    jq -e '
        type == "object"
        and (.w | type == "number" and . > 0 and . <= 1024)
        and (.h | type == "number" and . > 0 and . <= 1024)
        and (.fr | type == "number" and . > 0 and . <= 120)
        and (.ip | type == "number")
        and (.op | type == "number")
        and (.op > .ip and (.op - .ip) <= 600)
        and (.layers | type == "array")
    ' "$json" >/dev/null || die "invalid or unsupported TGS JSON: $(basename "$source")"

    width="$(jq -er '.w | floor' "$json")"
    height="$(jq -er '.h | floor' "$json")"
    source_fps="$(jq -er '.fr' "$json")"
    frames="$(jq -er '(.op - .ip) | ceil' "$json")"
    target_fps="$(jq -nr \
        --argjson fps "$source_fps" \
        --argjson requested "$animated_fps" \
        '$fps | if . > $requested then $requested else . end')"

    animated="$(jq -r '
        . as $root
        | any(.. | objects; (.a? == 1 or .a? == true))
          or any(.layers[]?;
              ((.ip? // $root.ip) > $root.ip)
              or ((.op? // $root.op) < $root.op))
    ' "$json")"
    if [ "$animated" = "true" ]; then
        converted_extension="$animated_format"
        converted_target_format="$animated_format"
        destination="$destination_stem.$animated_format"
        target_width="$(jq -nr \
            --argjson size "$width" \
            --argjson scale "$animated_scale" \
            '[1, (($size * $scale) | floor)] | max')"
        target_height="$(jq -nr \
            --argjson size "$height" \
            --argjson scale "$animated_scale" \
            '[1, (($size * $scale) | floor)] | max')"
        if [ "$animated_format" = "webm" ]; then
            # yuva420p requires even dimensions.
            target_width=$((target_width < 2 ? 2 : target_width - target_width % 2))
            target_height=$((target_height < 2 ? 2 : target_height - target_height % 2))
        fi
    else
        converted_extension="$static_format"
        converted_target_format="$static_format"
        destination="$destination_stem.$static_format"
        target_width="$width"
        target_height="$height"
        render_json="$render_dir/static.json"
        jq '.op = (.ip + 1)' "$json" > "$render_json"
    fi

    render_background "$render_json" "$render_dir/black" \
        "${target_width}x${target_height}" "000000"
    black_gif="$rendered_gif"
    render_background "$render_json" "$render_dir/white" \
        "${target_width}x${target_height}" "ffffff"
    white_gif="$rendered_gif"

    alpha_filter="[0:v]format=rgb24,split=2[black_diff][black_color]; \
        [1:v]format=rgb24[white]; \
        [white][black_diff]blend=all_mode=difference,format=gray,negate[alpha]; \
        [black_color][alpha]alphamerge[premultiplied]; \
        [premultiplied]unpremultiply=inplace=1:planes=7"

    if [ "$animated" = "true" ] && [ "$animated_format" = "webm" ]; then
        ffmpeg -hide_banner -loglevel error -y \
            -r "$source_fps" -i "$black_gif" \
            -r "$source_fps" -i "$white_gif" \
            -filter_complex \
            "$alpha_filter,fps=$target_fps,format=yuva420p[out]" \
            -map "[out]" \
            -an \
            -c:v libvpx-vp9 \
            -pix_fmt yuva420p \
            -crf "$webm_crf" \
            -b:v 0 \
            -deadline good \
            -cpu-used 2 \
            -row-mt 1 \
            -auto-alt-ref 0 \
            -metadata:s:v:0 alpha_mode=1 \
            "$destination"
    elif [ "$animated" = "true" ]; then
        ffmpeg -hide_banner -loglevel error -y \
            -r "$source_fps" -i "$black_gif" \
            -r "$source_fps" -i "$white_gif" \
            -filter_complex \
            "$alpha_filter,fps=$target_fps,format=rgba,split[gif][palette_input]; \
                [palette_input]palettegen=stats_mode=diff:reserve_transparent=1:transparency_color=000000[palette]; \
                [gif][palette]paletteuse=diff_mode=rectangle:alpha_threshold=128:dither=sierra2_4a[out]" \
            -map "[out]" \
            -an \
            -loop 0 \
            "$destination"
    else
        static_png="$render_dir/static.png"
        ffmpeg -hide_banner -loglevel error -y \
            -i "$black_gif" \
            -i "$white_gif" \
            -filter_complex "$alpha_filter,format=rgba[out]" \
            -map "[out]" \
            -frames:v 1 \
            -c:v png \
            "$static_png"
        if [ "$static_format" = "webp" ]; then
            cwebp -quiet -lossless -exact -z 9 "$static_png" -o "$destination"
        else
            mv "$static_png" "$destination"
        fi
    fi

    [ -s "$destination" ] || die "FFmpeg produced an empty output file"
    ffmpeg -hide_banner -loglevel error -i "$destination" -f null - \
        || die "FFmpeg could not validate $(basename "$destination")"

    converted_source_fps="$source_fps"
    converted_target_fps="$target_fps"
    converted_frames="$frames"
    converted_source_width="$width"
    converted_source_height="$height"
    converted_target_width="$target_width"
    converted_target_height="$target_height"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    usage
    exit 0
fi

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || {
    usage >&2
    exit 2
}

require_command unzip
require_command zip
require_command gzip
require_command jq
require_command ffmpeg
require_command find

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -n "${RLOTTIE_CONVERTER:-}" ]; then
    rlottie_converter="$RLOTTIE_CONVERTER"
elif command -v lottie2gif >/dev/null 2>&1; then
    rlottie_converter="lottie2gif"
elif [ -x "$script_dir/.tools/bin/lottie2gif" ]; then
    rlottie_converter="$script_dir/.tools/bin/lottie2gif"
else
    die "lottie2gif not found; run: make -C $script_dir lottie2gif"
fi
require_command "$rlottie_converter"
case "$rlottie_converter" in
    */*)
        rlottie_converter="$(absolute_file "$rlottie_converter")" \
            || die "could not resolve RLOTTIE_CONVERTER"
        ;;
    *)
        rlottie_converter="$(command -v "$rlottie_converter")"
        ;;
esac

animated_format="${ANIMATED_FORMAT:-gif}"
case "$animated_format" in
    gif|webm) ;;
    *) die "ANIMATED_FORMAT must be gif or webm" ;;
esac
animated_fps="${ANIMATED_FPS:-30}"
[[ "$animated_fps" =~ ^[1-9][0-9]*$ ]] \
    && [ "$animated_fps" -le 60 ] \
    || die "ANIMATED_FPS must be an integer from 1 to 60"
animated_scale="${ANIMATED_SCALE:-1}"
animated_scale="$(jq -enr --arg value "$animated_scale" \
    '($value | tonumber) as $scale
     | select($scale > 0 and $scale <= 1)
     | $scale')" \
    || die "ANIMATED_SCALE must be a number greater than 0 and at most 1"
[ -n "$animated_scale" ] \
    || die "ANIMATED_SCALE must be a number greater than 0 and at most 1"
webm_crf="${WEBM_CRF:-32}"
if [ "$animated_format" = "webm" ]; then
    [[ "$webm_crf" =~ ^[0-9]+$ ]] \
        && [ "$webm_crf" -le 63 ] \
        || die "WEBM_CRF must be an integer from 0 to 63"
fi
max_json_bytes="${TGS_MAX_JSON_BYTES:-10485760}"
[[ "$max_json_bytes" =~ ^[1-9][0-9]*$ ]] \
    || die "TGS_MAX_JSON_BYTES must be a positive integer"

if [ "$animated_format" = "webm" ] \
        && ! ffmpeg -hide_banner -encoders 2>/dev/null \
            | grep -q '[[:space:]]libvpx-vp9[[:space:]]'; then
    die "FFmpeg was built without the libvpx-vp9 encoder"
fi
if command -v cwebp >/dev/null 2>&1; then
    static_format="webp"
else
    static_format="png"
fi

input="$(absolute_file "$1")" || die "input directory does not exist"
[ -f "$input" ] || die "input archive not found: $input"

if [ "$#" -eq 2 ]; then
    output_path="$2"
else
    input_name="$(basename "$input")"
    case "$input_name" in
        *.zip|*.ZIP) input_name="${input_name%.*}" ;;
    esac
    output_path="$(dirname "$input")/$input_name-converted.zip"
fi

output_dir="$(dirname "$output_path")"
mkdir -p "$output_dir"
output="$(absolute_file "$output_path")"
[ "$output" != "$input" ] || die "output must differ from the input archive"
[ ! -d "$output" ] || die "output path is a directory: $output"

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/parla-sticker-convert.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT
extract_dir="$work_dir/archive"
mkdir -p "$extract_dir"

validate_archive_paths
unzip -q "$input" -d "$extract_dir"
if find "$extract_dir" -type l -print -quit | grep -q .; then
    die "archive contains symbolic links"
fi

metadata_count="$(find "$extract_dir" -type f -name metadata.json | wc -l | tr -d '[:space:]')"
[ "$metadata_count" -eq 1 ] \
    || die "expected exactly one metadata.json in the archive"
metadata="$(find "$extract_dir" -type f -name metadata.json -print -quit)"
pack_dir="$(dirname "$metadata")"
jq -e '.sticker_set.stickers | type == "array"' "$metadata" >/dev/null \
    || die "metadata.json is not a Parla sticker-pack manifest"

converted_at="$(date -u +'%Y-%m-%dT%H:%M:%SZ')"
converted_count=0
gif_count=0
webm_count=0
webp_count=0
png_count=0
# Read the NUL-delimited file list from fd 3. Renderers and encoders may read
# stdin, which would otherwise consume bytes from the next filename.
while IFS= read -r -d '' tgs_file <&3; do
    relative="${tgs_file#"$pack_dir"/}"
    destination_stem="$pack_dir/${relative%.*}"
    render_dir="$work_dir/render-$converted_count"

    echo "Converting $relative" >&2
    convert_tgs "$tgs_file" "$destination_stem" "$render_dir"
    converted_relative="${relative%.*}.$converted_extension"
    rm -f "$tgs_file"

    if [ "$converted_target_format" = "gif" ]; then
        gif_count=$((gif_count + 1))
    elif [ "$converted_target_format" = "webm" ]; then
        webm_count=$((webm_count + 1))
    elif [ "$converted_target_format" = "webp" ]; then
        webp_count=$((webp_count + 1))
    else
        png_count=$((png_count + 1))
    fi

    jq \
        --arg old "$relative" \
        --arg new "$converted_relative" \
        --arg target "$converted_target_format" \
        --arg converted_at "$converted_at" \
        --arg source_fps "$converted_source_fps" \
        --arg target_fps "$converted_target_fps" \
        --arg frames "$converted_frames" \
        --arg source_width "$converted_source_width" \
        --arg source_height "$converted_source_height" \
        --arg target_width "$converted_target_width" \
        --arg target_height "$converted_target_height" \
        '
        def converted:
            .local_file = $new
            | .width = ($target_width | tonumber)
            | .height = ($target_height | tonumber)
            | .is_animated = ($target == "gif")
            | .is_video = ($target == "webm")
            | .conversion = {
                source_format: "tgs",
                target_format: $target,
                source_local_file: $old,
                renderer: "rlottie/lottie2gif",
                encoder: (if $target == "gif"
                          then "ffmpeg/gif"
                          elif $target == "webm"
                          then "ffmpeg/libvpx-vp9"
                          elif $target == "webp"
                          then "cwebp/lossless"
                          else "ffmpeg/png" end),
                source_fps: ($source_fps | tonumber),
                target_fps: ($target_fps | tonumber),
                source_frames: ($frames | tonumber),
                source_width: ($source_width | tonumber),
                source_height: ($source_height | tonumber),
                target_width: ($target_width | tonumber),
                target_height: ($target_height | tonumber),
                converted_at: $converted_at
            };
        .sticker_set.stickers |= map(
            if .local_file == $old then converted else . end
        )
        | if .sticker_set.thumbnail.local_file? == $old
          then .sticker_set.thumbnail |= converted
          else .
          end
        ' "$metadata" > "$work_dir/metadata.json"
    mv "$work_dir/metadata.json" "$metadata"

    converted_count=$((converted_count + 1))
done 3< <(find "$pack_dir" -type f -iname '*.tgs' -print0)

[ "$converted_count" -gt 0 ] || die "archive contains no TGS files"

jq \
    --arg converted_at "$converted_at" \
    --argjson count "$converted_count" \
    --argjson gif_count "$gif_count" \
    --argjson webm_count "$webm_count" \
    --argjson webp_count "$webp_count" \
    --argjson png_count "$png_count" \
    --arg crf "$webm_crf" \
    --arg animated_format "$animated_format" \
    --argjson animated_fps "$animated_fps" \
    --argjson animated_scale "$animated_scale" \
    '.conversions = ((.conversions // []) + [{
        source_format: "tgs",
        target_formats: {
            gif: $gif_count,
            webm: $webm_count,
            webp: $webp_count,
            png: $png_count
        },
        count: $count,
        renderer: "rlottie/lottie2gif",
        encoders: {
            gif: (if $gif_count > 0 then "ffmpeg/gif" else null end),
            webm: (if $webm_count > 0 then "ffmpeg/libvpx-vp9" else null end),
            webp: (if $webp_count > 0 then "cwebp/lossless" else null end),
            png: (if $png_count > 0 then "ffmpeg/png" else null end)
        },
        webm_crf: (if $webm_count > 0 then ($crf | tonumber) else null end),
        settings: {
            animated_format: $animated_format,
            animated_fps: $animated_fps,
            animated_scale: $animated_scale
        },
        converted_at: $converted_at
    }])' "$metadata" > "$work_dir/metadata.json"
mv "$work_dir/metadata.json" "$metadata"

(cd "$extract_dir" && zip -q -r "$work_dir/converted.zip" .)
mv "$work_dir/converted.zip" "$output"
echo "$output"
