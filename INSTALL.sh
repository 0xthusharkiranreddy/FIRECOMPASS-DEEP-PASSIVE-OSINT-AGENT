#!/usr/bin/env bash
# FireCompass Deep Passive OSINT Agent — Cross-Distro Installer
#
# Supported: Kali, Ubuntu, Debian, Parrot, Pop!_OS, Mint,
#            Fedora, CentOS/RHEL/Rocky/AlmaLinux, Arch/Manjaro/BlackArch
#
# Usage: bash INSTALL.sh

# ── DO NOT use set -e: we handle failures per-step and continue ───────────────
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REAL_HOME="${HOME:-$(eval echo ~"$(whoami)")}"

# ── Colours ───────────────────────────────────────────────────────────────────
if [[ -t 1 ]]; then
    R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' N='\033[0m'
else
    R='' G='' Y='' B='' N=''
fi
info()  { echo -e "${B}[*]${N} $*"; }
ok()    { echo -e "${G}[+]${N} $*"; }
warn()  { echo -e "${Y}[-]${N} $*"; }
fail()  { echo -e "${R}[!]${N} $*"; }
step()  { echo -e "\n${B}──────────────────────────────────────${N}\n${B}  $*${N}\n${B}──────────────────────────────────────${N}"; }

ERRORS=()   # collect non-fatal failures for the end summary

# ── OS / package-manager detection ───────────────────────────────────────────
detect_os() {
    OS_ID="unknown"; OS_ID_LIKE=""; OS_PRETTY="Unknown Linux"; PKG_MGR="unknown"

    if [[ -f /etc/os-release ]]; then
        # shellcheck source=/dev/null
        source /etc/os-release
        OS_ID="${ID,,}"
        OS_ID_LIKE="${ID_LIKE:-}"; OS_ID_LIKE="${OS_ID_LIKE,,}"
        OS_PRETTY="${PRETTY_NAME:-$OS_ID}"
    elif [[ -f /etc/redhat-release ]]; then
        OS_ID="rhel"; OS_ID_LIKE="rhel"
    elif [[ -f /etc/arch-release ]]; then
        OS_ID="arch"; OS_ID_LIKE="arch"
    fi

    # Resolve to a package manager family
    if   echo "$OS_ID $OS_ID_LIKE" | grep -qE 'kali|ubuntu|debian|parrot|mint|pop|linuxmint|raspbian'; then
        PKG_MGR="apt"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -qE 'fedora|rhel|centos|rocky|alma|oracle|amzn'; then
        command -v dnf &>/dev/null && PKG_MGR="dnf" || PKG_MGR="yum"
    elif echo "$OS_ID $OS_ID_LIKE" | grep -qE 'arch|manjaro|blackarch|garuda|endeavouros'; then
        PKG_MGR="pacman"
    elif echo "$OS_ID" | grep -qE 'opensuse|sles'; then
        PKG_MGR="zypper"
    else
        warn "Unrecognised distro ($OS_PRETTY) — will skip native packages; Go tools will still install"
    fi

    info "Detected: ${OS_PRETTY}  |  Package manager: ${PKG_MGR}"
}

# ── Per-distro base package names ────────────────────────────────────────────
# Returns a space-separated list appropriate for the detected PKG_MGR
base_packages() {
    case "$PKG_MGR" in
        apt)
            # libimage-exiftool-perl  → Phase 16 document metadata
            # build-essential         → needed to compile some Go deps
            echo "curl jq dnsutils whois openssl python3 python3-pip git \
                  libimage-exiftool-perl build-essential ca-certificates"
            ;;
        dnf|yum)
            # bind-utils replaces dnsutils; perl-Image-ExifTool replaces libimage-exiftool-perl
            echo "curl jq bind-utils whois openssl python3 python3-pip git \
                  perl-Image-ExifTool gcc make ca-certificates"
            ;;
        pacman)
            echo "curl jq bind whois openssl python python-pip git \
                  perl-image-exiftool base-devel ca-certificates"
            ;;
        zypper)
            echo "curl jq bind-utils whois openssl python3 python3-pip git \
                  exiftool gcc make ca-certificates"
            ;;
        *)
            # Minimalist fallback
            echo "curl jq whois openssl python3 git"
            ;;
    esac
}

