# PayloadsAllTheThings Reference Mapping

Local PAT path: `/home/kali/PayloadsAllTheThings/`

| Phase | Topic | PAT Path |
|-------|-------|----------|
| 1 | Network discovery / DNS | `/Methodology and Resources/Network Discovery.md` |
| 1 | OSINT / Reconnaissance overview | `/Methodology and Resources/Methodology and enumeration.md` |
| 3 | Subdomain enumeration | `/Methodology and Resources/Network Discovery.md` (§ DNS / Subdomain) |
| 4 | Web attack surface | `/Methodology and Resources/Web Attack Surface.md` |
| 9 | ASN enumeration | `/Methodology and Resources/Network Discovery.md` (§ ASN) |
| 12 | Source code management leaks | `/Methodology and Resources/Source Code Management.md` |
| 13 | AWS reconnaissance | `/Methodology and Resources/Cloud - AWS Pentest.md` |
| 13 | Azure reconnaissance | `/Methodology and Resources/Cloud - Azure Pentest.md` |

---

## hacktricks-cloud paths (separate repo)

Local path: `/home/kali/hacktricks-cloud/`

| Topic | Path |
|-------|------|
| AWS unauthenticated enumeration | `/src/pentesting-cloud/aws-security/aws-unauthenticated-enum-access/README.md` |
| AWS S3 enumeration | `/src/pentesting-cloud/aws-security/aws-services/aws-s3-enum.md` |
| Azure unauthenticated | `/src/pentesting-cloud/azure-security/az-unauthenticated-enum/README.md` |
| GCP unauthenticated | `/src/pentesting-cloud/gcp-security/gcp-unauthenticated-enum/README.md` |
| GitHub Actions exploitation | `/src/pentesting-ci-cd/github-security/abusing-github-actions/README.md` |

If any path doesn't exist on disk, run:
```bash
cd /home/kali/PayloadsAllTheThings && git pull
cd /home/kali/hacktricks-cloud && git pull
```
