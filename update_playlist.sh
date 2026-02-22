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

# Channel mapping (Bengali/English name -> URL name)
declare -A CHANNEL_MAP=(
    ["BTV"]="BTV"
    ["বিটিভি"]="BTV"
    ["BTV News"]="BTV-News"
    ["বিটিভি নিউজ"]="BTV-News"
    ["BTV Chattogram"]="BTV-Chattogram"
    ["বিটিভি চট্টগ্রাম"]="BTV-Chattogram"
    ["Sangsad Television"]="Sangsad-Television"
    ["সংসদ টেলিভিশন"]="Sangsad-Television"
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
    echo "$line" | sed 's/^#EXTINF:-1 tvg-logo="".*,[[:space:]]*//' | sed 's/[[:space:]]*$//'
}

# Function to clean text (remove carriage returns, etc.)
clean_text() {
    echo "$1" | tr -d '\r' | xargs
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

# Initialize output file
> "$OUTPUT_FILE"

# Variables for statistics
total_channels=0
successful_channels=0
failed_channels=0
skipped_channels=0

# Read the template file line by line
current_channel=""
current_url=""

while IFS= read -r line || [ -n "$line" ]; do
    # Remove carriage return
    line=$(echo "$line" | tr -d '\r')
    
    # Skip empty lines
    if [ -z "$line" ]; then
        continue
    fi
    
    # Check if this is an EXTINF line (channel info)
    if [[ $line == \#EXTINF* ]]; then
        current_channel=$(extract_channel_name "$line")
        total_channels=$((total_channels + 1))
        
        print_status "$YELLOW" ""
        print_status "$YELLOW" "[$total_channels] Processing: $current_channel"
        
        # Find URL name for this channel
        urlname=""
        for key in "${!CHANNEL_MAP[@]}"; do
            if [[ "$current_channel" == *"$key"* ]] || [[ "$key" == *"$current_channel"* ]]; then
                urlname="${CHANNEL_MAP[$key]}"
                print_status "$GREEN" "  Matched URL name: $urlname"
                break
            fi
        done
        
        if [ -z "$urlname" ]; then
            print_status "$RED" "  ✗ Could not find URL name for: $current_channel"
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        # Fetch channel data
        channel_data=$(fetch_channel_data "$urlname")
        
        if [ $? -ne 0 ] || [ -z "$channel_data" ]; then
            print_status "$RED" "  ✗ Failed to fetch data for: $current_channel"
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        # Extract all required data
        banner=$(extract_banner "$channel_data")
        identifier=$(extract_identifier "$channel_data")
        user_id=$(extract_user_id "$channel_data")
        
        # Debug output
        print_status "$YELLOW" "  Banner: $banner"
        print_status "$YELLOW" "  Identifier: $identifier"
        print_status "$YELLOW" "  User ID: $user_id"
        
        # Validate extracted data
        if [ -z "$identifier" ] || [ "$identifier" = "null" ]; then
            print_status "$RED" "  ✗ Missing identifier for: $current_channel"
            failed_channels=$((failed_channels + 1))
            continue
        fi
        
        if [ -z "$user_id" ] || [ "$user_id" = "null" ]; then
            print_status "$YELLOW" "  ⚠ User ID not found, using identifier as fallback"
            user_id="$identifier"
        fi
        
        # Generate stream URL
        stream_url="${BASE_URL}${identifier}/BD/${user_id}/index.m3u8"
        print_status "$GREEN" "  Stream URL: $stream_url"
        
        # Write to output file
        echo "#EXTINF:-1 tvg-logo=\"$banner\", $current_channel" >> "$OUTPUT_FILE"
        echo "$stream_url" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        
        successful_channels=$((successful_channels + 1))
        print_status "$GREEN" "  ✓ Added to playlist"
        
        # Small delay to avoid rate limiting
        sleep 1
        
    else
        # Skip the original URL line
        continue
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

# Show the generated playlist
if [ -f "$OUTPUT_FILE" ] && [ -s "$OUTPUT_FILE" ]; then
    print_status "$YELLOW" ""
    print_status "$YELLOW" "Generated Playlist Content:"
    print_status "$YELLOW" "-----------------------------------------"
    cat "$OUTPUT_FILE"
    print_status "$YELLOW" "-----------------------------------------"
else
    print_status "$RED" "Error: No playlist generated!"
    exit 1
fi

exit 0
