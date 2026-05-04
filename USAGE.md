# USAGE — FireCompass Deep Passive OSINT Agent

Two ways to run: **(A) inside Claude CLI on Kali**, or **(B) standalone scripts only**.

---

## A. Claude CLI Mode (Recommended)

1. Open a terminal on your Kali box.
2. Start Claude CLI:
   ```bash
   claude
   ```
3. Invoke the agent:
   ```
   > use firecompass-passive-recon to recon acme.com (Acme Corp)
   ```
   Or more specifically:
   ```
   > run firecompass-passive-recon — organisation: Acme Corporation, primary domain: acme.com
   ```

The agent will:
- Acknowledge the target back to you
- Confirm scope (asks if there are known related domains it should add)
- Run all 14 phases sequentially with progress updates
- Pause to ask if it hits a missing API key (Shodan/HIBP/etc.) — does NOT silently skip
- Run the self-audit harness at the end
- Generate `passive-recon-output-<ORG>.md` in the engagement directory

**Estimated time:** 30–90 minutes depending on the size of the attack surface.

---

## B. Standalone Mode (No Claude CLI)

If you want to run the phases yourself, perfect for verification or when Claude CLI isn't available:

```bash
# Set environment
export ENGAGEMENT_DIR=/home/kali/engagements/acme-corp-$(date +%Y%m%d)
export PRIMARY_DOMAIN=acme.com
export ORG_NAME="Acme Corp"

# Run phases in order
bash scripts/00_setup_engagement.sh "$ORG_NAME" "$PRIMARY_DOMAIN"
bash scripts/01_seed_collection.sh
# >>>>> manually review $ENGAGEMENT_DIR/seeds/seed_roots.txt and remove false positives <<<<<

bash scripts/02_wildcard_check.sh
bash scripts/03_subdomain_enum.sh
bash scripts/04_js_mining.sh           # needs at least one HTTP probe to have run, or seeds will be used
bash scripts/05_google_dork.sh         # outputs ready-made search URLs — also opens in browser manually
bash scripts/06_shodan_lookup.sh       # uses InternetDB free; set SHODAN_API_KEY for richer lookup

python3 scripts/07_dns_resolve_probe.py
python3 scripts/08_pattern_permutation.py    # ESPECIALLY important if Phase 2 flagged wildcards
python3 scripts/07_dns_resolve_probe.py      # re-run to probe newly-discovered hosts

bash scripts/09_asn_netblock.sh
bash scripts/10_shodan_ports.sh
bash scripts/11_leaked_creds.sh        # set HIBP_API_KEY / DEHASHED_API_KEY / INTELX_API_KEY for richer
bash scripts/12_github_leaks.sh        # set GITHUB_TOKEN for higher rate limit
bash scripts/13_cloud_buckets.sh
bash scripts/14_email_osint.sh         # set HUNTER_API_KEY for hunter.io

# Verify nothing was skipped
bash tests/self-audit.sh

# Generate final report
python3 scripts/99_generate_report.py
```

Output report goes to:
```
$ENGAGEMENT_DIR/reports/passive-recon-output-<ORG>.md
```

---

## API Keys (Optional but Recommended)

Export these in your shell or in a `.env` file:

| Variable | Provider | Free Tier? |
|----------|----------|-----------|
| `SHODAN_API_KEY` | Shodan | Limited search; better with paid |
| `GITHUB_TOKEN` | GitHub PAT | 30 req/min unauth → 5000 req/h with PAT |
| `HIBP_API_KEY` | HaveIBeenPwned | Paid only; per-email lookups don't need key |
| `DEHASHED_USERNAME` + `DEHASHED_API_KEY` | DeHashed | Paid only |
| `INTELX_API_KEY` | IntelelligenceX | Free tier with registration |
| `HUNTER_API_KEY` | Hunter.io | Free tier 25 searches/month |

If a key is missing, the corresponding source is skipped with a clear log message — the rest of the engagement continues. The agent does NOT silently fail.

---

## How To Read The Output

The report is structured for direct copy-paste into the FireCompass internal email (Template #2 — Passive Scan Highlights). Sections map to the email bullets:

| Report Section | Email Bullet |
|----------------|--------------|
| § 0 Executive Summary | Top of email |
| § 4.1 Live 200 OK Apps | "Active Applications: NN" |
| § 5 Pattern Permutation | "Hidden internal apps recovered: NN" (talk track for client call) |
| § 6 IP / ASN | "Active IPs: NN" |
| § 7 Shodan Exposure | "Sensitive Open Services" |
| § 8 Cloud Buckets | New finding category — flag separately |
| § 9 Email OSINT | "Leaked Credentials: NN" |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `subfinder: command not found` | Run `bash INSTALL.sh` |
| `crt.sh returns 502` | Intermittent. Other sources cover the gap. Re-run Phase 3 later. |
| `httpx hangs with -follow-redirects` | We don't use httpx for redirects — Python concurrent curl is in Phase 7 instead |
| Phase 8 finds nothing on a wildcard root | Either you have insufficient prefixes from Phase 3, or the org's internal apps are truly air-gapped. Cross-check with Phase 4 (JS mining) and Phase 12 (GitHub). |
| `self-audit.sh` fails on Phase X | The phase script didn't produce its expected output file. Check `$ENGAGEMENT_DIR/logs/0X_*.log` for the error. |
