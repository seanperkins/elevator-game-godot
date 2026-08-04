# Domain availability checker

A single RDAP wrapper (`check_all.sh`) that checks a candidate name across
`.com .tv .app .fm` directly against the registries' own RDAP endpoints (IANA
bootstrap) — free, no API key, and authoritative in the way a registrar's
"available" flag isn't.

    ./check_all.sh sonoplane kaleidokine

    sonoplane        com:AVAIL   tv:AVAIL   app:AVAIL   fm:AVAIL

A verdict of `AVAIL` means the registry returned **404 — not registered**. That
is the authoritative "free". `taken` is a 200 with registration records.

## Reliability

Registrar "availability" pages and casual lookups lie — they can show a domain
as free that is actually registered (the naming doc once claimed `rotozoom.com`
was free; Verisign says it is taken). This script is built to not do that:

- It talks **directly to the registry** via RDAP using the **IANA bootstrap**
  endpoints (Verisign for `.com`, `rdap.nic.tv` for `.tv`, Google for `.app`,
  CentralNic for `.fm`), not a redirector.
- It **retries** unknown/connection states up to 3× instead of reporting them
  as "free".
- It **never counts an `err(...)` or `UNKNOWN` as available**, validates each
  name to `[a-z0-9-]`, and exits **non-zero** if any result is `RATE` or
  `UNKNOWN` or an endpoint errors — so `./check_all.sh foo && deploy` cannot
  trust a bad read.

There is no separate `.com`-only or `.tv`/`.app`-only script: `check_all.sh`
covers every TLD, and a single script removes the risk of two scripts
disagreeing on the same registry.

## Caveats

- Registry-free (RDAP 404) is not the same as safe to use — trademarks, App
  Store collisions, and social handles are separate checks. Use with
  `tools/appstore-check`.
- If an endpoint reads `err(400)` it may have moved — re-check via the IANA
  bootstrap (`https://data.iana.org/rdap/dns.json`).
