#!/bin/bash

# ফাইল এবং API ঠিকানা নির্ধারণ
TEMPLATE_FILE="template.m3u"
OUTPUT_FILE="btv_playlist.m3u"
MAIN_API_URL="https://www.btvlive.gov.bd/api/home"
BASE_URL="https://www.btvlive.gov.bd/live/"
USER_ID_API_PREFIX="https://www.btvlive.gov.bd/_next/data/wr5BMimBGS-yN5Rc2tmam/channel/"
USER_ID_API_SUFFIX=".json"

echo "Fetching main API data from $MAIN_API_URL..."
main_api_response=$(curl -s "$MAIN_API_URL")

if [ -z "$main_api_response" ]; then
    echo "Error: Failed to fetch main API data."
    exit 1
fi

# API response structure দেখে নেওয়া
echo "API Response structure (first 500 chars):"
echo "$main_api_response" | head -c 500
echo ""

# Check if it's a valid JSON
if ! echo "$main_api_response" | jq empty 2>/dev/null; then
    echo "Error: Invalid JSON response from API"
    exit 1
fi

# Try to find where channels data is located
echo "Trying to find channels data in API response..."

# বিভিন্ন সম্ভাব্য JSON path চেক করা
channels_data=""

# Path 1: .channels
channels_data=$(echo "$main_api_response" | jq -c '.channels // empty' 2>/dev/null)
if [ -n "$channels_data" ] && [ "$channels_data" != "null" ]; then
    echo "Found channels at .channels"
else
    # Path 2: .data.channels
    channels_data=$(echo "$main_api_response" | jq -c '.data.channels // empty' 2>/dev/null)
    if [ -n "$channels_data" ] && [ "$channels_data" != "null" ]; then
        echo "Found channels at .data.channels"
    else
        # Path 3: .result
        channels_data=$(echo "$main_api_response" | jq -c '.result // empty' 2>/dev/null)
        if [ -n "$channels_data" ] && [ "$channels_data" != "null" ]; then
            echo "Found channels at .result"
        fi
    fi
fi

if [ -z "$channels_data" ] || [ "$channels_data" = "null" ]; then
    echo "Error: Could not find channels data in API response"
    echo "Full API response:"
    echo "$main_api_response" | jq '.' 2>/dev/null || echo "$main_api_response"
    exit 1
fi

# Extract channel names from template
echo "Extracting channel names from template file: $TEMPLATE_FILE"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found!"
    exit 1
fi

# CRLF to LF conversion
sed -i 's/\r$//' "$TEMPLATE_FILE" 2>/dev/null || true

# #EXTINF লাইন থেকে চ্যানেলের নাম বের করা (বাংলা নাম)
channel_names=$(grep "^#EXTINF" "$TEMPLATE_FILE" | sed 's/^#EXTINF:-1 tvg-logo="".*,[[:space:]]*//' | sed 's/[[:space:]]*$//')

if [ -z "$channel_names" ]; then
    echo "Error: No channel names found in template file."
    echo "Debug: Template file content:"
    cat "$TEMPLATE_FILE"
    exit 1
fi

echo "Found channels in template:"
echo "$channel_names"

# নতুন M3U ফাইল তৈরি
> "$OUTPUT_FILE"

# বাংলা থেকে ইংরেজি নাম ম্যাপিং
declare -A channel_name_map=(
    ["BTV"]="BTV"
    ["BTV News"]="BTV News"
    ["BTV Chattogram"]="BTV Chattogram"
    ["Sangsad Television"]="Sangsad Television"
)

# প্রতিটি চ্যানেলের জন্য লুপ
echo "$channel_names" | while IFS= read -r channel_name; do
    clean_channel_name=$(echo "$channel_name" | xargs)
    
    if [ -z "$clean_channel_name" ]; then
        continue
    fi
    
    echo "Processing channel: '$clean_channel_name'"
    
    # Find matching channel in API data using urlname
    urlname="${channel_name_map[$clean_channel_name]:-$clean_channel_name}"
    urlname=$(echo "$urlname" | sed 's/ /-/g')
    
    echo "  Looking for urlname: $urlname"
    
    # Find channel by urlname
    found_channel=$(echo "$channels_data" | jq -c --arg urlname "$urlname" '.[] | select(.urlname == $urlname)')
    
    if [ -z "$found_channel" ]; then
        echo "  Warning: Channel with urlname '$urlname' not found in API data. Trying to find by name..."
        
        # Try to find by channel_name (case insensitive)
        found_channel=$(echo "$channels_data" | jq -c --arg name "$clean_channel_name" '.[] | select(.channel_name | ascii_downcase | contains($name | ascii_downcase))')
    fi
    
    if [ -z "$found_channel" ] || [ "$found_channel" = "null" ]; then
        echo "  Error: Could not find channel '$clean_channel_name' in API data"
        echo "  Available urlnames:"
        echo "$channels_data" | jq -r '.[].urlname // empty' | head -5
        continue
    fi
    
    # Extract channel details
    banner_url=$(echo "$found_channel" | jq -r '.banner // empty')
    identifier=$(echo "$found_channel" | jq -r '.identifier // empty')
    channel_urlname=$(echo "$found_channel" | jq -r '.urlname // empty')
    
    echo "  Found channel:"
    echo "    URLName: $channel_urlname"
    echo "    Identifier: $identifier"
    echo "    Banner: $banner_url"
    
    # Fetch specific channel data for user ID
    specific_api_url="${USER_ID_API_PREFIX}${channel_urlname}${USER_ID_API_SUFFIX}?id=${channel_urlname}"
    echo "  Fetching specific data from: $specific_api_url"
    
    specific_response=$(curl -s "$specific_api_url")
    
    if [ -z "$specific_response" ]; then
        echo "  Warning: Could not fetch specific data, using identifier as user ID"
        user_id="$identifier"
    else
        # Try to extract user ID from sourceURL
        source_url=$(echo "$specific_response" | jq -r '.pageProps.sourceURL // .pageProps.currentChannel.sourceURL // empty' 2>/dev/null)
        
        if [ -n "$source_url" ] && [ "$source_url" != "null" ]; then
            echo "  Source URL: $source_url"
            # Extract user ID from URL (last part before index.m3u8)
            user_id=$(echo "$source_url" | grep -oP '[^/]+(?=/index\.m3u8)' | tail -1)
        else
            user_id="$identifier"
        fi
    fi
    
    echo "  User ID: $user_id"
    
    # Generate final stream URL
    final_url="${BASE_URL}${identifier}/BD/${user_id}/index.m3u8"
    echo "  Stream URL: $final_url"
    
    # Write to M3U file
    echo "#EXTINF:-1 tvg-logo=\"$banner_url\", $clean_channel_name" >> "$OUTPUT_FILE"
    echo "$final_url" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "  ✓ Entry added"
    echo "----------------------------------------"
done

# Check if any entries were added
if [ ! -s "$OUTPUT_FILE" ]; then
    echo "Error: No entries were added to playlist!"
    exit 1
fi

entry_count=$(grep -c "^#EXTINF" "$OUTPUT_FILE" 2>/dev/null || echo "0")
echo "✓ Playlist generation complete. Added $entry_count channels."
echo "Output file: $OUTPUT_FILE"

# Show the generated playlist
echo ""
echo "Generated playlist content:"
cat "$OUTPUT_FILE"