# ── Package install wrapper ───────────────────────────────────────────────────
apt_update() {
    info "Refreshing apt package lists…"
    # -q suppresses progress; errors from broken third-party repos (e.g. a Docker
    # Ubuntu repo left on a Kali box) are printed but do NOT abort the script
    # because we use '|| true'.  Individual bad repos produce warnings, not exits.
    sudo apt-get update -qq 2>&1 \
        | grep -vE '^(Hit|Get|Ign):' \
        | grep -v 'Skipping acquire' \
        || true
}

pkg_install() {
    local -a pkgs=("$@")
    [[ ${#pkgs[@]} -eq 0 ]] && return
    info "Installing: ${pkgs[*]}"

    case "$PKG_MGR" in
        apt)
            apt_update
            # Try all at once; if that fails, fall back to one-by-one so a single
            # unavailable package doesn't block everything else
            sudo apt-get install -y --no-install-recommends "${pkgs[@]}" 2>/dev/null \
            || {
                warn "Bulk install failed — retrying package by package"
                for p in "${pkgs[@]}"; do
                    sudo apt-get install -y --no-install-recommends "$p" 2>/dev/null \
                        && ok "  installed: $p" \
                        || warn "  skipped (not found): $p"
                done
            }
            ;;
        dnf)    sudo dnf install -y "${pkgs[@]}" 2>/dev/null || warn "dnf: some packages skipped" ;;
        yum)    sudo yum install -y "${pkgs[@]}" 2>/dev/null || warn "yum: some packages skipped" ;;
        pacman) sudo pacman -Sy --noconfirm "${pkgs[@]}" 2>/dev/null || warn "pacman: some packages skipped" ;;
        zypper) sudo zypper install -y "${pkgs[@]}" 2>/dev/null || warn "zypper: some packages skipped" ;;
        *)      warn "No package manager — install manually: ${pkgs[*]}" ;;
    esac
}

# ── Go installation ───────────────────────────────────────────────────────────
# We install Go from the official binary (dl.google.com) instead of the distro
# package, because distro Go is often 1.18–1.19 while tools like amass v4 and
# ProjectDiscovery require ≥ 1.21.
GO_MIN_MINOR=21   # minimum Go 1.21
GO_INSTALL_VER="1.22.4"

go_version_ok() {
    command -v go &>/dev/null || return 1
    local ver
    ver=$(go version 2>/dev/null | grep -oE 'go[0-9]+\.[0-9]+' | head -1 | tr -d 'go')
    local major minor
    major=$(echo "$ver" | cut -d. -f1)
    minor=$(echo "$ver" | cut -d. -f2)
    [[ "${major:-0}" -ge 1 && "${minor:-0}" -ge $GO_MIN_MINOR ]]
}

install_go() {
    if go_version_ok; then
        ok "Go $(go version | grep -oE 'go[0-9.]+' | head -1) already installed (≥1.${GO_MIN_MINOR})"
        return 0
    fi

    info "Installing Go ${GO_INSTALL_VER} from official binary…"

    local arch
    case "$(uname -m)" in
        x86_64)         arch="amd64" ;;
        aarch64|arm64)  arch="arm64" ;;
        armv6l|armv7l)  arch="armv6l" ;;
        i686|i386)      arch="386" ;;
        *)              arch="amd64"; warn "Unknown arch $(uname -m) — assuming amd64" ;;
    esac

    local tarball="go${GO_INSTALL_VER}.linux-${arch}.tar.gz"
    local url="https://go.dev/dl/${tarball}"
    local tmpdir; tmpdir=$(mktemp -d)

    info "Downloading ${url}…"
    if ! curl -fsSL --progress-bar "$url" -o "${tmpdir}/${tarball}"; then
        fail "Go download failed — check internet connection"
        ERRORS+=("Go ${GO_INSTALL_VER} download failed")
        rm -rf "$tmpdir"
        return 1
    fi

    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf "${tmpdir}/${tarball}"
    rm -rf "$tmpdir"
    ok "Go ${GO_INSTALL_VER} installed to /usr/local/go"
}

