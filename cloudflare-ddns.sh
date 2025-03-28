#!/usr/bin/env sh

# Copyright (c) 2025 Binbin Qian
# All rights reserved. (MIT Licensed)
#
# cloudflare-ddns: Dynamically update your DNS records in Cloudflare
# https://github.com/qianbinbin/cloudflare-ddns

# shellcheck disable=SC2086

ZONE_NAME=
ZONE_ID=
RECORD_NAME=
# 0=default, 1=A only, 2=AAAA only, 3=A and AAAA
RECORD_TYPE=0
PROXY=false
TTL=1
RENEW_INTERVAL=$((60 * 5))
MAILTO=

IPV4_SERVICES=$(
  cat <<-END
https://ipinfo.io/ip
https://ifconfig.me/ip
https://ident.me
https://icanhazip.com
https://ipecho.net/plain
https://myexternalip.com/raw
END
)

IPV6_SERVICES=$(
  cat <<-END
https://ifconfig.co
https://api6.ipify.org
https://ident.me
https://icanhazip.com
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
  # update A record for 'ddns.example.com'
  $(basename "$0") --zone-name example.com --record-name ddns.example.com

  # update AAAA record for 'ddns.example.com' and notify admin
  $(basename "$0") -z example.com -r ddns.example.com -6 -m admin

  # update both A and AAAA records for 'ddns.example.com'
  $(basename "$0") -z example.com -r ddns.example.com -4 -6

Options:
  -z, --zone-name <name>    zone name
  -r, --record-name <name>  record name; if A/AAAA records already exist in
                            Cloudflare, update the first one; see also --ipv4
                            and --ipv6
  -4, --ipv4                update A record (default)
  -6, --ipv6                update AAAA record only when used without --ipv4, or
                            update both A and AAAA records when used with --ipv4
  -p, --proxy               enable Cloudflare proxy for the record
  -t, --ttl <num>           Time To Live (TTL) of the DNS record in seconds;
                            setting to 1 means 'automatic'; value must be
                            between 60 and 86400, with the minimum reduced to 30
                            for Enterprise zones (default: $TTL)
  -i, --renew-interval <num>
                            renew interval in seconds (default: $RENEW_INTERVAL)
  -m, --mail-to <addr>      send an email to <addr> when a record is created or
                            renewed; <addr> can be a user or an email address
                            (MTA configuration required for email); can be used
                            several times
  -h, --help                display this help and exit

Home page: <https://github.com/qianbinbin/cloudflare-ddns>
END
)

error() { echo "$@" >&2; }

_exit() {
  error "$USAGE"
  exit 2
}

require() {
  ret=0
  for cmd in "$@"; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      error "'$cmd' not found"
      ret=1
    fi
  done
  [ "$ret" -eq 0 ] || exit 127
}

require curl jq

_curl() { curl -sSL --retry 4 "$@"; }

curl_cf() {
  content=$(_curl \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type:application/json" \
    "$@") || return 1
  if [ "$(echo "$content" | jq -r '.success')" = false ]; then
    error "Cloudflare error:"
    error "$(echo "$content" | jq -c '.errors')"
    return 1
  fi
  echo "$content"
}

while [ $# -gt 0 ]; do
  case "$1" in
  -z | --zone-name)
    [ -n "$2" ] || _exit
    ZONE_NAME="$2"
    shift 2
    ;;
  -r | --record-name)
    [ -n "$2" ] || _exit
    RECORD_NAME="$2"
    shift 2
    ;;
  -4 | --ipv4)
    RECORD_TYPE=$((RECORD_TYPE | 1))
    shift
    ;;
  -6 | --ipv6)
    RECORD_TYPE=$((RECORD_TYPE | 2))
    shift
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
  -m | --mail-to)
    [ -n "$2" ] || _exit
    MAILTO="$MAILTO $2"
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

[ "$RECORD_TYPE" -eq 0 ] && RECORD_TYPE=1
[ -z "$CLOUDFLARE_API_TOKEN" ] && error "No Cloudflare API token found" && _exit
[ -z "$ZONE_NAME" ] && error "No zone specified" && _exit
[ -z "$RECORD_NAME" ] && error "No record specified" && _exit
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
MAILTO=$(echo "$MAILTO" | xargs)
[ -n "$MAILTO" ] && require mail

