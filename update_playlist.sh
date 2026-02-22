#!/bin/bash

# ============================================
# BTV M3U Playlist Generator
# Directly fetches from individual channel pages
# ============================================

# Configuration
TEMPLATE_FILE="template.m3u"
OUTPUT_FILE="btv_playlist.m3u"
BASE_URL="https://www.btvlive.gov.bd/live/"
API_BASE="https://www.btvlive.gov.bd/_next/data/wr5BMimBGS-yN5Rc2tmam/channel/"

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Channel mapping (Template Name -> URL Name)
# IMPORTANT: Exact mapping from your template
declare -A CHANNEL_MAP=(
    ["BTV"]="BTV"
    ["BTV News"]="BTV-News"
    ["BTV Chattogram"]="BTV-Chattogram"
    ["Sangsad Television"]="Sangsad-Television"
)

# Function to print colored output
print_status() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

# Function to extract channel name from EXTINF line
extract_channel_name() {
    local line="$1"
    # Remove #EXTINF:-1 tvg-logo="" part and trim
    echo "$line" | sed 's/^#EXTINF:-1 tvg-logo="".*,[[:space:]]*//' | sed 's/[[:space:]]*$//' | tr -d '\r'
}

# Function to fetch channel data
fetch_channel_data() {
    local urlname="$1"
    local api_url="${API_BASE}${urlname}.json?id=${urlname}"
    
    print_status "$YELLOW" "  Fetching: $api_url"
    
    # Fetch with timeout and user agent
    local response=$(curl -s -m 10 -A "Mozilla/5.0" "$api_url")
    
    if [ -z "$response" ]; then
        print_status "$RED" "  ✗ Failed to fetch data"
        return 1
    fi
    
    echo "$response"
    return 0
}

# Function to extract banner URL
extract_banner() {
    local data="$1"
    local banner=$(echo "$data" | jq -r '.pageProps.currentChannel.channel_details.banner // empty' 2>/dev/null)
    
    if [ -n "$banner" ] && [ "$banner" != "null" ]; then
        if [[ "$banner" != http* ]]; then
            # Remove any leading slash if present
            banner=$(echo "$banner" | sed 's/^\///')
            banner="https://www.btvlive.gov.bd/${banner}"
        fi
        echo "$banner"
    else
        echo ""
    fi
}

# Function to extract identifier
extract_identifier() {
    local data="$1"
    local identifier=$(echo "$data" | jq -r '.pageProps.currentChannel.channel_details.identifier // empty' 2>/dev/null)
    echo "$identifier"
}

# Function to extract user ID from sourceURL
extract_user_id() {
    local data="$1"
    local source_url=$(echo "$data" | jq -r '.pageProps.sourceURL // empty' 2>/dev/null)
    
    if [ -n "$source_url" ] && [ "$source_url" != "null" ]; then
        # Extract the part before /index.m3u8
        local user_id=$(echo "$source_url" | grep -oP '[^/]+(?=/index\.m3u8)' | tail -1)
        echo "$user_id"
    else
        echo ""
    fi
}

# Main execution starts here
print_status "$GREEN" "========================================="
print_status "$GREEN" "BTV M3U Playlist Generator"
print_status "$GREEN" "========================================="

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    print_status "$RED" "Error: Template file '$TEMPLATE_FILE' not found!"
    exit 1
fi

# Remove Windows carriage returns from template file
sed -i 's/\r$//' "$TEMPLATE_FILE" 2>/dev/null || true

# Read template file and process channels
print_status "$YELLOW" "Reading template file: $TEMPLATE_FILE"
print_status "$YELLOW" "----------------------------------------"

# Initialize output file
> "$OUTPUT_FILE"

# Variables for statistics
total_channels=0
successful_channels=0
failed_channels=0

# Read the template file line by line
while IFS= read -r line || [ -n "$line" ]; do
    # Remove carriage return
    line=$(echo "$line" | tr -d '\r')
    
    # Skip empty lines
    if [ -z "$line" ]; then
        continue
    fi
    
    # Check if this is an EXTINF line (channel info)
    if [[ $line == \#EXTINF* ]]; then
        channel_name=$(extract_channel_name "$line")
        total_channels=$((total_channels + 1))
        
        print_status "$YELLOW" ""
        print_status "$YELLOW" "[$total_channels] Processing: '$channel_name'"
        
        # Get URL name from map - EXACT MATCH
        urlname="${CHANNEL_MAP[$channel_name]}"
        
        if [ -z "$urlname" ]; then
            print_status "$RED" "  ✗ No mapping found for: '$channel_name'"
            print_status "$YELLOW" "  Available mappings:"
            for key in "${!CHANNEL_MAP[@]}"; do
                print_status "$YELLOW" "    '$key' -> '${CHANNEL_MAP[$key]}'"
            done
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        print_status "$GREEN" "  ✓ Found mapping: '$channel_name' -> '$urlname'"
        
        # Fetch channel data
        channel_data=$(fetch_channel_data "$urlname")
        
        if [ $? -ne 0 ] || [ -z "$channel_data" ]; then
            print_status "$RED" "  ✗ Failed to fetch data for: $channel_name"
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        # Extract all required data
        banner=$(extract_banner "$channel_data")
        identifier=$(extract_identifier "$channel_data")
        user_id=$(extract_user_id "$channel_data")
        
        # Debug output
        print_status "$YELLOW" "  Banner: ${banner:-"Not found"}"
        print_status "$YELLOW" "  Identifier: ${identifier:-"Not found"}"
        print_status "$YELLOW" "  User ID: ${user_id:-"Not found"}"
        
        # Validate extracted data
        if [ -z "$identifier" ] || [ "$identifier" = "null" ]; then
            print_status "$RED" "  ✗ Missing identifier for: $channel_name"
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
            print_status "$YELLOW" "  ⚠ User ID not found, using identifier as fallback"
            user_id="$identifier"
        fi
        
        # Generate stream URL
        stream_url="${BASE_URL}${identifier}/BD/${user_id}/index.m3u8"
        print_status "$GREEN" "  ✓ Generated URL: $stream_url"
        
        # Write to output file
        echo "#EXTINF:-1 tvg-logo=\"$banner\", $channel_name" >> "$OUTPUT_FILE"
        echo "$stream_url" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        successful_channels=$((successful_channels + 1))
        print_status "$GREEN" "  ✓ Added to playlist"
        
        # Small delay to avoid rate limiting
        sleep 1
        
    fi
    
done < "$TEMPLATE_FILE"

# Print statistics
print_status "$GREEN" ""
print_status "$GREEN" "========================================="
print_status "$GREEN" "Generation Complete!"
print_status "$GREEN" "========================================="
print_status "$GREEN" "Total channels found: $total_channels"
print_status "$GREEN" "Successfully added: $successful_channels"
if [ "$failed_channels" -gt 0 ]; then
    print_status "$RED" "Failed: $failed_channels"
fi
print_status "$GREEN" "Output file: $OUTPUT_FILE"
print_status "$GREEN" "========================================="

# Check if any entries were added
if [ "$successful_channels" -eq 0 ]; then
    print_status "$RED" "Error: No channels were successfully processed!"
    exit 1
fi

# Show the generated playlist
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    print_status "$YELLOW" ""
    print_status "$YELLOW" "Generated Playlist Content:"
    print_status "$YELLOW" "----------------------------------------"
    cat "$OUTPUT_FILE"
    print_status "$YELLOW" "----------------------------------------"
else
    print_status "$RED" "Error: Playlist file is empty or missing!"
    exit 1
fi

print_status "$GREEN" "✓ Script completed successfully!"
exit 0
