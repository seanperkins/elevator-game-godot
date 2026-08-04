#!/bin/bash
# Authoritative multi-TLD RDAP availability check using IANA bootstrap endpoints.
# 200 = taken; 404 = available ONLY when the response is genuinely RDAP
# (Content-Type: application/rdap+json -- Verisign free domains return an empty
# body with a 404, so the header, not the body, is the discriminator); 429 =
# rate-limited; else retried then UNKNOWN. Names are validated to [a-z0-9-], and
# the script exits non-zero if any result is RATE/UNKNOWN or an endpoint errors,
# so `&&` never trusts a bad read.
set -u

BASE_COM="https://rdap.verisign.com/com/v1/domain/"
BASE_TV="https://rdap.nic.tv/domain/"
BASE_APP="https://pubapi.registry.google/rdap/domain/"
BASE_FM="https://rdap.centralnic.com/fm/domain/"

check() {
  local name="$1" tld="$2" url attempt meta code ctype body
  case "$tld" in
    com) url="$BASE_COM${name}.COM" ;;
    tv)  url="$BASE_TV${name}.tv" ;;
    app) url="$BASE_APP${name}.app" ;;
    fm)  url="$BASE_FM${name}.fm" ;;
    *)   echo "err(tld)"; return 2 ;;
  esac
  for attempt in 1 2 3; do
    body=$(mktemp)
    meta=$(curl -s -o "$body" -w "%{http_code}|%{content_type}" --max-time 20 \
      -H "Accept: application/rdap+json" "$url" 2>/dev/null)
    code="${meta%%|*}"
    ctype="${meta#*|}"
    case "$code" in
      200) rm -f "$body"; echo "taken"; return 0 ;;
      404)
        # Only authoritative if this is a genuine registry 404, not a WAF /
        # proxy / moved-endpoint page. A registry 404 carries the RDAP content
        # type even when (like Verisign) its body is empty.
        if [[ "$ctype" == application/rdap+json* ]]; then
          rm -f "$body"; echo "AVAIL"; return 0
        fi
        echo "err(404 non-RDAP) attempt=$attempt" >&2; rm -f "$body" ;;
      429) rm -f "$body"; echo "RATE"; return 1 ;;
      *)   echo "err($code) attempt=$attempt" >&2; rm -f "$body" ;;
    esac
    sleep 1
  done
  echo "UNKNOWN"
  return 1
}

if [ "$#" -eq 0 ]; then
  echo "usage: $0 <name> [name ...]" >&2
  exit 2
fi

fails=0
for name in "$@"; do
  if ! [[ "$name" =~ ^[a-z0-9-]+$ ]]; then
    echo "!! invalid name (allow [a-z0-9-]): $name" >&2
    fails=$((fails + 1))
    continue
  fi
  r_com=$(check "$name" com); c_com=$?
  r_tv=$(check "$name" tv);   c_tv=$?
  r_app=$(check "$name" app); c_app=$?
  r_fm=$(check "$name" fm);   c_fm=$?
  printf "%-16s com:%-7s tv:%-7s app:%-7s fm:%-7s\n" "$name" \
    "$r_com" "$r_tv" "$r_app" "$r_fm"
  for c in "$c_com" "$c_tv" "$c_app" "$c_fm"; do
    [ "$c" -ne 0 ] && fails=$((fails + 1))
  done
done
[ "$fails" -eq 0 ] || exit 1
exit 0
