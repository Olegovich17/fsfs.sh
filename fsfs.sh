#!/usr/bin/env bash

DRY_RUN=0
DELETE_ORIGINAL=0
SKIP_EXISTING=0
OUT_DIR_NAME="splitted"
TARGET_DIR=""
DEPS=(cuetools shntool flac ffmpeg iconv uchardet)

print_header() {
    cat << EOF

    ██████             ██████                     █████     
   ███░░███           ███░░███                   ░░███      
  ░███ ░░░   █████   ░███ ░░░   █████      █████  ░███████  
 ███████    ███░░   ███████    ███░░      ███░░   ░███░░███ 
░░░███░    ░░█████ ░░░███░    ░░█████    ░░█████  ░███ ░███ 
  ░███      ░░░░███  ░███      ░░░░███    ░░░░███ ░███ ░███ 
  █████     ██████   █████     ██████  ██ ██████  ████ █████
 ░░░░░     ░░░░░░   ░░░░░     ░░░░░░  ░░ ░░░░░░  ░░░░ ░░░░░ 

EOF
}

print_header

show_help() {
    cat << EOF
fsfs.sh (fast strong flac splitter)
Usage: $0 [FLAGS] [ TARGET_DIRECTORY ]

FLAGS:
  -h, --help            Show this help message.
  -d, --dry-run         Check mode without making changes.
  -s, --skip-existing   Skip albums if the splitted folder already contains .flac files.
  -k, --delete-original Delete original audio and .cue file after successful splitting.
  -i, --install-deps    Install dependencies.
  -r, --remove-deps     Remove dependencies.
EOF
    exit 0
}

check_root() {
    if [ "$EUID" -ne 0 ]; then
        if command -v sudo &>/dev/null; then SUDO="sudo"; else echo "[!] Error: Root or sudo privileges required."; exit 1; fi
    else SUDO=""; fi
}

detect_pm() {
    if command -v apt-get &>/dev/null; then PM="apt-get"
    elif command -v apk &>/dev/null; then PM="apk"
    elif command -v dnf &>/dev/null; then PM="dnf"
    elif command -v pacman &>/dev/null; then PM="pacman"
    elif command -v zypper &>/dev/null; then PM="zypper"
    else echo "[!] Error: Could not detect the package manager."; exit 1; fi
}

install_dependencies() {
    echo "=== Installing Dependencies ==="
    check_root; detect_pm
    case "$PM" in
        apt-get) $SUDO apt-get update -qq && $SUDO apt-get install --no-install-recommends -y "${DEPS[@]}" ;;
        apk)     $SUDO apk add --no-cache "${DEPS[@]}" ;;
        dnf)     $SUDO dnf install -y "${DEPS[@]}" ;;
        pacman)  $SUDO pacman -Sy --noconfirm "${DEPS[@]}" ;;
        zypper)  $SUDO zypper install -y "${DEPS[@]}" ;;
    esac
    exit 0
}

remove_dependencies() {
    echo "=== Removing Dependencies ==="
    check_root; detect_pm
    case "$PM" in
        apt-get) $SUDO apt-get purge -y "${DEPS[@]}" && $SUDO apt-get autoremove --purge -y ;;
        apk)     $SUDO apk del "${DEPS[@]}" ;;
        dnf)     $SUDO dnf remove -y "${DEPS[@]}" ;;
        pacman)  $SUDO pacman -Rns --noconfirm "${DEPS[@]}" ;;
        zypper)  $SUDO zypper remove -y "${DEPS[@]}" ;;
    esac
    exit 0
}