# ── PATH configuration ────────────────────────────────────────────────────────
setup_path() {
    # Export for the rest of this script
    export PATH="$PATH:/usr/local/go/bin:$REAL_HOME/go/bin"

    local go_line='export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin'

    for rc in "$REAL_HOME/.bashrc" "$REAL_HOME/.zshrc" "$REAL_HOME/.profile"; do
        [[ -f "$rc" ]] || continue
        grep -q 'go/bin' "$rc" 2>/dev/null && continue
        echo "" >> "$rc"
        echo "# Go tools (added by FireCompass OSINT Agent installer)" >> "$rc"
        echo "$go_line" >> "$rc"
        ok "Updated $rc with Go PATH"
    done

    # fish
    if command -v fish &>/dev/null; then
        local fish_dir="$REAL_HOME/.config/fish/conf.d"
        mkdir -p "$fish_dir"
        if [[ ! -f "$fish_dir/go.fish" ]]; then
            echo 'fish_add_path /usr/local/go/bin $HOME/go/bin' > "$fish_dir/go.fish"
            ok "Updated fish PATH config"
        fi
    fi
}

# ── Go-based OSINT tools ──────────────────────────────────────────────────────
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

install_go_tools() {
    if ! command -v go &>/dev/null; then
        warn "Go not found — skipping Go tools"
        ERRORS+=("Go tools skipped: go not in PATH")
        return
    fi

    for tool in "${GO_TOOLS[@]}"; do
        # Extract binary name: last path component before @version
        local name
        name=$(echo "$tool" | awk -F'/' '{print $NF}' | sed 's|@.*||; s|/\.\.\.$||')

        if command -v "$name" &>/dev/null; then
            ok "$name already installed"
        else
            info "Installing $name…"
            if go install "$tool" 2>&1 | tail -3; then
                ok "$name installed"
            else
                warn "$name failed — install manually:  go install $tool"
                ERRORS+=("go install $name failed")
            fi
        fi
    done
}

# ── theHarvester ──────────────────────────────────────────────────────────────
install_theharvester() {
    if command -v theHarvester &>/dev/null; then
        ok "theHarvester already installed"; return
    fi
    info "Installing theHarvester…"
    # Try apt first (Kali/Parrot carry it); fall back to pip
    if [[ "$PKG_MGR" == "apt" ]]; then
        sudo apt-get install -y theharvester 2>/dev/null && ok "theHarvester installed via apt" && return
    fi
    pip3 install --break-system-packages theHarvester 2>/dev/null \
    || pip3 install theHarvester 2>/dev/null \
    || {
        warn "theHarvester unavailable — install from: github.com/laramies/theHarvester"
        ERRORS+=("theHarvester install failed")
    }
}

# ── trufflehog ────────────────────────────────────────────────────────────────
install_trufflehog() {
    if command -v trufflehog &>/dev/null; then
        ok "trufflehog already installed"; return
    fi
    info "Installing trufflehog…"
    curl -sSfL https://raw.githubusercontent.com/trufflesecurity/trufflehog/main/scripts/install.sh \
        | sudo sh -s -- -b /usr/local/bin 2>/dev/null \
    && ok "trufflehog installed" \
    || {
        warn "trufflehog install failed — install from: github.com/trufflesecurity/trufflehog"
        ERRORS+=("trufflehog install failed")
    }
}

# ── Python tools ──────────────────────────────────────────────────────────────
install_python_tools() {
    info "Installing Python tools (requests)…"
    pip3 install --break-system-packages requests 2>/dev/null \
    || pip3 install requests 2>/dev/null \
    || warn "pip3 install requests failed (may already be present)"
}

