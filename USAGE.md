# USAGE — FireCompass Deep Passive OSINT Agent

## How to use this — supervised collaboration with Claude

This isn't a "press play and walk away" tool. It's a **supervised collaboration**: Claude runs the 14 recon phases inside Claude CLI on your Kali box, you supervise and intervene when needed. Claude pauses at decision points; you guide, redirect, or confirm.

That's the default workflow. The standalone scripts at the bottom of this doc are a fallback for when Claude CLI isn't available or you need to verify a single phase by hand.

---

## Primary Workflow — Claude CLI on Kali (Supervised)

### Setup (once per Kali box)

```bash
git clone https://github.com/0xthusharkiranreddy/FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT
cd FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT
bash INSTALL.sh
mkdir -p ~/.claude/agents
cp agents/firecompass-passive-recon.md ~/.claude/agents/
```

### Per engagement

Open a Kali terminal. Start Claude CLI:

```bash
claude
```

Invoke the agent:

```
> use firecompass-passive-recon to recon acme.com (Acme Corp)
```

### What happens next — the supervision loop

The agent will:

1. **Acknowledge** the target back to you.
2. **Ask which mode you want:**
   - **(A) Auto-pilot** — runs all phases, pauses only at hard checkpoints (default if you don't specify)
   - **(B) Per-phase confirmation** — shows results after each phase, you say "continue" or redirect

3. **Run phases** with brief one-line status updates after each.

4. **Pause at hard checkpoints** regardless of mode (you cannot opt out of these):
   - **Checkpoint 1 — After related-domain discovery.** Reverse WHOIS has false positives. Agent shows you the candidate roots; you mark which to drop, which to add. Curated list goes into all subsequent phases.
   - **Checkpoint 2 — When wildcard cert is detected.** Agent tells you which root, asks if you want to proceed (Phase 8 pattern permutation will run on it), and asks if the client has already shared any hostnames so it can seed more naming patterns.
   - **Checkpoint 3 — Missing API key.** Instead of silently skipping, agent asks if you want to (1) skip and document the gap, or (2) wait while you set the key.
   - **Checkpoint 4 — Anomaly detected.** If results look wrong (huge unexpected count, all sources empty, source conflicts), agent stops and asks you to choose how to proceed.
   - **Checkpoint 5 — Before final report.** Asks if there's any specific finding to emphasise, or client context to include.

5. **You can interrupt at any time** — typing in the chat:
   - `"Hold on, why did you skip X?"` → agent explains its reasoning
   - `"Try Y instead"` → agent integrates your suggestion into the current phase
   - `"I don't trust that result"` → agent re-runs with different settings or cross-checks
   - `"Add this URL the client just shared"` → agent extracts patterns from it and feeds Phase 8

6. **Final output** — `passive-recon-output-<ORG>.md` in the engagement directory. Agent tells you the path.

**Total time:** 30–90 minutes depending on attack surface. You're not glued to it the whole time — most of the work is automated, you only step in at checkpoints or when something looks off.

---

## What "supervised" really means

| You don't have to | You DO want to |
|-------------------|----------------|
| Run scripts manually | Watch the brief progress updates |
| Read every command output | Review the related-domain list at Checkpoint 1 |
| Memorise the methodology | Confirm wildcard handling at Checkpoint 2 |
| Verify each phase by hand | Speak up if a result looks wrong |
| Write the report yourself | Tell the agent which finding to emphasise |

The agent is the doer. You're the navigator. When you see something that doesn't smell right (`"hmm, only 12 subdomains for an org that size?"`), call it out — the agent will diagnose.

---

## Common interventions you'll do

### "Add these URLs the client just shared"

Mid-engagement, the client mentions a few URLs in chat. Tell the agent:

```
The client just shared these targets — incorporate them and check if the patterns help us find more:
- portal.acme-internal.com
- apps.acme-internal.com
```

The agent will: add them to seed_roots, check for wildcard cert on `acme-internal.com`, extract `portal` / `apps` as prefixes, run Phase 8 permutation with those new prefixes.

### "I don't think those are real subsidiaries"

After Checkpoint 1, you spot 3 unrelated domains in the candidate list:

```
Drop: foo-corp.com, bar-inc.net, baz.io — those are different companies, false positives from reverse-WHOIS.
Add: acme-cloud.com — known internal hosting domain the client mentioned in kickoff.
```

Agent re-curates and proceeds.

### "Re-run Phase 3 — crt.sh was 502 last time"

If you noticed crt.sh failed during the original Phase 3 run, ask for a re-run on just that source. Agent re-queries crt.sh and merges new findings.

### "Why did Shodan find this hostname but DNS doesn't resolve it?"

Agent should have flagged this at Checkpoint 4, but if not — call it out. Common cause: the hostname existed at scan time, was decommissioned, but Shodan's record persisted.

---

## API Keys (Optional but Recommended)

Export these in your shell or `.env` file BEFORE invoking Claude CLI:

| Variable | Provider | Free Tier? |
|----------|----------|-----------|
| `SHODAN_API_KEY` | Shodan | Limited search; better with paid |
| `GITHUB_TOKEN` | GitHub PAT | 30 req/min unauth → 5000 req/h with PAT |
| `HIBP_API_KEY` | HaveIBeenPwned | Paid only |
| `DEHASHED_USERNAME` + `DEHASHED_API_KEY` | DeHashed | Paid only |
| `INTELX_API_KEY` | IntelelligenceX | Free tier with registration |
| `HUNTER_API_KEY` | Hunter.io | Free tier 25 searches/month |

If a key is missing, agent **does not silently skip** — it pauses at Checkpoint 3 and asks.

---

## Report Output

Saved at:
```
/home/kali/engagements/<org-slug>-<YYYYMMDD>/reports/passive-recon-output-<ORG>.md
```

Sections map directly to FireCompass Internal Email Template #2 (Passive Scan Highlights):

| Report Section | Template #2 Bullet |
|----------------|---------------------|
| § 0 Executive Summary | Top of email |
| § 4.1 Live 200 OK Apps | "Active Applications: NN" |
| § 5 Pattern Permutation | Talk track for client call ("hidden internal apps recovered") |
| § 6 IP / ASN | "Active IPs: NN" |
| § 7 Shodan Exposure | "Sensitive Open Services" |
| § 8 Cloud Buckets | New finding category — flag separately |
| § 9 Email OSINT | "Leaked Credentials: NN" |

---

## Fallback — Standalone Scripts (Without Claude CLI)

Only use this when:
- Claude CLI isn't available on the machine you're working from
- You want to verify or re-run a single phase by hand
- You're auditing the agent's output and want to compare against ground-truth scripts

```bash
export ENGAGEMENT_DIR=/home/kali/engagements/acme-corp-$(date +%Y%m%d)
export PRIMARY_DOMAIN=acme.com
export ORG_NAME="Acme Corp"

bash scripts/00_setup_engagement.sh "$ORG_NAME" "$PRIMARY_DOMAIN"
bash scripts/01_seed_collection.sh
# review $ENGAGEMENT_DIR/seeds/seed_roots.txt — remove false positives, add known subsidiaries

bash scripts/02_wildcard_check.sh
bash scripts/03_subdomain_enum.sh
bash scripts/04_js_mining.sh
bash scripts/05_google_dork.sh
bash scripts/06_shodan_lookup.sh

python3 scripts/07_dns_resolve_probe.py
python3 scripts/08_pattern_permutation.py    # critical if wildcard roots flagged
python3 scripts/07_dns_resolve_probe.py      # re-run to probe new permutation hits

bash scripts/09_asn_netblock.sh
bash scripts/10_shodan_ports.sh
bash scripts/11_leaked_creds.sh
bash scripts/12_github_leaks.sh
bash scripts/13_cloud_buckets.sh
bash scripts/14_email_osint.sh

bash tests/self-audit.sh                       # fail loudly if anything skipped
python3 scripts/99_generate_report.py
```

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| `subfinder: command not found` | Run `bash INSTALL.sh` |
| Agent stops mid-phase | Probably at a hard checkpoint — read the question and answer |
| Agent claims phase complete but file is empty | Run `bash tests/self-audit.sh` — it will flag the gap |
| `crt.sh returns 502` | Intermittent. Other sources cover. Tell agent to re-run when it recovers. |
| `httpx hangs with -follow-redirects` | We don't use httpx for redirects — Python concurrent curl is in Phase 7 |
| Agent finds nothing on a wildcard root | Either insufficient prefixes (Phase 3 returned little), or genuinely air-gapped. Cross-check with Phase 4 (JS mining) and Phase 12 (GitHub) — tell the agent to look there. |
| Agent acts confidently but you suspect hallucination | Open the engagement directory and grep the data files. Every claim should be sourced from a real file under `$ENGAGEMENT_DIR/`. If not, that's a bug — report in LESSONS_LEARNED.md. |
