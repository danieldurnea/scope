#!/usr/bin/env bash
# ubuntu-privacy-hardening.sh — Privacy-focused Ubuntu hardening
# Disables telemetry, restricts data collection, hardens network privacy
# Run as root on Ubuntu 22.04/24.04

set -euo pipefail

LOGFILE="/var/log/privacy-hardening.log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "[*] Privacy hardening started: $(date)"

# ── 1. Remove Ubuntu telemetry ────────────────────────────────────────────────

echo "[*] Removing telemetry packages..."
apt-get purge -y \
    ubuntu-report \
    popularity-contest \
    apport \
    whoopsie \
    kerneloops \
    2>/dev/null || true

apt-get autoremove -y -q

# Disable error reporting
systemctl disable --now apport 2>/dev/null || true
systemctl disable --now whoopsie 2>/dev/null || true

# ── 2. Disable Canonical data collection ─────────────────────────────────────

echo "[*] Disabling Canonical telemetry..."

# Disable motd news (phones home)
pro config set apt_news=false 2>/dev/null || true
systemctl disable --now motd-news.timer 2>/dev/null || true
sed -i 's/ENABLED=1/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true

# Disable snapd telemetry
if systemctl is-active snapd &>/dev/null; then
    snap set system metrics.enabled=no 2>/dev/null || true
fi

# ── 3. DNS privacy (DNS over TLS via systemd-resolved) ───────────────────────

echo "[*] Configuring DNS over TLS..."
cat > /etc/systemd/resolved.conf.d/privacy.conf <<'EOF'
[Resolve]
DNS=1.1.1.1#cloudflare-dns.com 9.9.9.9#dns.quad9.net
FallbackDNS=8.8.8.8#dns.google
DNSSEC=yes
DNSOverTLS=yes
MulticastDNS=no
LLMNR=no
EOF

systemctl restart systemd-resolved
echo "[+] DNS over TLS enabled (Cloudflare + Quad9)"

# ── 4. Disable mDNS / LLMNR (local network leakage) ─────────────────────────

echo "[*] Disabling mDNS and LLMNR..."
systemctl disable --now avahi-daemon 2>/dev/null || true

# ── 5. MAC address randomization ─────────────────────────────────────────────

echo "[*] Enabling MAC address randomization..."
cat > /etc/NetworkManager/conf.d/99-mac-randomize.conf <<'EOF'
[device]
wifi.scan-rand-mac-address=yes

[connection]
wifi.cloned-mac-address=random
ethernet.cloned-mac-address=random
EOF

systemctl restart NetworkManager 2>/dev/null || true

# ── 6. Restrict rsyslog from sending logs externally ─────────────────────────

echo "[*] Restricting rsyslog..."
sed -i 's/^\(.*@.*\)/#\1/' /etc/rsyslog.conf
systemctl restart rsyslog

# ── 7. Firewall — block outbound telemetry ────────────────────────────────────

echo "[*] Configuring privacy-focused firewall rules..."
apt-get install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow ssh

# Block known Ubuntu telemetry endpoints
ufw deny out to 91.189.88.0/21 comment "Ubuntu telemetry"
ufw deny out to 185.125.190.0/24 comment "Canonical services"

ufw --force enable

# ── 8. Disable core dumps (prevent sensitive data exposure) ──────────────────

echo "[*] Disabling core dumps..."
cat >> /etc/security/limits.conf <<'EOF'
* hard core 0
* soft core 0
EOF

cat > /etc/sysctl.d/99-privacy.conf <<'EOF'
# Disable core dumps
fs.suid_dumpable = 0

# Disable magic sysrq key
kernel.sysrq = 0

# Restrict ptrace scope
kernel.yama.ptrace_scope = 2

# Disable IPv6 privacy extensions off-by-default fix
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2

# Restrict kernel logs
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
EOF

sysctl -p /etc/sysctl.d/99-privacy.conf

# ── 9. Clear bash history on logout ──────────────────────────────────────────

echo "[*] Configuring shell history privacy..."
cat >> /etc/bash.bashrc <<'EOF'

# Privacy: clear history on logout
export HISTSIZE=0
export HISTFILESIZE=0
EOF

# ── 10. Restrict /proc visibility ────────────────────────────────────────────

echo "[*] Restricting /proc visibility..."
if ! grep -q "hidepid" /etc/fstab; then
    echo "proc /proc proc defaults,hidepid=2,gid=0 0 0" >> /etc/fstab
    mount -o remount,hidepid=2 /proc 2>/dev/null || true
fi

# ── 11. Secure /tmp with noexec ──────────────────────────────────────────────

echo "[*] Securing /tmp..."
if ! grep -q "tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,noexec,nosuid,nodev,size=512M 0 0" >> /etc/fstab
fi

# ── 12. AppArmor ─────────────────────────────────────────────────────────────

echo "[*] Enforcing AppArmor profiles..."
apt-get install -y apparmor apparmor-utils apparmor-profiles apparmor-profiles-extra
aa-enforce /etc/apparmor.d/* 2>/dev/null || true
systemctl enable --now apparmor

# ── Done ──────────────────────────────────────────────────────────────────────

echo ""
echo "══════════════════════════════════════════"
echo " Privacy hardening complete: $(date)"
echo " Log: $LOGFILE"
echo " REBOOT REQUIRED to apply all changes."
echo "══════════════════════════════════════════"
- #### Domains:
  - [inscope_domains.txt](https://github.com/rix4uni/scope/blob/main/data/Domains/inscope_domains.txt)
  - [outofscope_domains.txt](https://github.com/rix4uni/scope/blob/main/data/Domains/outofscope_domains.txt)


#### Platform Based files:
- #### Bugcrowd:
  - [bugcrowd_inscope.txt](https://github.com/rix4uni/scope/blob/main/data/Bugcrowd/bugcrowd_inscope.txt)
  - [bugcrowd_outofscope.txt](https://github.com/rix4uni/scope/blob/main/data/Bugcrowd/bugcrowd_outofscope.txt)

- #### Hackerone:
  - [hackerone_inscope.txt](https://github.com/rix4uni/scope/blob/main/data/Hackerone/hackerone_inscope.txt)
  - [hackerone_outofscope.txt](https://github.com/rix4uni/scope/blob/main/data/Hackerone/hackerone_outofscope.txt)

- #### Intigriti:
  - [intigriti_inscope.txt](https://github.com/rix4uni/scope/blob/main/data/Intigriti/intigriti_inscope.txt)
  - [intigriti_outofscope.txt](https://github.com/rix4uni/scope/blob/main/data/Intigriti/intigriti_outofscope.txt)

- #### Yeswehack:
  - [yeswehack_inscope.txt](https://github.com/rix4uni/scope/blob/main/data/Yeswehack/yeswehack_inscope.txt)
  - [yeswehack_outofscope.txt](https://github.com/rix4uni/scope/blob/main/data/Yeswehack/yeswehack_outofscope.txt)

## 📌 References
- https://github.com/arkadiyt/bounty-targets-data
- https://github.com/Osb0rn3/bugbounty-targets

## regex tested on `regex101.com`
You can improve these regex for more accurate data.
- https://regex101.com/r/1z8v70/1
- https://regex101.com/r/1z8v70/2
- https://regex101.com/r/1z8v70/3