DATA=$(
  cat <<-END
{
  "type": "",
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

ZONE_ID=$(curl_cf "https://api.cloudflare.com/client/v4/zones?name=$ZONE_NAME" | jq -r ".result[] | .id")
[ "$(echo "$ZONE_ID" | wc -w | xargs)" -ne 1 ] && error "Unable to find zone '$ZONE_NAME'" && exit 1
error "Found zone '$ZONE_NAME': '$ZONE_ID'"

first_record_id() {
  id=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records?name=$1&type=$2") || return 1
  echo "$id" | jq -r ".result[] | .id" | head -1
}

if [ $((RECORD_TYPE & 1)) -ne 0 ]; then
  A_RECORD_ID=$(first_record_id "$RECORD_NAME" A) || {
    error "Unable to find A record of '$RECORD_NAME'"
    exit 1
  }
  if [ -n "$A_RECORD_ID" ]; then
    error "Found A record '$RECORD_NAME': '$A_RECORD_ID'"
  else
    error "No A record of '$RECORD_NAME' found"
  fi
fi
if [ $((RECORD_TYPE & 2)) -ne 0 ]; then
  AAAA_RECORD_ID=$(first_record_id "$RECORD_NAME" AAAA) || {
    error "Unable to find AAAA record of '$RECORD_NAME'"
    exit 1
  }
  if [ -n "$AAAA_RECORD_ID" ]; then
    error "Found AAAA record '$RECORD_NAME': '$AAAA_RECORD_ID'"
  else
    error "No AAAA record of '$RECORD_NAME' found"
  fi
fi

get_ipv4() {
  for service in $IPV4_SERVICES; do
    _ip=$(_curl -f -4 --connect-timeout 10 "$service" |
      grep -o '^[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}$')
    if [ -n "$_ip" ]; then
      echo "$_ip"
      return
    fi
  done
  error "Unable to get IPv4 address"
  return 1
}

get_ipv6() {
  for service in $IPV6_SERVICES; do
    _ip=$(_curl -f -6 --connect-timeout 10 "$service" |
      grep -o '^[0-9a-fA-F:\.]\{7,45\}$')
    # Some servers may return an IPv4 address
    echo "$_ip" | grep -qs '^[0-9\.]*$' && continue
    # curl exits with code 3 when URL malformed
    # Consider it valid if accepted by curl
    # Use --head in case on a real HTTP server that returns bulk
    curl -f -6 --head --connect-timeout 0.01 "[$_ip]" >/dev/null 2>&1
    if [ $? -ne 3 ]; then
      echo "$_ip"
      return
    fi
  done
  error "Unable to get IPv6 address"
  return 1
}

create_record() {
  type=$(echo "$1" | jq -r '.type')
  name=$(echo "$1" | jq -r '.name')
  error "Creating $type record for '$name'"
  result=$(curl_cf -d "$1" "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records") || return 1
  echo "$result" | jq -r '.result.id'
  error "$(echo "$result" | jq)"
  if [ -n "$MAILTO" ]; then
    echo "$result" | jq | mail -s "Created $type record for '$name'" $MAILTO
  fi
  error "Created successfully"
}

renew_a_record() {
  data=$(echo "$DATA" | jq ".type = \"A\" | .content = \"$1\"")
  if [ -z "$A_RECORD_ID" ]; then
    A_RECORD_ID=$(create_record "$data") || return 1
    return
  fi
  record=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$A_RECORD_ID") || return 1
  if [ "$(echo "$record" | jq -r '.result.content')" = "$1" ] &&
    [ "$(echo "$record" | jq -r '.result.proxied')" = "$(echo "$data" | jq -r '.proxied')" ]; then
    error "No need to renew A record for '$RECORD_NAME'"
    return
  fi
  error "Renewing A record for '$RECORD_NAME'"
  result=$(curl_cf -X PUT -d "$data" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$A_RECORD_ID") || return 1
  error "$(echo "$result" | jq)"
  if [ -n "$MAILTO" ]; then
    echo "$result" | jq | mail -s "Renewed A record for '$RECORD_NAME'" $MAILTO
  fi
  error "Renewed successfully"
}

renew_aaaa_record() {
  data=$(echo "$DATA" | jq ".type = \"AAAA\" | .content = \"$1\"")
  if [ -z "$AAAA_RECORD_ID" ]; then
    AAAA_RECORD_ID=$(create_record "$data") || return 1
    return
  fi
  record=$(curl_cf "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$AAAA_RECORD_ID") || return 1
  if [ "$(echo "$record" | jq -r '.result.content')" = "$1" ] &&
    [ "$(echo "$record" | jq -r '.result.proxied')" = "$(echo "$data" | jq -r '.proxied')" ]; then
    error "No need to renew AAAA record for '$RECORD_NAME'"
    return
  fi
  error "Renewing AAAA record for '$RECORD_NAME'"
  result=$(curl_cf -X PUT -d "$data" \
    "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records/$AAAA_RECORD_ID") || return 1
  error "$(echo "$result" | jq)"
  if [ -n "$MAILTO" ]; then
    echo "$result" | jq | mail -s "Renewed AAAA record for '$RECORD_NAME'" $MAILTO
  fi
  error "Renewed successfully"
}

while true; do
  [ $((RECORD_TYPE & 1)) -ne 0 ] && ip=$(get_ipv4) && renew_a_record "$ip"
  [ $((RECORD_TYPE & 2)) -ne 0 ] && ip=$(get_ipv6) && renew_aaaa_record "$ip"
  sleep "$RENEW_INTERVAL"
done
