#!/usr/bin/env python3
"""
Phase 8 — Pattern permutation (replaces wordlist brute force)
Reference: Internal lesson (LESSONS_LEARNED.md #1 — wildcard cert blindness)
Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ DNS Bruteforce)

WHY THIS EXISTS — read carefully:
A wordlist of 10M generic words will NOT contain custom internal project-code
names. But once passive recon has surfaced one infrastructure tier (e.g. an
auth/SSO tier with prefix patterns like '[code]oam' or '[code]auth'), the
naming convention becomes apparent — and you can generate the paired application
tier ('[code]web', '[code]app', '[code]prod') in ~360 targeted DNS queries.

This is NOT brute force. This is pattern derivation. In a prior engagement it
recovered ALL of the missed hosts plus several new hosts the client didn't
even mention — paired-tier servers and adjacent project codes.

Run order:
1. Extract prefixes from already-resolved subdomains
2. Combine with proven suffix patterns (web, pweb, oam, *prod, *dev, etc.)
3. Resolve only the permutations (skip ones that are already known)
4. Add common generic names per root as a safety net
"""
import os
import re
import sys
import socket
import concurrent.futures as cf
from pathlib import Path

ENG = os.environ.get("ENGAGEMENT_DIR")
if not ENG:
    sys.exit("export ENGAGEMENT_DIR")
ENG = Path(ENG)

SEEDS = (ENG / "seeds" / "seed_roots.txt").read_text().splitlines()
SEEDS = [s.strip() for s in SEEDS if s.strip()]

WILDCARD_FILE = ENG / "seeds" / "wildcard_roots.txt"
wildcards = []
if WILDCARD_FILE.exists():
    wildcards = [l.strip() for l in WILDCARD_FILE.read_text().splitlines() if l.strip()]

if not wildcards:
    print("[*] No wildcard roots flagged — running permutation on ALL roots as safety net")
    wildcards = SEEDS

resolved_file = ENG / "resolved" / "resolved_hosts.txt"
known = set()
if resolved_file.exists():
    known = {l.strip().lower() for l in resolved_file.read_text().splitlines() if l.strip()}

# load curated suffix wordlists
HERE = Path(__file__).resolve().parent.parent
SUFFIX_FILE = HERE / "wordlists" / "subdomain-suffixes.txt"
COMMON_FILE = HERE / "wordlists" / "common-subdomains.txt"
suffixes = [l.strip() for l in SUFFIX_FILE.read_text().splitlines() if l.strip() and not l.startswith("#")]
common = [l.strip() for l in COMMON_FILE.read_text().splitlines() if l.strip() and not l.startswith("#")]

# extract prefixes from known subdomains per root
def extract_prefixes(root, known_set):
    prefixes = set()
    pat = re.compile(rf"^([a-z][a-z0-9]*?)([a-z]*?)\.{re.escape(root)}$")
    for h in known_set:
        if not h.endswith("." + root):
            continue
        leaf = h.rsplit("." + root, 1)[0]
        if "." in leaf:  # multi-level subdomain — skip for prefix extraction
            continue
        # split into base prefix (alpha-only first chunk) + variable suffix
        m = re.match(r"([a-z]+?)([a-z]{0,4}?)?(oam|web|app|dev|prod|stage|uat|test|auth|sso|portal|p|s|d|v|u)?$", leaf)
        if m and m.group(1) and len(m.group(1)) >= 3:
            prefixes.add(m.group(1))
        # also add the literal leaf as a candidate prefix
        if 3 <= len(leaf) <= 12 and leaf.isalpha():
            prefixes.add(leaf)
    return prefixes


def resolve(host):
    try:
        return host, socket.gethostbyname(host)
    except Exception:
        return host, None


print("[*] Phase 8 — Pattern permutation")
new_hits = []
total_queries = 0

for root in wildcards:
    print(f"    [+] {root}")
    prefixes = extract_prefixes(root, known)
    print(f"        extracted prefixes: {len(prefixes)} -> {sorted(prefixes)[:8]}...")

    candidates = set()

    # prefix × suffix
    for p in prefixes:
        for s in suffixes:
            candidates.add(f"{p}{s}.{root}")

    # generic common names (safety net)
    for c in common:
        candidates.add(f"{c}.{root}")

    # subtract already-known
    candidates -= known
    candidates = sorted(candidates)
    print(f"        permutations to test: {len(candidates)}")
    total_queries += len(candidates)

    # resolve in parallel
    found_for_root = []
    with cf.ThreadPoolExecutor(max_workers=60) as ex:
        for host, ip in ex.map(resolve, candidates):
            if ip:
                found_for_root.append((host, ip))
                new_hits.append((host, ip))

    print(f"        new hits for {root}: {len(found_for_root)}")
    if found_for_root:
        for h, ip in found_for_root[:10]:
            print(f"            {h} -> {ip}")
        if len(found_for_root) > 10:
            print(f"            ...and {len(found_for_root) - 10} more")

# write results
out = ENG / "subdomains" / "permutation_hits.tsv"
with open(out, "w") as f:
    f.write("host\tip\n")
    for h, ip in sorted(set(new_hits)):
        f.write(f"{h}\t{ip}\n")

# merge into all_master
master = ENG / "subdomains" / "all_master.txt"
master_set = {l.strip() for l in master.read_text().splitlines() if l.strip()} if master.exists() else set()
master_set.update(h for h, _ in new_hits)
master.write_text("\n".join(sorted(master_set)) + "\n")

print(f"\n[+] Phase 8 complete.")
print(f"    Total permutation queries: {total_queries}")
print(f"    NEW hosts found: {len(new_hits)}")
print(f"    Output: {out}")
print(f"\n[!] Re-run scripts/07_dns_resolve_probe.py to HTTP-probe the new hosts.")
