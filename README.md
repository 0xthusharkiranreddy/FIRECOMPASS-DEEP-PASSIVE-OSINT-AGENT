#Deep Passive OSINT Agent

> **Goal:** Map the complete external attack surface — subdomains, related domains, IPs, web applications — with **zero misses**. Every step is methodology-cited (HackTricks / PayloadsAllTheThings), hypothesis-driven, and reproducible.

---

## Why This Exists

This repository was born from a real failure on a prior engagement: a wildcard SSL certificate on the client's internal hosting domain made every CT-log-based passive subdomain tool blind to **6 publicly-reachable production web applications**. The client shared them in the target-selection meeting; the analyst had no explanation. That gap is solved here, structurally.

The repo encodes:
- **20 phases** of passive recon, each cited to HackTricks / PayloadsAllTheThings paths
- **The wildcard-cert lesson** — `Phase 2` (wildcard detection) and `Phase 8` (pattern permutation) directly counter that failure
- **A Claude Code agent** that orchestrates the phases automatically when invoked
- **Phase scripts** that the agent uses as its execution layer
- **A real-time engagement log** (`engagement_logs.md`) — verbatim CLI transcript written to disk as it happens; survives conversation compaction; everything you see in the terminal is in this file
- **A self-audit harness** — hard checks that fail the engagement if any phase was skipped

---

## The Most Important Thing To Understand

### The agent IS the product. The scripts are its tools.

There is a critical distinction that determines whether this system works or produces hollow output:

```
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   CLAUDE CODE AGENT  (agents/firecompass-passive-recon.md)      │
│                                                                 │
│   THE BRAIN:                                                    │
│   ✓ Reads the target and builds a mental model first            │
│   ✓ Forms a hypothesis before every technique                   │
│   ✓ Chooses which tools to run and justifies why                │
│   ✓ Reads the output and interprets what it means               │
│   ✓ Detects anomalies ("89 subdomains is LOW for this org")     │
│   ✓ Decides what to do NEXT based on findings                   │
│   ✓ Detects wildcard cert → automatically pivots to Phase 8     │
│   ✓ Writes reasoning, decisions, and findings as it goes        │
│   ✓ Asks you at checkpoints when something is ambiguous         │
│   ✓ Produces a report that explains HOW it thought              │
│                                                                 │
└───────────────────────────────┬─────────────────────────────────┘
                                │ calls
                                ▼
┌─────────────────────────────────────────────────────────────────┐
│                                                                 │
│   BASH/PYTHON SCRIPTS  (scripts/00–16, 99)                      │
│                                                                 │
│   THE ARMS:                                                     │
│   ✓ Fast, reliable execution of multi-step shell work           │
│   ✓ Produce structured output (TSV files) the agent reads       │
│   ✓ Write raw findings to engagement_logs.md via lib/log.sh     │
│   ✗ Cannot form hypotheses                                      │
│   ✗ Cannot interpret results                                    │
│   ✗ Cannot decide what to do next                               │
│   ✗ Cannot pivot when something unexpected appears              │
│   ✗ Cannot write the reasoning layer of the report              │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

**Running the scripts without the agent gives you data collection without intelligence.**

You would get TSV files full of subdomains, headers, and DNS records — but no hypothesis about what they mean, no decision about what to do when the subdomain count is suspiciously low, no pivot when a wildcard cert is detected, no strategic narrative. A human expert would still need to interpret every output manually. The scripts without the agent are just fast bash — not a recon agent.

**The scripts exist so the agent doesn't waste context typing long pipelines.** They are pre-written, reliable tools that the agent calls via its `Bash` tool. They are not designed to be a standalone product.

---

## What "Human-in-the-Loop Mode" Actually Means

The correct alternative to "fully autonomous agent" is not "run scripts alone." It is **analyst + agent working together** — which is how this system was developed.

```
You (analyst)  ←──────────────────────────────────────┐
     │                                                 │
     │  "recon acme.com"                               │ you watch, redirect,
     │                                                 │ intervene at checkpoints
     ▼                                                 │
