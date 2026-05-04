# METHODOLOGY — Why This Approach Is Best

This document explains the reasoning behind every phase, the tradeoffs made, and why the architecture is designed this way. Not a tutorial — a defensive document for senior reviewers.

---

## The Goal Statement

> **Nothing should be missed in passive recon — subdomains, related domains, IPs, web applications.**

That's the user's exact requirement. "Nothing missed" is not literally achievable (you cannot enumerate what doesn't exist publicly), but the *spirit* of the requirement is achievable: no asset that has any public footprint should escape detection.

---

## The Failure Mode This Architecture Addresses

### Real incident — prior engagement (April 2026)

- Client used a wildcard SSL cert on their internal hosting domain (covering all subdomains under that domain)
- Result: every CT-log-based passive subdomain tool (subfinder, amass, crt.sh, certspotter, assetfinder) returned **zero individual subdomain results** for the internal hosting domain — only the wildcard was logged
- Six live production web applications on that domain were missed during passive recon, all responding 200 / 302 on HTTPS
- Client provided them in the target-selection meeting. Analyst had no explanation. Embarrassing gap.

### Root cause

Wildcard certificate covers all subdomains with one cert, so only ONE entry exists in CT logs. CT-log-based passive enumeration is fundamentally blind on wildcard domains. The fix is structural — the workflow must detect wildcard certs and trigger compensating techniques.

---

## Why Each Phase Exists

### Phase 1 — Seed + Related Domain Discovery

**Why:** A primary domain rarely covers the full footprint. Companies own dozens of domains: acquisitions, regional brands, product domains, tenant clouds, M&A holdings. Skip this and you miss whole subsidiaries.

**What works:**
- WHOIS reverse lookup (whoxy, viewdns) — finds domains registered to the same org
- ASN pivots — IPs in the same ASN often serve other org-owned domains
- Favicon hashing — same favicon across multiple domains often = same org
- Tracking IDs (Google Analytics, AdSense) — shared IDs = same parent
- Manual: Crunchbase / Wikipedia / annual reports for known acquisitions

**Tradeoff:** WHOIS reverse lookup has false positives (random domains using same registrar). The script flags these but requires manual review.

### Phase 2 — Wildcard Cert Detection (mandatory)

**Why:** The wildcard-cert failure mode (see LESSONS_LEARNED.md #1). Skipping this is the #1 cause of missed assets.

**What works:**
- `openssl s_client` to fetch the cert SANs
- Match `DNS:*.<root>` in the SANs

**What also helps:**
- DNS wildcard check (`dig +short A randomname.<root>`) — if a non-existent name resolves, the org has wildcard DNS too, requiring different filtering

**Why it's a separate phase:** It gates Phase 8 (pattern permutation). If wildcards exist, permutation MUST run. If not, Phase 8 is optional.

### Phase 3 — Multi-source Subdomain Enumeration

**Why:** Different sources have different coverage. crt.sh has CT logs. urlscan has real browser captures. RapidDNS has historical DNS. OTX has threat intel. No single source is complete; aggregating all reduces blind spots.

**Why 10+ sources:**
- Some sources rate-limit (crt.sh frequently 502s)
- Some are incomplete for certain TLDs
- Cross-checking reveals which subdomains are confirmed by multiple sources (high confidence) vs. only one (worth verifying)

**Tradeoff:** Slower than running just subfinder, but coverage matters more than speed in passive phase.

### Phase 4 — JS / Source Mining

**Why:** Internal apps reference each other in JavaScript redirects, fetch calls, and config blobs. These hostnames don't appear in CT logs (no public cert) but are embedded in production code on public-facing apps.

**What works:**
- katana (ProjectDiscovery) — fast JS-aware crawler
- gospider — alternative crawler
- Both grep for hostnames matching the wildcard root

**Why it bypasses wildcard cert blindness:** The internal hostname is in the JS source, not in CT logs.

### Phase 5 — Google / Bing Dorking

**Why:** Search engines index linked subdomains regardless of naming convention. Even a randomly-named internal app, if linked from any public page, is indexed.

**Tradeoff:** Google has aggressive bot protection. We provide ready-made dork URLs for manual browser inspection alongside scraping.

### Phase 6 — Shodan / Censys Passive

**Why:** Shodan's crawler records every Host header and SSL cert it sees. Free InternetDB API requires no key and gives hostname + port + CVE per IP.

**What works:**
- For each resolved IP, query InternetDB
- Filter returned hostnames to in-scope domains

**Why it complements CT logs:** Shodan sees what real scanners observe in the wild. A subdomain that responds to Shodan crawler with a Host header is recorded — even without a public cert.

### Phase 7 — DNS Resolve + HTTP Probe

**Why:** Subdomain enumeration produces *candidates*. Only DNS resolution confirms existence. Only HTTP probing confirms a live web app.

**Why Python instead of httpx:** httpx-toolkit hangs intermittently with `-follow-redirects` (proven in a prior engagement). Python concurrent.futures + curl is more reliable.

### Phase 8 — Pattern Permutation (NOT Brute Force)

**Why this is the key innovation:**

Wordlist brute force tries 10M+ generic words. Custom internal project-code names are not in any wordlist. Brute force misses them entirely.

Pattern permutation derives the naming convention from what passive sources DID return, then tests targeted variants. In a prior engagement, after passive surfaced one infrastructure tier (e.g. `[prefix]*oam` auth tier), permutation generated paired tiers (e.g. `[prefix]*web` application tier) — ~360 queries found ALL of the missed hosts plus several new hosts the client didn't even mention.

**Why brute force is the LAST resort:**
- 10M wordlist queries take hours and miss custom names
- 360 pattern permutations take seconds and find them
- Pattern is derived from real data — not guessed

### Phase 9 — IP / ASN / Netblock

**Why:** Once you have IPs, the ASN reveals all netblocks owned by the same org. This finds additional client-controlled IP space (sometimes containing internal apps, dev environments, CI runners).

### Phase 10 — Shodan Ports

**Why:** Active port scanning is out of scope in passive phase. Shodan's free InternetDB gives a fast list of ports + known CVEs per IP without sending any traffic. Same data for free.

### Phase 11 — Leaked Credentials

**Why:** Public breach data often contains employee creds reusable against the client's external apps. This is the #1 actionable finding clients act on. Source: HIBP, DeHashed, IntelX.

### Phase 12 — GitHub Leaks

**Why:** Developers leak secrets — API keys, passwords, internal hostnames — into public repos. Even if no credentials, internal hostnames in JS/config files in public repos bypass wildcard cert blindness.

### Phase 13 — Cloud Bucket Discovery

**Why:** Misconfigured S3/GCS/Azure buckets are a top breach vector. Bucket names follow predictable patterns. HTTP 200 = public, 403 = exists private (still a finding), 404 = doesn't exist.

### Phase 14 — Email / People OSINT

**Why:** Names + emails define the phishing simulation scope, identify named admin accounts, and surface shared mailboxes worth flagging in the report.

---

## Why This Architecture Beats a Single Agent Prompt

### Problem with single-prompt agents:
1. **Untestable** — when the agent says "Phase 7 complete: 134 subdomains," there's no way to verify without rerunning
2. **Stale wordlists** — pattern suffixes learned in one engagement don't propagate to others
3. **Hallucination risk** — without external verification, the agent can confidently report fabricated results
4. **Single point of failure** — if the prompt has a bug, every engagement inherits it

### How this repo solves each:
1. **Testable** — every phase outputs to a file. `tests/self-audit.sh` verifies them with real `[ -s file ]` checks. No checkbox-claim is accepted.
2. **Wordlist evolution** — `wordlists/subdomain-suffixes.txt` and `wordlists/cloud-bucket-variants.txt` are updated per engagement. Lessons compound.
3. **Verification through file outputs** — every claim in the report is sourced from a real data file. Reviewers can grep the engagement directory to verify.
4. **Modular fixes** — bug in Phase 8? Fix `scripts/08_pattern_permutation.py`, push, all engagements benefit immediately.

---

## Why Some Things Are NOT Automated

| Step | Why manual |
|------|-----------|
| Reviewing seed_roots.txt for false positives | Reverse WHOIS has false positives. Human judgement required. |
| Opening Google/Bing dork URLs in browser | Aggressive anti-bot — automation gets CAPTCHAs |
| Reviewing leaked cred JSON | Sensitive — analyst should verify before reporting to client |
| Adding known acquisitions | Crunchbase / Wikipedia content varies — judgement required |

The agent / scripts produce the data. The analyst reviews it. That balance is intentional.

---

## When This Approach Will Still Miss Something

Be honest: there are scenarios where even this stack fails.

| Scenario | Why missed | Mitigation |
|----------|-----------|------------|
| Subdomain only resolved internally (split DNS) | No public DNS record exists | None possible passively. Active phase from inside the network. |
| Subdomain on a domain we never knew the org owns | Phase 1 didn't find the parent | Improve Phase 1 — add more reverse-WHOIS / acquisition sources |
| Subdomain with no cert AND no public reference AND not in Shodan | True air-gap | Document as finding ("good segmentation"). Active brute force won't find it either if the name is non-standard. |
| API-only host with no DNS record (IP-direct) | No DNS to enumerate | Active scanning of ASN netblocks would find it (but that's Step 2) |

Document these in `LESSONS_LEARNED.md` if they happen.

---

## Why HackTricks + PayloadsAllTheThings Are The Methodology Foundation

These two repos are continuously updated by hundreds of contributors. They are the de-facto industry-standard methodology references for offensive security. Citing them gives:

1. **Defensibility** — reviewers and clients can verify the technique
2. **Traceability** — when a finding is challenged, the methodology is documented
3. **Currency** — kept up to date with new techniques
4. **No analyst-specific knowledge required** — any new team member can read the citation and understand the rationale

If a technique isn't in these repos but is needed (e.g. cloud-specific bucket enumeration), we cite the alternative source explicitly — never fabricate.
