#!/usr/bin/env python3
"""
Phase 7 — DNS resolution + HTTP probing
Reference: HackTricks /src/generic-methodologies-and-resources/external-recon-methodology/README.md (§ DNS)

Why: Subdomain enumeration produces candidates. Resolving them confirms which
exist; HTTP-probing confirms which are live web services. We use Python
concurrent.futures + curl rather than httpx-toolkit because httpx hangs on
some -follow-redirects cases (proven failure mode in a prior engagement).
"""
import os
import sys
import socket
import subprocess
import concurrent.futures as cf
from pathlib import Path

ENG = os.environ.get("ENGAGEMENT_DIR")
if not ENG:
    sys.exit("export ENGAGEMENT_DIR")

ENG = Path(ENG)
SUBS = ENG / "subdomains" / "all_master.txt"
RESOLVED_DIR = ENG / "resolved"
LIVE_DIR = ENG / "live"
RESOLVED_DIR.mkdir(exist_ok=True)
LIVE_DIR.mkdir(exist_ok=True)

if not SUBS.exists():
    sys.exit(f"missing {SUBS}")

candidates = sorted({l.strip().lower() for l in SUBS.read_text().splitlines() if l.strip()})
print(f"[*] Phase 7 — Resolving {len(candidates)} candidates")


def resolve(host):
    try:
        ip = socket.gethostbyname(host)
        return host, ip
    except Exception:
        return host, None


resolved = []
unresolved = []
with cf.ThreadPoolExecutor(max_workers=80) as ex:
    for host, ip in ex.map(resolve, candidates):
        if ip:
            resolved.append((host, ip))
        else:
            unresolved.append(host)

(RESOLVED_DIR / "resolved_hosts.txt").write_text("\n".join(h for h, _ in resolved) + "\n")
(RESOLVED_DIR / "resolved_ips.txt").write_text("\n".join(sorted({ip for _, ip in resolved})) + "\n")
(RESOLVED_DIR / "unresolved.txt").write_text("\n".join(unresolved) + "\n")
(RESOLVED_DIR / "host_ip_map.tsv").write_text("\n".join(f"{h}\t{ip}" for h, ip in resolved) + "\n")

print(f"    resolved: {len(resolved)}    unresolved: {len(unresolved)}")
print(f"[*] HTTP probing live hosts...")


def probe(host):
    """Try HTTPS first, fall back to HTTP. Capture status, title, redirect, size."""
    for scheme in ("https", "http"):
        try:
            r = subprocess.run(
                [
                    "curl", "-skL", "--max-time", "15",
                    "-o", "/dev/null",
                    "-w", "%{http_code}\t%{size_download}\t%{redirect_url}",
                    f"{scheme}://{host}/",
                ],
                capture_output=True, text=True, timeout=20,
            )
            parts = r.stdout.strip().split("\t")
            status = parts[0] if parts else "000"
            size = parts[1] if len(parts) > 1 else "0"
            redirect = parts[2] if len(parts) > 2 else ""
            if status == "000":
                continue

            # fetch title (max 100KB)
            title = ""
            try:
                body = subprocess.run(
                    ["curl", "-skL", "--max-time", "10", "-r", "0-100000", f"{scheme}://{host}/"],
                    capture_output=True, text=True, timeout=15,
                ).stdout
                import re
                m = re.search(r"<title[^>]*>(.*?)</title>", body, re.IGNORECASE | re.DOTALL)
                if m:
                    title = m.group(1).strip()[:200].replace("\n", " ").replace("\t", " ")
            except Exception:
                pass

            return host, scheme, status, title, redirect, size
        except Exception:
            continue
    return host, "-", "000", "", "", ""


live_results = []
with cf.ThreadPoolExecutor(max_workers=40) as ex:
    futures = {ex.submit(probe, h): h for h, _ in resolved}
    for f in cf.as_completed(futures):
        live_results.append(f.result())

with open(LIVE_DIR / "probed.tsv", "w") as f:
    f.write("host\tscheme\tstatus\ttitle\tredirect\tsize\n")
    for row in sorted(live_results):
        f.write("\t".join(str(x) for x in row) + "\n")

# Status distribution
from collections import Counter
dist = Counter(r[2] for r in live_results)
print(f"[+] Phase 7 complete. Status distribution:")
for code, n in sorted(dist.items(), key=lambda x: -x[1]):
    print(f"    {code}: {n}")

print(f"\n    output: {LIVE_DIR / 'probed.tsv'}")
