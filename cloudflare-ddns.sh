#!/usr/bin/env sh

# Copyright (c) 2025 Binbin Qian
# All rights reserved. (MIT Licensed)
#
# cloudflare-ddns: Dynamically update your DNS records in Cloudflare
# https://github.com/qianbinbin/cloudflare-ddns

ZONE_NAME=
ZONE_ID=
RECORD_NAME=
RECORD_ID=
PROXY=false
TTL=1
RENEW_INTERVAL=$((60 * 5))

IP_SERVICES=$(
  cat <<-END
https://ipinfo.io/ip
https://ifconfig.me/ip
https://ident.me
https://icanhazip.com
https://ipecho.net/plain
https://myexternalip.com/raw
END
)

USAGE=$(
  cat <<-END
Usage: $0 [OPTION]...

Dynamically update your DNS records in Cloudflare.

Create an API token and set your CLOUDFLARE_API_TOKEN environment variable
before running this script. For more details, refer to
<https://developers.cloudflare.com/fundamentals/api/get-started/create-token/>

Examples:
  $(basename "$0") --zone-name example.com --record-name ddns.example.com

Options:
      --zone-name <name>    zone name
      --zone-id <id>        zone ID; if not set, the ID will be retrieved with
                            --zone-name; this option takes higher precedence
                            than --zone-name
      --record-name <name>  record name
      --record-id <id>      record ID; if not set, the ID will be the first A
                            record retrieved with --record-name, or create a new
                            one if no records found; this option takes higher
                            precedence than --record-name
  -p, --proxy               enable Cloudflare proxy for the record
  -t, --ttl <num>           Time To Live (TTL) of the DNS record in seconds;
                            setting to 1 means 'automatic'; value must be
                            between 60 and 86400, with the minimum reduced to 30
                            for Enterprise zones (default: $TTL)
  -i, --renew-interval <num>
                            renew interval in seconds (default: $RENEW_INTERVAL)
  -h, --help                display this help and exit

Home page: <https://github.com/qianbinbin/cloudflare-ddns>
END
)

error() { echo "$@" >&2; }

_exit() {
  error "$USAGE"
  exit 2
}

while [ $# -gt 0 ]; do
  case "$1" in
  --zone-name)
    [ -n "$2" ] || _exit
    ZONE_NAME="$2"
    shift 2
    ;;
  --zone-id)
    [ -n "$2" ] || _exit
    ZONE_ID="$2"
    shift 2
    ;;
  --record-name)
    [ -n "$2" ] || _exit
    RECORD_NAME="$2"
    shift 2
    ;;
  --record-id)
    [ -n "$2" ] || _exit
    RECORD_ID="$2"
    shift 2
    ;;
  -p | --proxy)
    PROXY=true
    shift
    ;;
  -t | --ttl)
    [ -n "$2" ] || _exit
    TTL="$2"
    shift 2
    ;;
  -i | --renew-interval)
    [ -n "$2" ] || _exit
    RENEW_INTERVAL="$2"
    shift 2
    ;;
  -h | --help)
    error "$USAGE" && exit
    ;;
  *)
    _exit
    ;;
  esac
done

if [ -z "$CLOUDFLARE_API_TOKEN" ]; then
  error "No Cloudflare API token found"
  _exit
fi
if [ -z "$ZONE_NAME" ] && [ -z "$ZONE_ID" ]; then
  error "No zone specified"
  _exit
fi
if [ -z "$RECORD_NAME" ] && [ -z "$RECORD_ID" ]; then
  error "No record specified"
  _exit
fi
if ! [ "$TTL" -gt 0 ] 2>/dev/null; then
  error "Invalid TTL '$TTL'"
  _exit
fi
if [ "$TTL" -ne 1 ] && { [ "$TTL" -lt 30 ] || [ "$TTL" -gt 86400 ]; }; then
  error "Invalid TTL '$TTL'"
  _exit
fi
if ! [ "$RENEW_INTERVAL" -gt 0 ] 2>/dev/null; then
  error "Invalid renew interval '$RENEW_INTERVAL'"
  _exit
fi

_curl() { curl -sSL --retry 5 "$@"; }

curl_cf() {
  if ! content=$(_curl \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type:application/json" \
    "$@"); then
    return 1
  fi
  if [ "$(echo "$content" | jq -r '.success')" = false ]; then
    error "Cloudflare error:"
    error "$(echo "$content" | jq -c '.errors')"
    return 1
  fi
  echo "$content"
}

if [ -n "$ZONE_ID" ]; then
  zone_name=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID" |
    jq -r '.result.name')
  if [ -z "$zone_name" ]; then
    error "Unable to find zone '$ZONE_ID'"
    exit 1
  fi
  if [ "$ZONE_NAME" != "$zone_name" ]; then
    error "Setting ZONE_NAME as '$zone_name'"
    ZONE_NAME="$zone_name"
  fi
else
  ZONE_ID=$(curl_cf "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" |
    jq -r ".result[] | select(.name == \"$ZONE_NAME\") | .id")
  if [ -z "$ZONE_ID" ]; then
    error "Unable to find zone '$ZONE_NAME'"
    exit 1
  fi
fi

if [ -n "$RECORD_ID" ]; then
  record_name=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" |
    jq -r '.result.name')
  if [ -z "$record_name" ]; then
    error "Unable to find record '$RECORD_ID'"
    exit 1
  fi
  if [ "$RECORD_NAME" != "$record_name" ]; then
    error "Setting RECORD_NAME as '$record_name'"
    RECORD_NAME="$record_name"
  fi
else
  records=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?type=A&name=$RECORD_NAME") || exit 1
  total_count=$(echo "$records" | jq -r '.result_info.total_count')
  if [ "$total_count" -gt 0 ]; then
    if [ "$total_count" -ge 2 ]; then
      error "$total_count A records of '$RECORD_NAME' found, choosing the first one"
    fi
    RECORD_ID=$(echo "$records" | jq -r '.result[0].id')
  fi
fi

DATA=$(
  cat <<-END
{
  "type": "A",
  "name": "$RECORD_NAME",
  "content": "",
  "proxied": $PROXY,
  "ttl": $TTL,
  "comment": "cloudflare-ddns",
  "settings": {},
  "tags": []
}
END
)

get_public_ip() {
  for service in $IP_SERVICES; do
    _ip=$(_curl -f -4 --connect-timeout 5 "$service" |
      grep -o '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$')
    if [ -n "$_ip" ]; then
      echo "$_ip"
      return
    fi
  done
  error "Unable to get IP address"
  return 1
}

renew() {
  data=$(echo "$DATA" | jq ".content = \"$1\"")
  if [ -z "$RECORD_ID" ]; then
    error "Creating a new A record for '$RECORD_NAME'"
    response=$(curl_cf -d "$data" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records") || return 1
    RECORD_ID=$(echo "$response" | jq -r '.result.id')
    error "Created successfully"
    return
  fi
  record=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID") || return 1
  if [ "$(echo "$record" | jq -r '.result.content')" = "$1" ]; then
    error "No need to renew '$RECORD_NAME'"
    return
  fi
  error "Renewing '$RECORD_NAME'"
  curl_cf -X PUT -d "$data" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$RECORD_ID" || return 1
  error "Renewed successfully"
}

while true; do
  ip=$(get_public_ip) && renew "$ip"
  sleep "$RENEW_INTERVAL"
done