cue_to_seconds() {
    local time_str="$1"
    time_str="${time_str//./:}"
    local m s f
    IFS=':' read -r m s f <<< "$time_str"
    m=$((10#${m:-0}))
    s=$((10#${s:-0}))
    f=$((10#${f:-0}))
    local ms=$((1000 * f / 75))
    printf "%d.%03d" "$((m * 60 + s))" "$ms"
}

convert_to_utf8() {
    local src="$1"
    local dst="$2"

    if command -v uchardet &>/dev/null; then
        local enc
        enc=$(uchardet "$src" 2>/dev/null)
        if [ -n "$enc" ] && iconv -f "$enc" -t UTF-8 "$src" > "$dst" 2>/dev/null; then
            return 0
        fi
    fi

    if iconv -f UTF-8 -t UTF-8 "$src" &>/dev/null; then
        cp "$src" "$dst"
        return 0
    fi

    for enc in CP1251 CP866 ISO-8859-1 SHIFT-JIS GBK; do
        if iconv -f "$enc" -t UTF-8 "$src" > "$dst" 2>/dev/null; then
            return 0
        fi
    done

    iconv -c -f CP1251 -t UTF-8 "$src" > "$dst" 2>/dev/null || cp "$src" "$dst"
}

extract_cue_tag() {
    local pattern="$1"
    local file="$2"
    grep -i -E "^[[:space:]]*${pattern}" "$file" | head -n 1 | sed -E 's/^[[:space:]]*'"${pattern}"'[[:space:]]+"?([^"]*)"?/\1/' | tr -d '\r'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help) show_help ;;
        -i|--install-deps) install_dependencies ;;
        -r|--remove-deps) remove_dependencies ;;
        -d|--dry-run) DRY_RUN=1; shift ;;
        -s|--skip-existing) SKIP_EXISTING=1; shift ;;
        -k|--delete-original) DELETE_ORIGINAL=1; shift ;;
        -*) echo "[!] Error: Unknown flag '$1'"; exit 1 ;;
        *) TARGET_DIR="$1"; shift ;;
    esac
done

TARGET_DIR="$(realpath "${TARGET_DIR:-.}" )"