# ── Reference repos ───────────────────────────────────────────────────────────
install_knowledge_repos() {
    declare -A REPOS=(
        ["${REAL_HOME}/hacktricks"]="https://github.com/HackTricks-wiki/hacktricks"
        ["${REAL_HOME}/PayloadsAllTheThings"]="https://github.com/swisskyrepo/PayloadsAllTheThings"
        ["${REAL_HOME}/hacktricks-cloud"]="https://github.com/HackTricks-wiki/hacktricks-cloud"
    )

    for dir in "${!REPOS[@]}"; do
        local url="${REPOS[$dir]}"
        local name; name=$(basename "$dir")
        if [[ -d "$dir/.git" ]]; then
            ok "$name already cloned — skipping"
        else
            info "Cloning $name (shallow)…"
            git clone --depth 1 "$url" "$dir" 2>/dev/null \
                && ok "$name cloned to $dir" \
                || {
                    warn "$name clone failed — check network / disk space"
                    ERRORS+=("git clone $name failed")
                }
        fi
    done
}

# ── Install agent file ────────────────────────────────────────────────────────
install_agent() {
    local agent_src="$SCRIPT_DIR/agents/firecompass-passive-recon.md"
    local agent_dst="$REAL_HOME/.claude/agents/firecompass-passive-recon.md"
    mkdir -p "$REAL_HOME/.claude/agents"
    if [[ -f "$agent_src" ]]; then
        cp "$agent_src" "$agent_dst"
        ok "Agent installed → $agent_dst"
    else
        warn "Agent file not found at $agent_src"
        warn "After cloning the repo, run:  cp agents/firecompass-passive-recon.md ~/.claude/agents/"
    fi
}

# ── Summary banner ────────────────────────────────────────────────────────────
print_summary() {
    echo ""
    echo "  ╔═══════════════════════════════════════════╗"
    echo "  ║           Installation Summary            ║"
    echo "  ╚═══════════════════════════════════════════╝"
    if [[ ${#ERRORS[@]} -eq 0 ]]; then
        ok "All components installed successfully"
    else
        warn "${#ERRORS[@]} non-fatal issue(s) — review below:"
        for e in "${ERRORS[@]}"; do warn "  • $e"; done
        echo ""
        warn "The agent will still work; fix the above when convenient."
    fi
    echo ""
    info "Reload your shell or run:  source ~/.bashrc  (or ~/.zshrc)"
    echo ""
    info "Optional API keys (export in shell or add to .env):"
    printf "    %-28s %s\n" "SHODAN_API_KEY=..."        "# richer port / banner data"
    printf "    %-28s %s\n" "GITHUB_TOKEN=..."          "# GitHub search — raises rate limit"
    printf "    %-28s %s\n" "HIBP_API_KEY=..."          "# HaveIBeenPwned domain breach check"
    printf "    %-28s %s\n" "HUNTER_API_KEY=..."        "# Hunter.io email enumeration"
    echo ""
}

# ── Main ──────────────────────────────────────────────────────────────────────
main() {
    echo ""
    echo "  ╔══════════════════════════════════════════════════════╗"
    echo "  ║   FireCompass Deep Passive OSINT Agent — Installer  ║"
    echo "  ╚══════════════════════════════════════════════════════╝"
    echo ""

    # Ensure sudo is available before doing anything destructive
    if ! sudo -v 2>/dev/null; then
        fail "sudo access required — cannot continue"
        exit 1
    fi

    step "Step 1 — Detecting OS"
    detect_os

    step "Step 2 — Installing system packages"
    read -ra PKGS <<< "$(base_packages)"
    pkg_install "${PKGS[@]}"

    step "Step 3 — Installing Go ≥ 1.${GO_MIN_MINOR}"
    install_go
    setup_path

    step "Step 4 — Installing Go-based OSINT tools"
    install_go_tools

    step "Step 5 — Installing theHarvester"
    install_theharvester

    step "Step 6 — Installing trufflehog"
    install_trufflehog

    step "Step 7 — Installing Python tools"
    install_python_tools

    step "Step 8 — Cloning knowledge repos (HackTricks, PAT, hacktricks-cloud)"
    install_knowledge_repos

    step "Step 9 — Installing Claude Code agent"
    install_agent

    print_summary
}

main "$@"
