# FireCompass Deep Passive OSINT Agent

> **Goal:** Map the complete external attack surface of any FireCompass POC client — subdomains, related domains, IPs, web applications — with **zero misses**. Every step is methodology-cited (HackTricks / PayloadsAllTheThings), hypothesis-driven, and reproducible.

---

## Why This Exists

This repository was born from a real failure on a prior engagement: a wildcard SSL certificate on the client's internal hosting domain made every CT-log-based passive subdomain tool blind to **6 publicly-reachable production web applications**. The client shared them in the target-selection meeting; the analyst had no explanation. That gap is solved here, structurally.

The repo encodes:
- **14 phases** of passive recon, each cited to HackTricks / PayloadsAllTheThings paths
- **The wildcard-cert lesson** — `Phase 2` (wildcard detection) and `Phase 8` (pattern permutation) directly counter that failure
- **A Claude Code agent** that orchestrates the phases automatically when invoked
- **Standalone scripts** so each phase can be run manually without the agent
- **A self-audit harness** — 10 hard checks that fail the engagement if any phase was skipped

---

## Architecture — Why This Approach Is Better Than a Single Agent File

A single agent prompt has three problems:
1. **Untestable** — you cannot rerun "phase 4" by itself if the agent stalls
2. **Stale wordlists** — patterns learned from one engagement (e.g. `*oam` paired with `*web`) don't propagate
3. **No verification** — the agent says "self-audit complete" but there's no proof

This repo solves all three:

```
                ┌────────────────────────────────────┐
                │  agents/firecompass-passive-recon  │  ← Claude Code orchestrator
                └────────────────┬───────────────────┘
                                 │ delegates to
            ┌────────────────────┼────────────────────┐
            ▼                    ▼                    ▼
  ┌──────────────────┐ ┌───────────────────┐ ┌───────────────────┐
  │  scripts/01..14  │ │ wordlists/*.txt   │ │ references/*.md   │
  │ phase scripts    │ │ permutation lists │ │ HackTricks/PAT    │
  └──────────────────┘ └───────────────────┘ │ mapping +         │
                                             │ lessons-learned   │
                                             └───────────────────┘
                                 │
                                 ▼
                       ┌─────────────────────┐
                       │   tests/self-audit  │  ← real verification, not a checkbox
                       └─────────────────────┘
                                 │
                                 ▼
                ┌────────────────────────────────────┐
                │  passive-recon-output-[ORG].md     │  ← cited, evidenced report
                └────────────────────────────────────┘
```

Each layer is independently usable:
- **Just need a quick subdomain dump?** Run `scripts/03_subdomain_enum.sh`
- **Want to verify the agent didn't skip a phase?** Run `tests/self-audit.sh`
- **New lesson from an engagement?** Add to `references/lessons-learned.md` — agent reads it at startup

---

## The 14 Phases — Mapped to Methodology

| # | Phase | What | HackTricks / PAT Reference | Why |
|---|-------|------|----------------------------|-----|
| 0 | Engagement Setup | Create directory structure, capture scope | — | Reproducibility |
| 1 | Seed + Related Domain Discovery | WHOIS, ASN, favicon, tenant pivots | HackTricks `external-recon-methodology/README.md` § Acquisitions | Catch subsidiaries, tenant clouds, regional brands |
| 2 | **Wildcard Cert Detection** ⚠ | openssl s_client per root | Internal lesson (prior engagement) | CT-log tools are blind on wildcard domains |
| 3 | Multi-source Subdomain Enum | 10+ passive sources in parallel | HackTricks § Subdomains + PAT `Network Discovery.md` | Maximise breadth |
| 4 | JS / Source Mining | katana + gospider, grep for hostnames | HackTricks § JS files | Internal apps reference each other in JS |
| 5 | Google / Bing Dorking | `site:` operators | HackTricks § Google Dorks | Search engines index linked names |
| 6 | Shodan / Censys Passive | InternetDB free + API | HackTricks § Shodan | Hostname + port indexing |
| 7 | DNS Resolve + HTTP Probe | dnsx + concurrent curl | HackTricks § DNS | Filter live from candidates |
| 8 | **Pattern Permutation** 🎯 | Extract patterns, generate variants | Internal lesson + HackTricks § DNS Bruteforce | Catches custom internal names |
| 9 | IP / ASN / Netblock | Team Cymru, bgp.he.net | PAT `Network Discovery.md` § ASN | Pivot to additional client IP space |
| 10 | Shodan Open Ports | InternetDB per IP | HackTricks § Shodan | Passive port enum, no active scan |
| 11 | Leaked Credentials | HIBP, DeHashed, IntelX | HackTricks `database-leaks.md` | Top breach vector |
| 12 | GitHub / Source Leaks | trufflehog, dorks | HackTricks `github-leaked-secrets.md` | Code/secrets in public repos |
| 13 | Cloud Bucket Discovery | S3, GCS, Azure | hacktricks-cloud `aws-unauthenticated-enum-access` | Misconfigured buckets |
| 14 | Email / People OSINT | theHarvester, Hunter.io | HackTricks § Emails | Phishing scope, named accounts |