if [ "$DRY_RUN" -eq 0 ]; then
    missing_cmds=()
    for cmd in cuebreakpoints shnsplit flac iconv ffmpeg mktemp realpath metaflac awk; do
        if ! command -v "$cmd" &>/dev/null; then missing_cmds+=("$cmd"); fi
    done
    if [ ${#missing_cmds[@]} -gt 0 ]; then
        echo "[!] Missing tools: ${missing_cmds[*]}"
        echo "Run: $0 --install-deps"
        exit 1
    fi
fi

FOUND_COUNT=0

while IFS= read -r -d '' cue_file; do
    if [[ "$cue_file" =~ /"${OUT_DIR_NAME}"/ ]]; then continue; fi

    dir=$(dirname "$cue_file")
    cue_name=$(basename "$cue_file")

    TMP_DIR_PRE=$(mktemp -d -t flac_pre_XXXXXX)
    tmp_raw_pre="$TMP_DIR_PRE/raw.cue"
    convert_to_utf8 "$cue_file" "$tmp_raw_pre"

    audio_file=""

    candidate_1="${cue_name%.*}"
    if [ -f "$dir/$candidate_1" ] && [[ "$candidate_1" =~ \.(flac|FLAC)$ ]]; then
        audio_file="$dir/$candidate_1"
    fi

    if [ -z "$audio_file" ]; then
        base_no_ext="${cue_name%.*}"
        for ext in flac FLAC Flac; do
            if [ -f "$dir/${base_no_ext}.${ext}" ]; then
                audio_file="$dir/${base_no_ext}.${ext}"
                break
            fi
        done
    fi

    if [ -z "$audio_file" ]; then
        cue_target=$(extract_cue_tag "FILE" "$tmp_raw_pre" | awk '{print $1}')
        if [ -n "$cue_target" ] && [ -f "$dir/$cue_target" ] && [[ "$cue_target" =~ \.(flac|FLAC)$ ]]; then
            audio_file="$dir/$cue_target"
        fi
    fi

    rm -rf "$TMP_DIR_PRE"

    if [ -z "$audio_file" ]; then continue; fi

    flac_name=$(basename "$audio_file")
    rel_dir="${dir#"$TARGET_DIR"}"
    rel_dir="${rel_dir:-/}"

    echo ""
    echo "=================================================="
    echo "Match found:"
    echo "  Folder: $rel_dir"
    echo "  CUE   : $cue_name"
    echo "  AUDIO : $flac_name"

    if [ "$SKIP_EXISTING" -eq 1 ] && [ -d "$dir/$OUT_DIR_NAME" ] && find "$dir/$OUT_DIR_NAME" -maxdepth 1 -iname "*.flac" -print -quit | grep -q .; then
        echo "  [↪] Folder '$OUT_DIR_NAME' already contains files. Skipping."
        continue
    fi

    ((FOUND_COUNT++))
    [ "$DRY_RUN" -eq 1 ] && continue

    (
        cd "$dir" || exit 1

        TMP_DIR=$(mktemp -d -t flac_split_XXXXXX)
        trap 'rm -rf "$TMP_DIR"' EXIT

        tmp_raw="$TMP_DIR/raw.cue"
        tmp_clean="$TMP_DIR/clean.cue"
        tmp_work="$TMP_DIR/work.cue"
        output_path="$OUT_DIR_NAME"
        mkdir -p "$output_path"

        src_cue="$(basename "$cue_file")"

        convert_to_utf8 "$src_cue" "$tmp_raw"

        tr -d '\r' < "$tmp_raw" | sed '1s/^\xEF\xBB\xBF//' | sed 's/[“”«»]/"/g' > "$tmp_clean"
        grep -i -E '^[[:space:]]*(FILE|TRACK|INDEX|TITLE|PERFORMER|SONGWRITER|COMPOSER|FLAGS|REM DATE|REM YEAR|REM GENRE)' "$tmp_clean" > "$tmp_work"

        awk -v fn="$flac_name" '
            /^[[:space:]]*FILE/ { print "FILE \"" fn "\" WAVE"; next }
            { print }
        ' "$tmp_work" > "$tmp_work.tmp" && mv "$tmp_work.tmp" "$tmp_work"

        if ! grep -q -i "^FILE" "$tmp_work"; then
            sed -i '1i FILE "'"$flac_name"'" WAVE' "$tmp_work"
        fi

        bits=$(metaflac --show-bps "./$flac_name" 2>/dev/null)
        split_success=0

        if [ -n "$bits" ] && [ "$bits" -gt 16 ] 2>/dev/null; then
            echo "-> Hi-Res FLAC (${bits}-bit) detected. Splitting via ffmpeg..."
            mapfile -t breakpoints < <(cuebreakpoints "$tmp_work")
            breakpoints+=("end")

            track_idx=1
            start_time="00:00:00"

            for bp in "${breakpoints[@]}"; do
                formatted_num=$(printf "%02d" $track_idx)
                out_track="$output_path/track${formatted_num}.flac"
                start_sec=$(cue_to_seconds "$start_time")

                if [ "$bp" == "end" ]; then
                    echo "    [+] Splitting track $formatted_num ($start_time -> end)"
                    ffmpeg -hide_banner -loglevel error -y -ss "$start_sec" -i "$flac_name" -map_metadata -1 -c:a flac "$out_track"
                else
                    echo "    [+] Splitting track $formatted_num ($start_time -> $bp)"
                    end_sec=$(cue_to_seconds "$bp")
                    duration=$(awk "BEGIN {print $end_sec - $start_sec}")
                    ffmpeg -hide_banner -loglevel error -y -ss "$start_sec" -i "$flac_name" -t "$duration" -map_metadata -1 -c:a flac "$out_track"
                    start_time="$bp"
                fi
                ((track_idx++))
            done
            split_success=1
        else
            echo "-> Standard 16-bit FLAC. Splitting via shnsplit..."
            cuebreakpoints "$tmp_work" | shnsplit -O always -a track -n %02d -o flac -d "$output_path" "$flac_name"
            [ $? -eq 0 ] && split_success=1
        fi

        if [ "$split_success" -eq 1 ]; then
            echo "-> Reading tags and renaming tracks..."

            shopt -s nullglob
            tracks=("$output_path"/track*.flac)
            
            album_title=$(extract_cue_tag "TITLE" "$tmp_work")
            album_artist=$(extract_cue_tag "PERFORMER" "$tmp_work")
            album_date=$(extract_cue_tag "REM DATE" "$tmp_work")
            [ -z "$album_date" ] && album_date=$(extract_cue_tag "REM YEAR" "$tmp_work")
            album_genre=$(extract_cue_tag "REM GENRE" "$tmp_work")

            for track in "${tracks[@]}"; do
                raw_num=$(echo "$(basename "$track")" | sed 's/[^0-9]//g')
                num_int=$((10#$raw_num))
                formatted_num=$(printf "%02d" "$num_int")

                track_block=$(awk -v trk="$formatted_num" '
                    BEGIN { RS="TRACK "; FS="\n" }
                    $1 ~ "^" trk { print $0 }
                ' "$tmp_work")

                t_title=$(echo "$track_block" | grep -i '^[[:space:]]*TITLE' | head -n 1 | sed -E 's/^[[:space:]]*TITLE[[:space:]]+"?([^"]*)"?/\1/' | tr -d '\r')
                t_artist=$(echo "$track_block" | grep -i '^[[:space:]]*PERFORMER' | head -n 1 | sed -E 's/^[[:space:]]*PERFORMER[[:space:]]+"?([^"]*)"?/\1/' | tr -d '\r')

                [ -z "$t_artist" ] && t_artist="$album_artist"

                metaflac --remove-all-tags "$track"
                [ -n "$t_title" ] && metaflac --set-tag="TITLE=$t_title" "$track"
                [ -n "$t_artist" ] && metaflac --set-tag="ARTIST=$t_artist" "$track"
                [ -n "$album_title" ] && metaflac --set-tag="ALBUM=$album_title" "$track"
                [ -n "$album_artist" ] && metaflac --set-tag="ALBUMARTIST=$album_artist" "$track"
                [ -n "$album_date" ] && metaflac --set-tag="DATE=$album_date" "$track"
                [ -n "$album_genre" ] && metaflac --set-tag="GENRE=$album_genre" "$track"
                metaflac --set-tag="TRACKNUMBER=$num_int" "$track"

                if [ -n "$t_artist" ] && [ -n "$t_title" ]; then
                    base_new_name="${formatted_num} - ${t_artist} - ${t_title}"
                elif [ -n "$t_title" ]; then
                    base_new_name="${formatted_num} - ${t_title}"
                else
                    base_new_name="Track_${formatted_num}"
                fi

                safe_name=$(echo "$base_new_name" | sed -E -e 's/[/\\:*?"<>|]//g' -e 's/[[:space:]]+/ /g' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' | cut -c 1-120)
                [ -z "$safe_name" ] && safe_name="Track_${formatted_num}"

                mv "$track" "$output_path/${safe_name}.flac"
            done
            shopt -u nullglob

            if [ "$DELETE_ORIGINAL" -eq 1 ]; then
                echo "-> Cleaning up originals and moving files..."
                shopt -s nullglob
                out_files=("$output_path"/*.flac)

                if [ ${#out_files[@]} -gt 0 ]; then
                    rm -f "$flac_name" "$src_cue"
                    
                    for f in "${out_files[@]}"; do
                        mv "$f" .
                    done

                    rmdir "$output_path" 2>/dev/null || true
                fi
                shopt -u nullglob
            fi

            echo "[✓] Album successfully split and processed!"
        else
            echo "[✗] Error processing $flac_name"
            rm -rf "$output_path"
        fi
    )

done < <(find "$TARGET_DIR" -type f -iname "*.cue" -print0)

echo ""
echo "=================================================="
if [ "$DRY_RUN" -eq 1 ]; then
    echo "DRY-RUN SUMMARY: Found $FOUND_COUNT matching CUE + FLAC pairs."
fi