Claude Code Agent                                      │
  - builds target mental model                         │
  - runs Phase 1 → reads output → updates model        │
  - [CHECKPOINT 1] presents findings, asks: ────────────┘
    "Domain is in healthcare, I expect EHR/patient portal
     infrastructure. Does this match your understanding?"
  - you confirm or redirect
  - continues to Phase 2 → detects wildcard cert
  - [CHECKPOINT 2] "Wildcard detected on acme-internal.com.
     CT-log tools will miss subdomains here.
     I'm proceeding to pattern permutation. Confirm?"
  - you approve
  - ... 7 supervised checkpoints total ...
  - final report — you review, the agent explains every decision
```

You are the expert in the loop. The agent does the execution and the reasoning. You validate, redirect, and add context the agent can't know (e.g., "they also have a subsidiary called Acme Labs on a different domain"). This is the mode that produced the wildcard-cert recovery on the prior engagement.

---

## Architecture

```
                ┌────────────────────────────────────┐
                │  agents/firecompass-passive-recon  │  ← Claude Code brain
                └────────────────┬───────────────────┘
                                 │ calls
            ┌────────────────────┼────────────────────┐
            ▼                    ▼                    ▼
  ┌──────────────────┐ ┌───────────────────┐ ┌───────────────────┐
  │  scripts/00–16   │ │ wordlists/*.txt   │ │ references/*.md   │
  │ phase scripts    │ │ permutation lists │ │ HackTricks/PAT    │
  │ (agent's arms)   │ │ (grow per engage) │ │ methodology map   │
  └──────────────────┘ └───────────────────┘ └───────────────────┘
            │
            │ all write to
            ▼
  ┌──────────────────────────────────────────────────────────────┐
  │  engagement_logs.md  (real-time, append-only, survives       │
  │  conversation compaction — full audit trail on disk)         │
  └──────────────────────────────────────────────────────────────┘
            │
            ▼
  ┌─────────────────────┐
  │   tests/self-audit  │  ← real verification, not a checkbox
  └─────────────────────┘
            │
            ▼
  ┌────────────────────────────────────────────────────────────┐
  │  passive-recon-output-[ORG].md + .html                     │
  │  (cited report with full reasoning chain, not tool output) │
  └────────────────────────────────────────────────────────────┘
```

---

## The 20 Phases — Mapped to Methodology

| # | Phase | Script | What | Key Reference |
|---|-------|--------|------|---------------|
| 0 | Engagement Setup | `00_setup_engagement.sh` | Directory structure, `engagement_logs.md` init | — |
| 0.5 | Target Visualisation | *(agent only)* | Build mental model BEFORE any tool runs | HackTricks `external-recon-methodology` § Intro |
| 1 | Seed + Related Domain Discovery | `01_seed_collection.sh` | WHOIS, ASN, favicon, tenant pivots | HackTricks § Acquisitions |
| 2 | **Wildcard Cert Detection** ⚠ | `02_wildcard_check.sh` | `openssl s_client` per root | Internal lesson — prior engagement |
| 3 | Multi-source Subdomain Enum | `03_subdomain_enum.sh` | 10+ passive sources in parallel | HackTricks § Subdomains |
| 3.5 | TLS Cert Deep Inspection | `03b_tls_cert_inspect.sh` | Extract SANs (new subdomain source), expiry, internal CAs | HackTricks § Certificate Transparency |
| 4 | JS / Source Mining | `04_js_mining.sh` | katana + gospider, grep hostnames | HackTricks § JS files |
| 5 | Google / Bing Dorking | `05_google_dork.sh` | `site:` operators | HackTricks § Google Dorks |
| 6 | Shodan Passive Lookup | `06_shodan_lookup.sh` | InternetDB free tier | HackTricks § Shodan |
| 7 | DNS Resolve + HTTP Probe | `07_dns_resolve_probe.py` | dnsx + concurrent curl | HackTricks § DNS |
| 7.5 | TLS + App Fingerprinting | `07b_live_app_fingerprint.sh` | CDN / WAF / CMS / framework from response headers | HackTricks § Web Server Identification |
| 7.6 | Web Surface Harvest | `07c_web_surface_harvest.sh` | robots.txt, sitemap, security.txt, .well-known/ | HackTricks § Web Recon |
| 7.7 | Wayback URL Crawl | `07d_wayback_url_crawl.sh` | Historical URLs, deleted admin panels, backup files | HackTricks § Wayback Machine |
| 8 | **Pattern Permutation** 🎯 | `08_pattern_permutation.py` | Extract patterns, generate variants — wildcard bypass | Internal lesson + HackTricks § DNS Bruteforce |
| 9 | IP / ASN / Netblock | `09_asn_netblock.sh` | Team Cymru, bgp.he.net | PAT `Network Discovery.md` |
| 10 | Shodan Open Ports | `10_shodan_ports.sh` | InternetDB per IP | HackTricks § Shodan |
| 11 | Leaked Credentials | `11_leaked_creds.sh` | HIBP, DeHashed, IntelX | HackTricks `database-leaks.md` |
| 12 | GitHub / Source Leaks | `12_github_leaks.sh` | trufflehog, dorks | HackTricks `github-leaked-secrets.md` |
| 12.5 | Beyond-GitHub Code Search | `12b_beyond_github_code.sh` | GitLab, Bitbucket, Codeberg, Pastebin | HackTricks `wide-source-code-search.md` |
| 13 | Cloud Bucket Discovery | `13_cloud_buckets.sh` | S3, GCS, Azure variants | hacktricks-cloud `aws-unauthenticated-enum-access` |
| 14 | Email / People OSINT | `14_email_osint.sh` | theHarvester, Hunter.io, job postings | HackTricks § Emails |
| 14.5 | DNS Records Intelligence | `14b_dns_records_intel.sh` | MX/SPF/DKIM/DMARC — SaaS footprint + phishing gaps | HackTricks `pentesting-dns.md` |
| 15 | Mobile App Surface | `15_mobile_app_surface.sh` | App Store / Google Play metadata, bundle IDs | HackTricks Android/iOS recon |
| 16 | Document Metadata | `16_document_metadata.sh` | exiftool on public PDFs/docs — usernames, UNC paths | HackTricks § Metadata |

⚠ = mandatory gate  🎯 = where most engagements find missed assets

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/0xthusharkiranreddy/FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT
cd FIRECOMPASS-DEEP-PASSIVE-OSINT-AGENT

# 2. Install prerequisites
bash INSTALL.sh

# 3. Install the agent into Claude Code
mkdir -p ~/.claude/agents
cp agents/firecompass-passive-recon.md ~/.claude/agents/

# 4. Start an engagement inside Claude Code
> use firecompass-passive-recon to recon acme.com (Acme Corp)
```

The agent will:
1. Build a target mental model (Phase 0.5) and present it to you
2. Run phases sequentially, writing to `engagement_logs.md` in real time
3. Stop at 7 supervised checkpoints for your input
4. Deliver `passive-recon-output-[ORG].md` + `.html` with full reasoning chain

Output lands in `/home/kali/engagements/<org-slug>-<date>/`.

---

## The Engagement Log — Your CLI Session, Saved To Disk

### The short answer: yes, what you see in the CLI is what goes into the log.

Every response the agent writes, every command that runs with its full output, every file the agent reads and interprets, every checkpoint exchange — all of it is written to `$ENGAGEMENT_DIR/engagement_logs.md` in real time as it happens.

**Why this matters:** Claude Code conversations get compacted. When that happens, all the reasoning, all the command outputs, all the findings visible in your terminal disappear from context. The log is the permanent on-disk copy that survives compaction — you can open it during the engagement, after the engagement, or months later and read exactly what happened.

---

### How it works

The agent writes to the log after every single action. There is no batch-at-end or summary mode — it writes as it goes. Four types of entries are written:

| Entry type | Emoji | When written | What it contains |
|---|---|---|---|
| Agent response | `🤖` | After every message Claude writes | The full text verbatim — same as what you read in the terminal |
| Command | `⚡` | Before + after every command runs | The command + its complete output (up to 200 lines, with pointer to full file) |
| File read | `📄` | After every file the agent inspects | Which file, line count, and key observations — what it means, not just what it says |
| Checkpoint | `🛑` | At every supervised pause | What the agent presented, your response, and the decision made |

> **How the log is written:** The agent actively calls `log_agent_response()`, `log_cmd_with_output()`, `log_read_result()`, and `log_checkpoint()` from `scripts/lib/log.sh` after each action. It is not an automatic terminal hook — it is enforced by the agent prompt as a mandatory protocol. Rule 8 of the agent's hard rules states: *"If it happened and it's not in the log, it didn't happen."*

---

### What the log looks like

```
---
### 🤖 Agent — 2026-05-05 14:31:10

Phase 3 subdomain enumeration complete. subfinder returned 89 hosts.
crt.sh returned ZERO — but subfinder returned 89. This divergence is
a wildcard cert signal: crt.sh sees a single *.acme.com entry and cannot
enumerate individual subdomains. subfinder queries non-CT sources so it
still sees hosts, which is why the counts differ.

Checking Phase 2 wildcard output to confirm.

---
### ⚡ Command — 2026-05-05 14:31:15
**Purpose:** Confirm wildcard cert detection from Phase 2
**Command:**
    cat /home/kali/engagements/acme-corp-20260505/seeds/wildcard_roots.txt
**Output** (1 line):
    acme-internal.com

---
### 🤖 Agent — 2026-05-05 14:31:22

Confirmed. acme-internal.com has a wildcard cert. CT-log tools are blind
to every subdomain under it. Phase 3 returning 0 for acme-internal.com
is expected — not a gap in methodology.

This is the same failure mode that hit the prior engagement. Phase 8
(pattern permutation) on acme-internal.com is now the priority before
I continue.

---
### 🛑 Checkpoint 2 — 2026-05-05 14:31:35

**Presented to analyst:**
Wildcard cert *.acme-internal.com detected (same scenario as the prior
engagement). CT-log tools returned 0 subdomains for this domain. I am
pivoting to Phase 8 pattern permutation using prefixes extracted from
acme.com (dev, staging, vpn, mail...). Do you have any hostnames under
acme-internal.com from the client kickoff that I should add as seeds?

**Analyst response:** "Yes — they mentioned webmail and sso in the call."

**Decision:** Added webmail, sso as confirmed seed prefixes for Phase 8
permutation on acme-internal.com. These will anchor the pattern generation.
Proceeding.

---
### ⚡ Command — 2026-05-05 14:32:00
**Purpose:** Phase 8 — pattern permutation on acme-internal.com
**Command:**
    python3 scripts/08_pattern_permutation.py
**Output** (14 lines):
    webmail.acme-internal.com → 10.0.1.45 [LIVE]
    sso.acme-internal.com → 10.0.1.50 [LIVE]
    dev.acme-internal.com → 10.0.1.12 [LIVE]
    staging.acme-internal.com → 10.0.1.13 [LIVE]
    vpn.acme-internal.com → NXDOMAIN
    mail.acme-internal.com → 10.0.1.5 [LIVE]
    ...

- `14:32:05` 🟠 [HIGH] 6 live hosts recovered under wildcard domain via permutation
```

The log reads as a continuous session transcript. No gaps between what you saw in the terminal and what is on disk.

---

### Recovering after compaction

If your conversation is compacted mid-engagement, read the log to resume:

```bash
# Where you left off
tail -80 $ENGAGEMENT_DIR/engagement_logs.md

# What decisions were made
grep "^### 🛑 Checkpoint" $ENGAGEMENT_DIR/engagement_logs.md

# What commands ran
grep "^### ⚡ Command" $ENGAGEMENT_DIR/engagement_logs.md

# Critical findings
grep "CRITICAL\|HIGH\]\|NOTABLE\]" $ENGAGEMENT_DIR/engagement_logs.md
```

---

## What "Nothing Missed" Means In Practice

| Class of asset | How we don't miss it |
|----------------|----------------------|
| Subdomains in CT logs | 10+ passive sources cross-checked (Phase 3) |
| Subdomains under wildcard certs | Wildcard detected (Phase 2) → pattern permutation (Phase 8) — proven: 6/6 missed hosts recovered in prior engagement |
| SANs on live certs | TLS deep inspection extracts full SAN list (Phase 3.5) |
| Subdomains referenced in JS | katana + gospider on every live primary app (Phase 4) |
| Subdomains indexed by search engines | Google / Bing dork (Phase 5) |
| Subdomains seen by Shodan | InternetDB lookup (Phase 6) |
| Historical URLs / deleted pages | Wayback CDX crawl (Phase 7.7) |
| Related domains / acquisitions | WHOIS, ASN, favicon, tenant pivots (Phase 1) |
| IP space owned by client | ASN enumeration (Phase 9) |
| Open ports on those IPs | Shodan InternetDB (Phase 10) |
| Cloud buckets | Variant generation against S3/GCS/Azure (Phase 13) |
| Code / secrets leaks | GitHub + GitLab + Bitbucket + pastes (Phase 12 + 12.5) |
| Leaked credentials | HIBP / DeHashed / IntelX (Phase 11) |
| Email infrastructure / SaaS footprint | SPF/MX/DMARC/TXT records (Phase 14.5) |
| DMARC enforcement gaps | Phase 14.5 flags p=none and missing DMARC → phishing risk |
| Mobile app surface | App Store / Google Play enumeration (Phase 15) |
| Internal usernames in documents | exiftool metadata on public PDFs (Phase 16) |

If after all phases an asset still isn't found, it has zero public footprint — which is itself a finding ("good segmentation"), not a recon gap.

---

## Repo Layout

```
.
├── README.md                  ← you are here
├── INSTALL.sh                 ← prerequisite installer
├── LESSONS_LEARNED.md         ← incidents we will not repeat
├── agents/
│   └── firecompass-passive-recon.md  ← the brain (install to ~/.claude/agents/)
├── scripts/
│   ├── lib/
│   │   └── log.sh             ← shared engagement_logs.md writer (sourced by all scripts)
│   ├── 00_setup_engagement.sh
│   ├── 03b_tls_cert_inspect.sh
│   ├── 07b_live_app_fingerprint.sh
│   ├── 07c_web_surface_harvest.sh
│   ├── 07d_wayback_url_crawl.sh
│   ├── 12b_beyond_github_code.sh
│   ├── 14b_dns_records_intel.sh
│   ├── 15_mobile_app_surface.sh
│   ├── 16_document_metadata.sh
│   └── 99_generate_report.py
├── wordlists/                 ← curated permutation lists (grow per engagement)
├── references/                ← HackTricks/PAT path mapping per phase
├── tests/
│   └── self-audit.sh          ← run before final report; fails if any phase skipped
└── examples/                  ← anonymised sample engagement output
```

---

## Contributing — Add a Lesson

When an engagement teaches you something new:

1. Add the lesson to `LESSONS_LEARNED.md` with: incident date, what was missed, root cause, fix
2. If the fix is a new technique inside an existing phase — update the relevant script
3. If the fix is a new wordlist entry — append to the appropriate file in `wordlists/`
4. Open a PR. Reviewer verifies the methodology citation and merges.

Every fix becomes structural — the next engagement runs with the lesson built in, no human memory required.

---

## Maintainer

**Thushar Kiran Thiruthani** — Senior Security Analyst, FireCompass POC Team
Email: `thusharkiran.tthiruthani@firecompass.com`

---

*"The agent is the intelligence. The scripts are its hands. Running the hands without the brain gives you data, not recon."*
