#!/bin/bash
# Installer for FireCompass Deep Passive OSINT Agent prerequisites
# Tested on Kali Linux 2025+. Adjust package names for other distros.

set -e

echo "[*] FireCompass Deep Passive OSINT Agent — Installer"
echo "[*] Installing prerequisites..."

# Tool list
APT_TOOLS=(curl jq dnsutils whois openssl python3 python3-pip git)
GO_TOOLS=(
  "github.com/projectdiscovery/subfinder/v2/cmd/subfinder@latest"
  "github.com/projectdiscovery/dnsx/cmd/dnsx@latest"
  "github.com/projectdiscovery/httpx/cmd/httpx@latest"
  "github.com/projectdiscovery/katana/cmd/katana@latest"
  "github.com/projectdiscovery/alterx/cmd/alterx@latest"
  "github.com/jaeles-project/gospider@latest"
  "github.com/tomnomnom/assetfinder@latest"
  "github.com/owasp-amass/amass/v4/...@master"
)

# 1. APT packages
echo "[+] Installing apt packages: ${APT_TOOLS[*]}"
sudo apt update -qq
sudo apt install -y "${APT_TOOLS[@]}"

# 2. Go (required for ProjectDiscovery tools)
if ! command -v go &> /dev/null; then
    echo "[+] Installing Go..."
    sudo apt install -y golang-go
fi

# 3. Go-based tools
for tool in "${GO_TOOLS[@]}"; do
    name=$(echo "$tool" | sed 's|.*/||;s|@.*||;s|/v[0-9].*||')
    if ! command -v "$name" &> /dev/null; then
        echo "[+] Installing $name from $tool"
        go install "$tool" 2>&1 | tail -3 || echo "[-] $name install failed — install manually"
    else
        echo "[=] $name already installed"
    fi
done

# Add go bin to PATH if not there
if [[ ":$PATH:" != *":$HOME/go/bin:"* ]]; then
    echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.zshrc
    echo 'export PATH=$PATH:$HOME/go/bin' >> ~/.bashrc
    export PATH=$PATH:$HOME/go/bin
fi

# 4. Python tools
echo "[+] Installing Python tools..."
pip3 install --break-system-packages requests 2>/dev/null || pip3 install requests

# 5. trufflehog (for github leaks)
if ! command -v trufflehog &> /dev/null; then
    echo "[+] Installing trufflehog..."
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh | sudo sh -s -- -b /usr/local/bin || echo "[-] trufflehog install failed"
fi

# 6. theHarvester
if ! command -v theHarvester &> /dev/null; then
    echo "[+] Installing theHarvester..."
    sudo apt install -y theharvester 2>/dev/null || echo "[-] theHarvester not in apt — install manually from github"
fi

# 7. Reference repos (HackTricks, PayloadsAllTheThings, hacktricks-cloud)
HT_DIR=/home/kali/hacktricks
PAT_DIR=/home/kali/PayloadsAllTheThings
HTC_DIR=/home/kali/hacktricks-cloud

[ -d "$HT_DIR" ]  || git clone --depth 1 https://github.com/HackTricks-wiki/hacktricks "$HT_DIR"
[ -d "$PAT_DIR" ] || git clone --depth 1 https://github.com/swisskyrepo/PayloadsAllTheThings "$PAT_DIR"
[ -d "$HTC_DIR" ] || git clone --depth 1 https://github.com/HackTricks-wiki/hacktricks-cloud "$HTC_DIR"

echo ""
echo "[*] Done."
echo "[*] Next: copy the agent into Claude Code:"
echo "      mkdir -p ~/.claude/agents && cp agents/firecompass-passive-recon.md ~/.claude/agents/"
echo ""
echo "[*] Optional API keys (export in shell or .env):"
echo "      SHODAN_API_KEY=...      (for richer port data)"
echo "      GITHUB_TOKEN=...        (raises GitHub search rate limit)"
echo "      HIBP_API_KEY=...        (HaveIBeenPwned domain search)"
echo "      HUNTER_API_KEY=...      (Hunter.io email enumeration)"
