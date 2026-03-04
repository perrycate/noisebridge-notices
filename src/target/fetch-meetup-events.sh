#!/usr/bin/env bash
#
# Fetches upcoming Meetup events (next 7 days) for a given group,
# including featured images and metadata.
#
# Usage: fetch-meetup-events.sh <group-urlname> [output-dir]
#
# Output:
#   output-dir/events.json   - Array of event objects
#   output-dir/event-N.jpeg  - Featured image for each event (if available)

set -euo pipefail

GROUP="${1:?Usage: fetch-meetup-events.sh <group-urlname> [output-dir]}"
OUTDIR="${2:-./events}"

mkdir -p "$OUTDIR"

ICAL_URL="https://www.meetup.com/${GROUP}/events/ical/"

NOW=$(date +%s)
WEEK_LATER=$(( NOW + 7 * 24 * 60 * 60 ))

echo "Fetching iCal feed from $ICAL_URL ..."
ICAL_DATA=$(curl -s -f "$ICAL_URL") || {
    echo "Error: Failed to fetch iCal feed for group '$GROUP'" >&2
    exit 1
}

# Unfold iCal line continuations (lines starting with space are continuations).
ICAL_DATA=$(echo "$ICAL_DATA" | sed ':a;N;$!ba;s/\n //g')

# Parse events from iCal data.
# Extracts DTSTART, SUMMARY, URL, DESCRIPTION for each VEVENT block.
parse_events() {
    local in_event=0
    local dtstart="" summary="" url="" description=""

    while IFS= read -r line; do
        # Strip carriage returns
        line="${line%$'\r'}"

        case "$line" in
            "BEGIN:VEVENT")
                in_event=1
                dtstart=""
                summary=""
                url=""
                description=""
                ;;
            "END:VEVENT")
                if [ "$in_event" -eq 1 ] && [ -n "$dtstart" ]; then
                    printf '%s\t%s\t%s\t%s\n' "$dtstart" "$summary" "$url" "$description"
                fi
                in_event=0
                ;;
            DTSTART*)
                if [ "$in_event" -eq 1 ]; then
                    # Handle both DTSTART;TZID=...:VALUE and DTSTART:VALUE formats
                    dtstart="${line#*:}"
                fi
                ;;
            SUMMARY*)
                if [ "$in_event" -eq 1 ]; then
                    summary="${line#*:}"
                fi
                ;;
            URL*)
                if [ "$in_event" -eq 1 ]; then
                    url="${line#*:}"
                    # URL field uses URL;VALUE=URI:https://... format
                    # The above strips up to first colon, leaving "//..."
                    # Need to re-add the scheme
                    if [[ "$url" == //* ]]; then
                        url="https:$url"
                    fi
                fi
                ;;
            DESCRIPTION*)
                if [ "$in_event" -eq 1 ]; then
                    description="${line#*:}"
                    # Truncate to ~200 chars
                    description="${description:0:200}"
                fi
                ;;
        esac
    done <<< "$ICAL_DATA"
}

# Convert iCal datetime (e.g. 20260304T180000) to epoch seconds.
ical_to_epoch() {
    local dt="$1"
    # Format: YYYYMMDDTHHMMSS
    local year="${dt:0:4}"
    local month="${dt:4:2}"
    local day="${dt:6:2}"
    local hour="${dt:9:2}"
    local min="${dt:11:2}"
    local sec="${dt:13:2}"
    date -d "${year}-${month}-${day} ${hour}:${min}:${sec}" +%s 2>/dev/null || echo 0
}

# Scrape the featured image URL from a Meetup event page.
scrape_image_url() {
    local event_url="$1"
    local html
    html=$(curl -s -f "$event_url" 2>/dev/null) || return 1

    # Look for highres image URL in the page
    echo "$html" | grep -oP 'https://secure\.meetupstatic\.com/photos/event/[^"]+/highres_[0-9]+\.jpeg' | head -1
}

# JSON-escape a string (handles quotes, backslashes, newlines).
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/}"
    # Unescape iCal escapes
    s="${s//\\n/\\n}"
    s="${s//\\,/,}"
    s="${s//\\;/;}"
    echo "$s"
}

echo "Parsing events..."
EVENTS=$(parse_events)

EVENT_COUNT=0
JSON_ENTRIES=""

while IFS=$'\t' read -r dtstart summary url description; do
    [ -z "$dtstart" ] && continue

    event_epoch=$(ical_to_epoch "$dtstart")
    [ "$event_epoch" -eq 0 ] && continue

    # Filter: only events in the next 7 days
    if [ "$event_epoch" -lt "$NOW" ] || [ "$event_epoch" -gt "$WEEK_LATER" ]; then
        continue
    fi

    EVENT_COUNT=$((EVENT_COUNT + 1))
    human_date=$(date -d "@$event_epoch" "+%Y-%m-%d %H:%M")
    echo "  [$EVENT_COUNT] $summary ($human_date)"

    # Try to get the featured image
    image_file=""
    image_url=$(scrape_image_url "$url" || true)
    if [ -n "$image_url" ]; then
        image_file="event-${EVENT_COUNT}.jpeg"
        echo "    Downloading image..."
        curl -s -f -o "${OUTDIR}/${image_file}" "$image_url" || {
            echo "    Warning: Failed to download image" >&2
            image_file=""
        }
    else
        echo "    No featured image found"
    fi

    # Build JSON entry
    j_title=$(json_escape "$summary")
    j_date=$(json_escape "$human_date")
    j_desc=$(json_escape "$description")
    j_url=$(json_escape "$url")
    j_img=$(json_escape "$image_file")

    entry=$(cat <<ENTRY
  {
    "title": "$j_title",
    "date": "$j_date",
    "description": "$j_desc",
    "url": "$j_url",
    "image": "$j_img"
  }
ENTRY
)

    if [ -n "$JSON_ENTRIES" ]; then
        JSON_ENTRIES="${JSON_ENTRIES},
${entry}"
    else
        JSON_ENTRIES="$entry"
    fi

done <<< "$EVENTS"

# Write JSON output
cat > "${OUTDIR}/events.json" <<EOF
[
${JSON_ENTRIES}
]
EOF

echo ""
echo "Done. Found $EVENT_COUNT event(s) in the next 7 days."
echo "Output: $OUTDIR/"
