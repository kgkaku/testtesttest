#!/bin/bash

# ফাইল এবং API ঠিকানা নির্ধারণ
TEMPLATE_FILE="template.m3u"          # আপনার দেওয়া মূল M3U ফাইলটির নাম
OUTPUT_FILE="btv_playlist.m3u"        # আপডেট হওয়া আউটপুট ফাইলের নাম
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

# ২. টেমপ্লেট M3U ফাইল থেকে চ্যানেলের নাম (urlname) বের করে একটি অস্থায়ী ফাইলে রাখা
echo "Extracting channel names from template file: $TEMPLATE_FILE"
channel_names=$(grep -oP '(?<=#EXTINF:-1 tvg-logo="" ).*' "$TEMPLATE_FILE" | sed 's/[[:space:]]*$//')

if [ -z "$channel_names" ]; then
    echo "Error: No channel names found in template file."
    exit 1
fi

# ৩. নতুন M3U ফাইল তৈরি শুরু
> "$OUTPUT_FILE"

# ৪. প্রতিটি চ্যানেলের জন্য লুপ
echo "$channel_names" | while read -r channel_name; do
    # চ্যানেলের নাম ট্রিম করা ( leading/trailing spaces সরানো)
    clean_channel_name=$(echo "$channel_name" | xargs)
    echo "Processing channel: $clean_channel_name"

    # মেইন API রেসপন্স থেকে এই চ্যানেলের অবজেক্ট খুঁজে বের করা (jq ব্যবহার করে)
    # জটিল JSON পার্স করার জন্য jq ইনস্টল করা থাকা জরুরি। GitHub Actions-এ ডিফল্ট থাকে।
    channel_data=$(echo "$main_api_response" | jq -c --arg name "$clean_channel_name" '.channels[] | select(.urlname == $name)')

    if [ -z "$channel_data" ] || [ "$channel_data" = "null" ]; then
        echo "  Warning: Channel '$clean_channel_name' not found in main API. Skipping."
        continue
    fi

    # ৫. 'banner' এবং 'identifier' এক্সট্রাক্ট করা
    banner_url=$(echo "$channel_data" | jq -r '.banner')
    identifier=$(echo "$channel_data" | jq -r '.identifier')
    base_url_from_api=$(echo "$channel_data" | jq -r '.base_url') # API থেকে base_url নেয়া, যদিও আপনি fix দিয়েছেন

    if [ -z "$banner_url" ] || [ "$banner_url" = "null" ]; then banner_url=""; fi
    if [ -z "$identifier" ] || [ "$identifier" = "null" ]; then
        echo "  Error: Identifier not found for channel $clean_channel_name. Skipping."
        continue
    fi

    echo "  Found Banner: $banner_url"
    echo "  Found Identifier: $identifier"

    # ৬. নির্দিষ্ট চ্যানেল API থেকে 'userId' বের করা
    # urlname অনুযায়ী JSON ফাইলের পথ তৈরি (যেমন: BTV.json?id=BTV)
    # URL encode প্রয়োজন হতে পারে, কিন্তু এখানে স্পেস থাকলে সেগুলো '-'-এ রূপান্তর করতে হবে (যেমন: BTV News -> BTV-News)
    urlname_for_path=$(echo "$clean_channel_name" | sed 's/ /-/g')
    specific_api_url="${USER_ID_API_PREFIX}${urlname_for_path}${USER_ID_API_SUFFIX}?id=${urlname_for_path}"

    # যদি urlname-এ স্পেস না থাকে, তাহলে সরাসরি ব্যবহার করা যায়। আমরা এখানে API কল করছি।
    echo "  Fetching user ID from: $specific_api_url"
    specific_api_response=$(curl -s "$specific_api_url")

    if [ -z "$specific_api_response" ]; then
        echo "  Error: Failed to fetch specific API for $clean_channel_name. Using default user ID? (Skipping)"
        # আপনি চাইলে এখানে ডিফল্ট কিছু সেট করতে পারেন, কিন্তু আমরা চ্যানেলটি স্কিপ করছি।
        continue
    fi

    # JSON থেকে userId বের করা। এটি currentChannel.channel_details.identifier এর ভিতর আছে। কিন্তু আপনার বর্ণনা অনুযায়ী, main API থেকেই identifier পেয়ে গেছেন।
    # userId আসলে কোথায়? আপনার দেওয়া BTV-Chattogram.json-এর data তে দেখছি sourceURL-এর মধ্যে userId হিসেবে "HK" ব্যবহার করা হয়েছে এবং identifier এর ভ্যালু "a707f2dc-9704-413a-a67c-17c64a77c350"।
    # আপনার বর্ণনায় userId এর জন্য যে API দেয়া হয়েছে, তার রেসপন্সে সরাসরি "userId" নামে কোনো ফিল্ড নেই। বরং, sourceURL ফিল্ড থেকে আমরা শেষ অংশটি পেতে পারি।
    # sourceURL = "https://www.btvlive.gov.bd/live/undefined/HK/a707f2dc-9704-413a-a67c-17c64a77c350/index.m3u8"
    # এখানে 'userId' হচ্ছে "a707f2dc-9704-413a-a67c-17c64a77c350"? নাকি দেশের কোড "HK"? আপনি বলেছেন "userId" বসাতে হবে। JSON-এ "userId" নামে কিছু নেই।
    # আমি এখানে sourceURL থেকে শেষ স্ল্যাশের পরের অংশ (identifier) এবং তার আগের অংশ (Country Code?) আলাদা করে দেখছি।
    # ধরে নিচ্ছি, "userId" আসলে এই identifier-ই। এবং Country Code হবে "BD" (যা আপনি fix দিয়েছেন)।

    # আমরা sourceURL থেকে identifier টি বের করে সেটিকেই 'userId' হিসেবে ব্যবহার করছি। এটি main API থেকে পাওয়া identifier-এর সাথে মিলে যাবে।
    source_url=$(echo "$specific_api_response" | jq -r '.pageProps.sourceURL')
    if [ -z "$source_url" ] || [ "$source_url" = "null" ]; then
        echo "  Error: Could not find sourceURL for $clean_channel_name."
        continue
    fi

    # source_url থেকে শেষ অংশ বের করা (identifier/userId)
    # ফরম্যাট: .../live/CountryCode/ThisPart/index.m3u8
    user_id_from_url=$(basename "$(dirname "$source_url")") # এটি "a707f2dc-9704-413a-a67c-17c64a77c350" রিটার্ন করবে
    echo "  Found User ID (from sourceURL): $user_id_from_url"

    # ৭. চূড়ান্ত M3U8 URL তৈরি
    # আপনি base_url হিসেবে "https://www.btvlive.gov.bd/live/" দিতে চেয়েছেন। সেটাই ব্যবহার করছি।
    # ফরম্যাট: base_url/identifier/BD/userId/index.m3u8
    # এখানে 'identifier' ও 'userId' আসলে একই মান হতে পারে। কিন্তু আপনার বর্ণনা অনুযায়ী, identifier main API থেকে এবং userId specific API থেকে আসছে। আমরা উভয়ই আলাদা করে পেয়েছি।
    final_stream_url="${BASE_URL}${identifier}/BD/${user_id_from_url}/index.m3u8"
    echo "  Generated Stream URL: $final_stream_url"

    # ৮. M3U ফাইলে এন্ট্রি যোগ করা
    echo "#EXTINF:-1 tvg-logo=\"$banner_url\", $clean_channel_name" >> "$OUTPUT_FILE"
    echo "$final_stream_url" >> "$OUTPUT_FILE"
    echo "" >> "$OUTPUT_FILE"

    echo "  Entry added to $OUTPUT_FILE"
done

echo "Playlist generation complete. Output file: $OUTPUT_FILE"