⚠ = mandatory  🎯 = where most engagements actually find the missed assets

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/0xthusharkiranreddy/FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT
cd FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT

# 2. Install prerequisites
bash INSTALL.sh

# 3. Drop the agent into Claude Code
mkdir -p ~/.claude/agents
cp agents/firecompass-passive-recon.md ~/.claude/agents/

# 4. Run on a target
#    Inside Claude Code:
> use firecompass-passive-recon to recon acme.com (Acme Corp)
```

Output lands in `/home/kali/engagements/<org-slug>-<date>/reports/passive-recon-output-<ORG>.md`.

---

## Manual Mode (Without Claude Code)

Every phase is a runnable script. To do passive recon manually:

```bash
ORG="Acme Corp"
DOMAIN="acme.com"
export ENGAGEMENT_DIR=/home/kali/engagements/acme-corp-$(date +%Y%m%d)

bash scripts/00_setup_engagement.sh "$ORG" "$DOMAIN"
bash scripts/01_seed_collection.sh
bash scripts/02_wildcard_check.sh
bash scripts/03_subdomain_enum.sh
bash scripts/04_js_mining.sh
bash scripts/05_google_dork.sh        # uses WebSearch — manual step if no API
bash scripts/06_shodan_lookup.sh
python3 scripts/07_dns_resolve_probe.py
python3 scripts/08_pattern_permutation.py
bash scripts/09_asn_netblock.sh
bash scripts/10_shodan_ports.sh
bash scripts/11_leaked_creds.sh
bash scripts/12_github_leaks.sh
bash scripts/13_cloud_buckets.sh
bash scripts/14_email_osint.sh

# Verify nothing was skipped
bash tests/self-audit.sh

# Generate final report
python3 scripts/99_generate_report.py
```

---

## What "Nothing Missed" Means In Practice

This repo cannot guarantee 100% coverage of an unknown internal network — that's mathematically impossible. What it does guarantee:

| Class of asset | How we don't miss it |
|----------------|----------------------|
| Subdomains in CT logs | 10+ passive sources cross-checked (Phase 3) |
| Subdomains under wildcard certs | Wildcard detected (Phase 2) → pattern permutation (Phase 8) — proven in prior engagement: 6/6 missed hosts recovered |
| Subdomains referenced in JS | katana + gospider on every live primary app (Phase 4) |
| Subdomains indexed by search engines | Google / Bing dork (Phase 5) |
| Subdomains seen by Shodan | InternetDB lookup on every resolved IP (Phase 6) |
| Subdomains in Wayback / urlscan | Historical capture replay (Phase 3) |
| Related domains / acquisitions | WHOIS, ASN, favicon, tenant pivots (Phase 1) |
| IP space owned by client | ASN enumeration (Phase 9) |
| Open ports on those IPs | Shodan InternetDB (Phase 10) |
| Cloud buckets | Variant generation against S3/GCS/Azure (Phase 13) |
| Public source / secrets leaks | trufflehog + dorks (Phase 12) |
| Leaked employee credentials | HIBP / DeHashed / IntelX (Phase 11) |

If after all 14 phases an asset still isn't found, it has zero public footprint — which is itself a finding ("good segmentation"), not a recon gap.

---

## Repo Layout

```
.
├── README.md              ← you are here
├── INSTALL.sh             ← prerequisite installer
├── USAGE.md               ← detailed usage walkthrough
├── METHODOLOGY.md         ← deep dive: why each phase, citations
├── LESSONS_LEARNED.md     ← incidents we will not repeat
├── agents/                ← Claude Code agent definition
├── scripts/               ← phase scripts (00–14, 99=report)
├── wordlists/             ← curated permutation lists (grow per engagement)
├── references/            ← HackTricks/PAT path mapping per phase
├── templates/             ← report template
├── examples/              ← anonymised sample engagement output
└── tests/                 ← self-audit harness
```

---

## Contributing — Add a Lesson

Anyone on the team can extend this. When an engagement teaches you something new:

1. Add the lesson to `LESSONS_LEARNED.md` with: incident date, what was missed, root cause, fix
2. If the fix is a new phase or a new technique inside an existing phase — update the relevant script
3. If the fix is a new wordlist entry — append to the appropriate file in `wordlists/`
4. Open a PR. Reviewer (Thushar) verifies the methodology citation and merges.

Every fix becomes structural — the next engagement runs with the lesson built in, no human memory required.

---

## Maintainer

**Thushar Kiran Thiruthani** — Senior Security Analyst, FireCompass POC Team
Email: `thusharkiran.tthiruthani@firecompass.com`

---

*"Your end goal is that nothing should be missed in passive recon. This repo encodes that goal as testable infrastructure."*
