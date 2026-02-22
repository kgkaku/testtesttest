#!/bin/bash

# ফাইল এবং API ঠিকানা নির্ধারণ
TEMPLATE_FILE="template.m3u"
OUTPUT_FILE="btv_playlist.m3u"
MAIN_API_URL="https://www.btvlive.gov.bd/api/home"
BASE_URL="https://www.btvlive.gov.bd/live/"
USER_ID_API_PREFIX="https://www.btvlive.gov.bd/_next/data/wr5BMimBGS-yN5Rc2tmam/channel/"
USER_ID_API_SUFFIX=".json"

# ১. মেইন API থেকে ডেটা সংগ্রহ
echo "Fetching main API data from $MAIN_API_URL..."
main_api_response=$(curl -s "$MAIN_API_URL")

if [ -z "$main_api_response" ]; then
    echo "Error: Failed to fetch main API data."
    exit 1
fi

# ২. টেমপ্লেট M3U ফাইল থেকে চ্যানেলের নাম বের করা
echo "Extracting channel names from template file: $TEMPLATE_FILE"

if [ ! -f "$TEMPLATE_FILE" ]; then
    echo "Error: Template file $TEMPLATE_FILE not found!"
    exit 1
fi

# CRLF to LF conversion
sed -i 's/\r$//' "$TEMPLATE_FILE" 2>/dev/null || true

# #EXTINF লাইন থেকে চ্যানেলের নাম বের করা
channel_names=$(grep "^#EXTINF" "$TEMPLATE_FILE" | sed 's/^#EXTINF:-1 tvg-logo="".*,[[:space:]]*//' | sed 's/[[:space:]]*$//')

if [ -z "$channel_names" ]; then
    echo "Error: No channel names found in template file."
    echo "Debug: Template file content:"
    cat "$TEMPLATE_FILE"
    exit 1
fi

echo "Found channels:"
echo "$channel_names"

# ৩. নতুন M3U ফাইল তৈরি শুরু
> "$OUTPUT_FILE"

# ৪. প্রতিটি চ্যানেলের জন্য লুপ
echo "$channel_names" | while IFS= read -r channel_name; do
    clean_channel_name=$(echo "$channel_name" | xargs)
    
    if [ -z "$clean_channel_name" ]; then
        continue
    fi
    
    echo "Processing channel: '$clean_channel_name'"
    
    # মেইন API রেসপন্স থেকে সব চ্যানেলের তালিকা বের করা
    channels_list=$(echo "$main_api_response" | jq -c '.channels[]')
    
    # চ্যানেল খোঁজা
    found_channel=""
    while IFS= read -r channel; do
        channel_bn_name=$(echo "$channel" | jq -r '.channel_name')
        channel_urlname=$(echo "$channel" | jq -r '.urlname')
        
        if [[ "$channel_bn_name" == *"$clean_channel_name"* ]] || [[ "$clean_channel_name" == *"$channel_bn_name"* ]]; then
            found_channel="$channel"
            echo "  Matched with API channel: $channel_bn_name (urlname: $channel_urlname)"
            break
        fi
    done <<< "$channels_list"
    
    if [ -z "$found_channel" ]; then
        echo "  Warning: Channel '$clean_channel_name' not found in main API. Skipping."
        continue
    fi
    
    banner_url=$(echo "$found_channel" | jq -r '.banner')
    identifier=$(echo "$found_channel" | jq -r '.identifier')
    urlname=$(echo "$found_channel" | jq -r '.urlname')
    
    if [[ "$banner_url" != http* ]] && [[ -n "$banner_url" ]]; then
        banner_url="https://www.btvlive.gov.bd/${banner_url}"
    fi
    
    echo "  Banner: $banner_url"
    echo "  Identifier: $identifier"
    echo "  URLName: $urlname"
    
    specific_api_url="${USER_ID_API_PREFIX}${urlname}${USER_ID_API_SUFFIX}?id=${urlname}"
    echo "  Fetching user ID from: $specific_api_url"
    
    specific_api_response=$(curl -s "$specific_api_url")
    
    if [ -z "$specific_api_response" ]; then
        echo "  Error: Failed to fetch specific API for $urlname"
        continue
    fi
    
    source_url=$(echo "$specific_api_response" | jq -r '.pageProps.sourceURL // .pageProps.currentChannel.sourceURL // empty')
    
    if [ -z "$source_url" ] || [ "$source_url" = "null" ]; then
        echo "  Error: Could not find sourceURL for $urlname"
        continue
    fi
    
    user_id=$(echo "$source_url" | grep -oP '/[^/]+/index\.m3u8$' | sed 's/\/index\.m3u8$//' | sed 's/^\///')
    
    if [ -z "$user_id" ]; then
        path_without_filename=$(dirname "$source_url")
        user_id=$(basename "$path_without_filename")
    fi
    
    echo "  User ID: $user_id"
    
    final_stream_url="${BASE_URL}${identifier}/BD/${user_id}/index.m3u8"
    echo "  Stream URL: $final_stream_url"
    
    echo "#EXTINF:-1 tvg-logo=\"$banner_url\", $clean_channel_name" >> "$OUTPUT_FILE"
    echo "$final_stream_url" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"
    
    echo "  ✓ Entry added"
    echo "----------------------------------------"
done

entry_count=$(grep -c "^#EXTINF" "$OUTPUT_FILE" 2>/dev/null || echo "0")

if [ "$entry_count" -eq 0 ]; then
    echo "Error: No entries were added to the playlist!"
    exit 1
fi

echo "✓ Playlist generation complete. Added $entry_count channels."
echo "Output file: $OUTPUT_FILE"
