# LESSONS LEARNED — Engagement Incidents That Shaped This Repo

Each entry: incident date · what was missed · root cause · structural fix encoded in repo.

Client-identifying information is intentionally redacted. The methodology and structural fixes are what matter — they apply to every future engagement regardless of which client triggered the lesson.

---

## 1. Wildcard Certificate Blindness (April 2026)

**What happened:** During the Active Scan target-selection meeting, the client provided a list of target URLs. Several of them — internal application servers on the client's private hosting domain — had not been discovered during passive recon. All were publicly reachable on HTTPS (302 / 200). The analyst could not explain the gap on the call.

**Root cause:** The internal hosting domain was protected by a single wildcard SSL certificate (`*.<internal-domain>`). CT-log-based passive subdomain tools (subfinder, amass, crt.sh, certspotter, assetfinder) only see the wildcard entry — never individual subdomains. Without a wildcard-specific compensating workflow, recon was structurally blind to those hosts.

The naming convention also defeated generic wordlists: the missed hosts followed an internal project-code pattern (e.g. `[project][env][tier]`) where the discovered passive results showed only one tier (e.g. the `*oam` auth tier) and the missed assets were on the paired `*web` application tier. A 10M-entry wordlist would not contain custom internal project codes.

**Structural fix encoded in repo:**
- `scripts/02_wildcard_check.sh` — mandatory wildcard cert detection on every root domain
- `scripts/08_pattern_permutation.py` — derives naming patterns from already-discovered subdomains and generates targeted permutations on the same prefix space
- `wordlists/subdomain-suffixes.txt` — curated suffix list (web, pweb, oam, prod, etc.) that recovers paired-tier hosts
- `tests/self-audit.sh` — fails the engagement if a wildcard root is flagged but permutation didn't run
- `agents/firecompass-passive-recon.md` — Phase 2 is mandatory; Phase 8 is conditional on Phase 2 result

**Verification of fix:** Pattern permutation was tested in-session against the missed hosts. Result: every missed host recovered in ~360 DNS queries. Several additional hosts the client didn't mention were also discovered (paired tiers and adjacent project codes).

---

## (Add new entries below)

### Format for new entries

```markdown
## N. [Generic Failure Description] ([Month YYYY])

**What happened:** [Anonymised — describe the failure mode without client identifiers]

**Root cause:** [Technical reason — be specific about the mechanism, not the target]

**Structural fix encoded in repo:**
- [files / scripts / wordlists / agent changes]

**Verification of fix:** [How you proved it works — also anonymised]
```

The point is to make every failure structural. After the fix, it should be impossible for the same failure to happen on the next engagement, regardless of who runs the recon.

**Redaction rules for entries:**
- Never include client name, primary domain, internal hostnames, IP addresses, or specific subdomain names
- Describe naming patterns generically (e.g. "internal project-code pattern") not literally
- Cite the technical mechanism, not the target — the fix has to generalise
