# HackTricks Reference Mapping

Each phase of the recon agent maps to a specific path in the local HackTricks repo (`/home/kali/hacktricks/`). This document is the citation source that the agent uses in the final report.

| Phase | Topic | HackTricks Path |
|-------|-------|-----------------|
| 1 | Acquisitions / Related domains | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Acquisitions) |
| 1 | Reverse WHOIS | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Reverse Whois) |
| 1 | ASN reverse lookup | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ ASN) |
| 1 | Favicon hash search | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Favicon) |
| 2 | SSL Certificate inspection | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ SSL Certificates) |
| 3 | Certificate Transparency logs | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Certificate Transparency) |
| 3 | Subdomain enumeration tools | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Subdomain) |
| 3 | DNS history / passive DNS | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ DNS) |
| 4 | JavaScript file analysis | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ JS files) |
| 5 | Google Dorks | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Google Dorks) |
| 6 | Shodan / Censys | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Shodan) |
| 7 | DNS resolution / probing | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ DNS) |
| 8 | DNS Bruteforce + permutation | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ DNS Bruteforce) |
| 9 | ASN / Netblock enumeration | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ ASN) |
| 10 | Shodan port enumeration | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Shodan) |
| 11 | Public breach databases | `/src/generic-methodologies-and-resources/external-recon-methodology/database-leaks.md` |
| 12 | GitHub leaked secrets | `/src/generic-methodologies-and-resources/external-recon-methodology/github-leaked-secrets.md` |
| 12 | Wide source code search | `/src/generic-methodologies-and-resources/external-recon-methodology/wide-source-code-search.md` |
| 13 | AWS unauth enum (S3 buckets) | (hacktricks-cloud) `/src/pentesting-cloud/aws-security/aws-unauthenticated-enum-access/README.md` |
| 14 | Email harvesting | `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` (§ Emails) |

---

## How to use this mapping

When the agent generates a report section, it must include the path from this table. Example:

```
### Phase 3 — Multi-source Subdomain Enumeration
**Reference:** HackTricks `/src/generic-methodologies-and-resources/external-recon-methodology/README.md` § Subdomain
**Why:** [from the methodology table]
**Findings:** [from the data files]
```

If the path doesn't exist locally, run:
```bash
cd /home/kali/hacktricks && git pull
```

If a needed technique genuinely isn't in HackTricks, it must be cited to an alternative source (e.g. `https://github.com/owasp/...`) — not omitted.
