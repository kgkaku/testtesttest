#!/bin/bash

# ============================================
# BTV M3U Playlist Generator
# ============================================

# Configuration
TEMPLATE_FILE="template.m3u"
OUTPUT_FILE="btv_playlist.m3u"
BASE_URL="https://www.btvlive.gov.bd/live/"
BUILD_ID="wr5BMimBGS-yN5Rc2tmam"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Channel mapping (Template Name -> URL Name)
declare -A CHANNEL_MAP=(
    ["BTV"]="BTV"
    ["BTV News"]="BTV-News"
    ["BTV Chattogram"]="BTV-Chattogram"
    ["Sangsad Television"]="Sangsad-Television"
)

print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Extract channel name from EXTINF line
extract_channel_name() {
    local line="$1"
    echo "$line" | sed 's/^#EXTINF:-1 tvg-logo="".*,[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r'
}

# Fetch channel data from API
fetch_channel_data() {
    local urlname="$1"
    local api_url="https://www.btvlive.gov.bd/_next/data/${BUILD_ID}/channel/${urlname}.json?id=${urlname}"
    
    curl -s "$api_url" -A "Mozilla/5.0" -m 10
}

# Extract banner URL
extract_banner() {
    local data="$1"
    local banner=$(echo "$data" | jq -r '.pageProps.currentChannel.channel_details.banner // empty')
    
    if [ -n "$banner" ] && [ "$banner" != "null" ]; then
        if [[ "$banner" != http* ]]; then
            banner="https://www.btvlive.gov.bd/${banner}"
        fi
        echo "$banner"
    else
        echo ""
    fi
}

# Extract identifier
extract_identifier() {
    local data="$1"
    echo "$data" | jq -r '.pageProps.currentChannel.channel_details.identifier // empty'
}

# Extract user ID from sourceURL
extract_user_id() {
    local data="$1"
    local source_url=$(echo "$data" | jq -r '.pageProps.sourceURL // empty')
    
    if [ -n "$source_url" ] && [ "$source_url" != "null" ]; then
        echo "$source_url" | grep -oP '[^/]+(?=/index\.m3u8)' | tail -1
    else
        echo ""
    fi
}

# Main execution
print_status "$GREEN" "========================================="
print_status "$GREEN" "BTV M3U Playlist Generator"
print_status "$GREEN" "========================================="

# Check template file
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_status "$RED" "Error: Template file '$TEMPLATE_FILE' not found!"
    exit 1
fi

# Remove Windows line endings
sed -i 's/\r$//' "$TEMPLATE_FILE" 2>/dev/null || true

# Initialize output file
> "$OUTPUT_FILE"

# Statistics
total=0
success=0
failed=0

# Process each channel
while IFS= read -r line || [ -n "$line" ]; do
    line=$(echo "$line" | tr -d '\r')
    
    if [ -z "$line" ]; then
        continue
    fi
    
    if [[ $line == \#EXTINF* ]]; then
        channel_name=$(extract_channel_name "$line")
        total=$((total + 1))
        
        print_status "$YELLOW" ""
        print_status "$YELLOW" "[$total] Processing: $channel_name"
        
        # Get URL name
        urlname="${CHANNEL_MAP[$channel_name]}"
        
        if [ -z "$urlname" ]; then
            print_status "$RED" "  ✗ No mapping found for: $channel_name"
            failed=$((failed + 1))
            continue
        fi
        
        print_status "$GREEN" "  ✓ URL name: $urlname"
        
        # Fetch data
        channel_data=$(fetch_channel_data "$urlname")
        
        if [ -z "$channel_data" ]; then
            print_status "$RED" "  ✗ Failed to fetch data"
            failed=$((failed + 1))
            continue
        fi
        
        # Extract data
        identifier=$(extract_identifier "$channel_data")
        banner=$(extract_banner "$channel_data")
        user_id=$(extract_user_id "$channel_data")
        
        # Debug output
        print_status "$YELLOW" "  Identifier: ${identifier:-NOT FOUND}"
        print_status "$YELLOW" "  Banner: ${banner:-NOT FOUND}"
        print_status "$YELLOW" "  User ID: ${user_id:-NOT FOUND}"
        
        # Validate
        if [ -z "$identifier" ]; then
            print_status "$RED" "  ✗ Missing identifier"
            failed=$((failed + 1))
            continue
        fi
        
        if [ -z "$user_id" ]; then
            print_status "$YELLOW" "  ⚠ Using identifier as user ID"
            user_id="$identifier"
        fi
        
        # Generate stream URL
        stream_url="${BASE_URL}${identifier}/BD/${user_id}/index.m3u8"
        print_status "$GREEN" "  ✓ Stream URL: $stream_url"
        
        # Write to file
        echo "#EXTINF:-1 tvg-logo=\"$banner\", $channel_name" >> "$OUTPUT_FILE"
        echo "$stream_url" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        success=$((success + 1))
        print_status "$GREEN" "  ✓ Added to playlist"
        
        sleep 1
    fi
done < "$TEMPLATE_FILE"

# Print summary
print_status "$GREEN" ""
print_status "$GREEN" "========================================="
print_status "$GREEN" "Generation Complete!"
print_status "$GREEN" "========================================="
print_status "$GREEN" "Total channels: $total"
print_status "$GREEN" "Successful: $success"
print_status "$RED" "Failed: $failed"
print_status "$GREEN" "Output file: $OUTPUT_FILE"
print_status "$GREEN" "========================================="

if [ "$success" -gt 0 ]; then
    print_status "$GREEN" ""
    print_status "$GREEN" "Generated Playlist:"
    print_status "$YELLOW" "----------------------------------------"
    cat "$OUTPUT_FILE"
    exit 0
else
    print_status "$RED" "Error: No channels were added!"
    exit 1
fi
