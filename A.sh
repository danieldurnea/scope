#
#!/usr/bin/env bash
# =============================================================================
# Ubuntu 24.10 Hardening Script
# Bazat pe: CIS Benchmark, STIG, NIST SP 800-53
# Rulează ca root. Testează într-un mediu non-producție înainte de deployment.
# =============================================================================

set -euo pipefail

# --- Culori și logging ---
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
fail() { echo -e "${RED}[FAIL]${NC} $*"; exit 1; }
info() { echo -e "      $*"; }

[[ $EUID -ne 0 ]] && fail "Scriptul trebuie rulat ca root (sudo)."

OS_VER=$(lsb_release -rs 2>/dev/null || echo "unknown")
[[ "$OS_VER" != "24.10" ]] && warn "Detectat Ubuntu $OS_VER — scriptul vizează 24.10, continuă cu precauție."

echo "============================================================"
echo "  Ubuntu 24.10 — Hardening Script"
echo "  $(date)"
echo "============================================================"
echo

# =============================================================================
# 1. UPDATE SISTEM
# =============================================================================
echo ">>> [1/12] Actualizare pachete"
apt-get update -q
apt-get upgrade -y -q
apt-get autoremove -y -q
log "Sistem actualizat."

# =============================================================================
# 2. PACHETE DE SECURITATE ESENȚIALE
# =============================================================================
echo ">>> [2/12] Instalare pachete de securitate"
PACKAGES=(
    ufw
    fail2ban
    auditd
    audispd-plugins
    libpam-pwquality
    apparmor
    apparmor-utils
    unattended-upgrades
    apt-listchanges
    rkhunter
    chkrootkit
    aide
    lynis
    acl
    libpam-google-authenticator   # opțional MFA
)
apt-get install -y -q "${PACKAGES[@]}" || warn "Unele pachete nu au putut fi instalate."
log "Pachete instalate."

# =============================================================================
# 3. ACTUALIZĂRI AUTOMATE
# =============================================================================
echo ">>> [3/12] Configurare actualizări automate de securitate"
cat > /etc/apt/apt.conf.d/20auto-upgrades <<'EOF'
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::Download-Upgradeable-Packages "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades <<'EOF'
Unattended-Upgrade::Allowed-Origins {
    "${distro_id}:${distro_codename}-security";
};
Unattended-Upgrade::Remove-Unused-Kernel-Packages "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
Unattended-Upgrade::Automatic-Reboot "false";
Unattended-Upgrade::Mail "root";
EOF
log "Actualizări automate configurate."

# =============================================================================
# 4. HARDENING KERNEL (sysctl)
# =============================================================================
echo ">>> [4/12] Parametri kernel (sysctl)"
SYSCTL_FILE="/etc/sysctl.d/99-hardening.conf"
cat > "$SYSCTL_FILE" <<'EOF'
# --- Protecție rețea ---
net.ipv4.ip_forward = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_rfc1337 = 1

# --- Protecție kernel ---
kernel.randomize_va_space = 2
kernel.dmesg_restrict = 1
kernel.kptr_restrict = 2
kernel.yama.ptrace_scope = 2
kernel.perf_event_paranoid = 3
kernel.unprivileged_bpf_disabled = 1
net.core.bpf_jit_harden = 2

# --- Fișiere core dump ---
fs.suid_dumpable = 0

# --- Protecție symlink/hardlink ---
fs.protected_symlinks = 1
fs.protected_hardlinks = 1
fs.protected_fifos = 2
fs.protected_regular = 2
EOF

sysctl --system -q
log "Parametri sysctl aplicați."

# =============================================================================
# 5. FIREWALL (UFW)
# =============================================================================
echo ">>> [5/12] Configurare UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing
ufw default deny forward
ufw allow ssh comment "SSH"
# Decomentează și adaptează după necesitate:
# ufw allow 80/tcp comment "HTTP"
# ufw allow 443/tcp comment "HTTPS"
ufw logging on
ufw --force enable
log "UFW activat — doar SSH permis (incoming)."

# =============================================================================
# 6. SSH HARDENING
# =============================================================================
echo ">>> [6/12] Hardening SSH"
SSH_CFG="/etc/ssh/sshd_config"
BACKUP="/etc/ssh/sshd_config.bak.$(date +%Y%m%d%H%M%S)"
cp "$SSH_CFG" "$BACKUP"
info "Backup creat: $BACKUP"

# Aplică setări de securitate (append în drop-in file)
SSH_DROP="/etc/ssh/sshd_config.d/99-hardening.conf"
cat > "$SSH_DROP" <<'EOF'
# Hardening SSH — generat de script
Protocol 2
Port 22
PermitRootLogin no
PasswordAuthentication no
PermitEmptyPasswords no
ChallengeResponseAuthentication no
UsePAM yes
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
PermitTunnel no
MaxAuthTries 3
MaxSessions 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
Banner /etc/issue.net
PrintLastLog yes
LogLevel VERBOSE
AuthorizedKeysFile .ssh/authorized_keys
KexAlgorithms curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512
Ciphers chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com
MACs hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com
EOF

echo "Unauthorized access is prohibited." > /etc/issue.net

sshd -t && systemctl restart ssh
log "SSH restartat cu configurație hardened."
warn "Autentificarea cu parolă este DEZACTIVATĂ — asigură-te că ai cheie SSH configurată!"

# =============================================================================
# 7. POLITICI PAROLE (PAM + pwquality)
# =============================================================================
echo ">>> [7/12] Politici parole"
PWQUALITY_CONF="/etc/security/pwquality.conf"
cat > "$PWQUALITY_CONF" <<'EOF'
minlen = 14
minclass = 4
maxrepeat = 3
maxsequence = 4
gecoscheck = 1
dictcheck = 1
usercheck = 1
enforcing = 1
retry = 3
EOF

# Politică expirare parole
sed -i 's/^PASS_MAX_DAYS.*/PASS_MAX_DAYS   90/' /etc/login.defs
sed -i 's/^PASS_MIN_DAYS.*/PASS_MIN_DAYS   1/'  /etc/login.defs
sed -i 's/^PASS_WARN_AGE.*/PASS_WARN_AGE   14/' /etc/login.defs

# Timeout inactivitate shell
echo 'TMOUT=900' >> /etc/profile.d/timeout.sh
echo 'readonly TMOUT' >> /etc/profile.d/timeout.sh
echo 'export TMOUT' >> /etc/profile.d/timeout.sh
chmod 644 /etc/profile.d/timeout.sh

log "Politici parole configurate."

# =============================================================================
# 8. AUDIT (auditd)
# =============================================================================
echo ">>> [8/12] Configurare auditd"
cat > /etc/audit/rules.d/99-hardening.rules <<'EOF'
# Șterge regulile existente
-D
# Dimensiune buffer
-b 8192

# Eșecuri de autentificare
-w /var/log/faillog -p wa -k logins
-w /var/log/lastlog -p wa -k logins
-w /var/run/faillock -p wa -k logins

# Modificări utilizatori/grupuri
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/gshadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Apeluri de sistem privilegiate
-a always,exit -F arch=b64 -S execve -F euid=0 -k root_commands
-a always,exit -F arch=b32 -S execve -F euid=0 -k root_commands

# Modificări rețea
-a always,exit -F arch=b64 -S sethostname -S setdomainname -k network_config
-w /etc/hosts -p wa -k network_config
-w /etc/network/ -p wa -k network_config

# Module kernel
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Fișiere critice sistem
-w /boot/grub/grub.cfg -p wa -k bootloader
-w /etc/crontab -p wa -k cron
-w /etc/cron.d/ -p wa -k cron
-w /etc/ssh/sshd_config -p wa -k sshd

# Imutabil (comentează dacă ai nevoie să modifici regulile la runtime)
# -e 2
EOF

systemctl enable auditd
systemctl restart auditd
log "auditd configurat și pornit."

# =============================================================================
# 9. APPARMOR
# =============================================================================
echo ">>> [9/12] AppArmor"
systemctl enable apparmor
systemctl start apparmor
aa-enforce /etc/apparmor.d/* 2>/dev/null || warn "Unele profile AppArmor nu pot fi puse în enforce (normal dacă nu există)."
log "AppArmor activ (enforce)."

# =============================================================================
# 10. DEZACTIVARE SERVICII ȘI MODULE INUTILE
# =============================================================================
echo ">>> [10/12] Dezactivare servicii și module inutile"

SERVICES_TO_DISABLE=(
    avahi-daemon
    cups
    isc-dhcp-server
    isc-dhcp-server6
    slapd
    nfs-server
    rpcbind
    rsync
    snmpd
    nis
    telnet
    ftp
    rsh-server
)
for svc in "${SERVICES_TO_DISABLE[@]}"; do
    if systemctl is-enabled "$svc" &>/dev/null; then
        systemctl disable --now "$svc" 2>/dev/null || true
        info "Dezactivat: $svc"
    fi
done

# Dezactivare module kernel neutilizate
MODULES_BLACKLIST="/etc/modprobe.d/hardening-blacklist.conf"
cat > "$MODULES_BLACKLIST" <<'EOF'
# Protocoale de rețea neutilizate
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
install n-hdlc /bin/false
install ax25 /bin/false
install netrom /bin/false
install x25 /bin/false
install rose /bin/false
install decnet /bin/false
install econet /bin/false
install af_802154 /bin/false
install ipx /bin/false
install appletalk /bin/false
install psnap /bin/false
install p8022 /bin/false
install p8023 /bin/false
install llc2 /bin/false

# Sisteme de fișiere nefolosite
install cramfs /bin/false
install freevxfs /bin/false
install jffs2 /bin/false
install hfs /bin/false
install hfsplus /bin/false
install squashfs /bin/false
install udf /bin/false

# Altele
install usb-storage /bin/false
install firewire-core /bin/false
EOF
log "Servicii și module inutile dezactivate."

# =============================================================================
# 11. HARDENING FIȘIERE DE SISTEM
# =============================================================================
echo ">>> [11/12] Permisiuni fișiere critice"

chmod 640 /etc/shadow
chmod 644 /etc/passwd
chmod 644 /etc/group
chmod 000 /etc/gshadow
chmod 700 /root
chmod 700 /boot
chmod 600 /etc/ssh/sshd_config

# Restricționare /tmp și /var/tmp ca noexec
if ! grep -q "^tmpfs /tmp" /etc/fstab; then
    echo "tmpfs /tmp tmpfs defaults,nodev,nosuid,noexec 0 0" >> /etc/fstab
    info "Adăugat /tmp ca noexec în fstab (se aplică la reboot)."
fi

# Dezactivare core dumps
echo "* hard core 0" >> /etc/security/limits.conf
echo "* soft core 0" >> /etc/security/limits.conf

# Securizare GRUB (previne editare la boot)
GRUB_PASS_HASH=$(echo -e "hardening\nhardening" | grub-mkpasswd-pbkdf2 2>/dev/null | grep "PBKDF2 hash" | awk '{print $NF}')
if [[ -n "$GRUB_PASS_HASH" ]]; then
    cat > /etc/grub.d/40_custom_hardening <<EOF
set superusers="admin"
password_pbkdf2 admin $GRUB_PASS_HASH
EOF
    chmod 600 /etc/grub.d/40_custom_hardening
    update-grub 2>/dev/null || true
    warn "GRUB protejat cu parolă implicită 'hardening' — SCHIMB-O imediat!"
fi

log "Permisiuni și restricții aplicate."

# =============================================================================
# 12. FAIL2BAN
# =============================================================================
echo ">>> [12/12] Configurare Fail2Ban"
cat > /etc/fail2ban/jail.d/hardening.conf <<'EOF'
[DEFAULT]
bantime  = 3600
findtime = 600
maxretry = 5
backend  = systemd

[sshd]
enabled  = true
port     = ssh
logpath  = %(sshd_log)s
maxretry = 3
bantime  = 86400
EOF

systemctl enable fail2ban
systemctl restart fail2ban
log "Fail2Ban configurat (SSH: 3 încercări → ban 24h)."

# =============================================================================
# 13. LUKS — CRIPTARE DISC PENTRU VPS CLOUD
# =============================================================================
# Pe un VPS nu există acces fizic la consolă la boot, deci unlock-ul automat
# se face prin una din metodele:
#   A) Dropbear-in-initramfs  — SSH în initramfs pentru unlock manual (recomandat)
#   B) Clevis + Tang          — unlock automat prin server Tang din rețeaua internă
#   C) Clevis + TPM2          — unlock automat dacă hypervisorul expune vTPM 2.0
#
# ATENȚIE: Criptarea unui disc deja pornit NU este posibilă fără reinstalare.
# Acest script configurează infrastructura de unlock; criptarea propriu-zisă
# se face la provisionare (installer Ubuntu cu "Encrypt disk" sau `cryptsetup`).
# =============================================================================
echo ">>> [13/13] LUKS — configurare remote unlock pentru VPS"

LUKS_MODE="${LUKS_MODE:-dropbear}"   # dropbear | tang | tpm2 | skip
TANG_SERVER="${TANG_SERVER:-}"       # IP/hostname server Tang (mod tang)
DROPBEAR_PORT="${DROPBEAR_PORT:-2222}"

if [[ "$LUKS_MODE" == "skip" ]]; then
    warn "LUKS_MODE=skip — secțiunea LUKS omisă."
else

# --- Detectare partiție LUKS activă ---
LUKS_DEVS=$(lsblk -o NAME,TYPE -rn | awk '$2=="crypt"{print $1}')
if [[ -z "$LUKS_DEVS" ]]; then
    warn "Nu s-a detectat nicio partiție LUKS activă montată."
    warn "Configurarea unlock se poate face preventiv, dar nu există ce descifra acum."
fi

# -------------------------------------------------------------------------
# METODA A: Dropbear SSH în initramfs (recomandat pentru VPS fără Tang)
# -------------------------------------------------------------------------
if [[ "$LUKS_MODE" == "dropbear" ]]; then
    echo "    Metodă: Dropbear SSH în initramfs (port $DROPBEAR_PORT)"
    apt-get install -y -q dropbear-initramfs

    # Configurare Dropbear
    cat > /etc/dropbear/initramfs/dropbear.conf <<EOF
# Dropbear în initramfs — pentru unlock LUKS remote
DROPBEAR_OPTIONS="-p ${DROPBEAR_PORT} -s -j -k -I 60"
# -s  interzice autentificare cu parolă (doar cheie)
# -j  interzice port forwarding local
# -k  interzice port forwarding remote
# -I  timeout inactivitate 60s
EOF

    # Cheie SSH pentru initramfs (separată de cheia sistemului)
    INITRAMFS_KEYS_FILE="/etc/dropbear/initramfs/authorized_keys"
    if [[ ! -s "$INITRAMFS_KEYS_FILE" ]]; then
        warn "Nicio cheie SSH în $INITRAMFS_KEYS_FILE !"
        warn "Adaugă cheia publică ÎNAINTE de reboot:"
        warn "  echo 'ssh-ed25519 AAAA...' > $INITRAMFS_KEYS_FILE"
        warn "Apoi regenerează initramfs: update-initramfs -u -k all"
    else
        info "Chei găsite în $INITRAMFS_KEYS_FILE — OK"
    fi

    # Script helper de unlock (se execută din SSH-ul Dropbear)
    cat > /usr/local/sbin/luks-unlock-remote <<'UNLOCK_EOF'
#!/bin/bash
# Rulează din sesiunea SSH Dropbear pentru a descifra volumele LUKS
echo "=== LUKS Remote Unlock ==="
for DEV in /dev/mapper/cryptroot /dev/mapper/cryptdata; do
    if [[ -e "$DEV" ]]; then
        echo "Volum deja descifrat: $DEV"
    fi
done
# Trimite parola spre cryptroot-ask (compatibil Plymouth/initramfs)
if [ -p /lib/cryptsetup/passfifo ]; then
    echo -n "Parolă LUKS: "
    read -rs PASS
    echo "$PASS" > /lib/cryptsetup/passfifo
    echo
    echo "Parolă trimisă. Sistemul va continua boot-ul."
else
    # fallback: cryptroot-unlock (Ubuntu 22.04+)
    /lib/cryptsetup/cryptroot-unlock
fi
UNLOCK_EOF
    chmod 700 /usr/local/sbin/luks-unlock-remote

    # Deschide portul Dropbear în UFW (dacă UFW e activ)
    if ufw status | grep -q "Status: active"; then
        ufw allow "${DROPBEAR_PORT}/tcp" comment "LUKS Dropbear initramfs"
        info "UFW: port $DROPBEAR_PORT deschis pentru Dropbear."
    fi

    # Configurare IP static în initramfs (necesar pe VPS — DHCP poate lipsi)
    # Editează manual IP-ul real al VPS-ului tău în /etc/initramfs-tools/initramfs.conf
    INITRAMFS_CONF="/etc/initramfs-tools/initramfs.conf"
    if ! grep -q "^IP=" "$INITRAMFS_CONF"; then
        PUBLIC_IP=$(ip -4 route get 1 2>/dev/null | awk '{print $7; exit}' || echo "")
        GATEWAY=$(ip -4 route show default 2>/dev/null | awk '{print $3; exit}' || echo "")
        IFACE=$(ip -4 route show default 2>/dev/null | awk '{print $5; exit}' || echo "eth0")
        if [[ -n "$PUBLIC_IP" && -n "$GATEWAY" ]]; then
            echo "IP=${PUBLIC_IP}::${GATEWAY}:255.255.255.0::${IFACE}:off" >> "$INITRAMFS_CONF"
            info "IP static initramfs: ${PUBLIC_IP} via ${GATEWAY} pe ${IFACE}"
        else
            warn "Nu s-a putut detecta IP-ul — editează manual IP= în $INITRAMFS_CONF"
            echo "# IP=<ip>::<gateway>:<netmask>::<iface>:off" >> "$INITRAMFS_CONF"
        fi
    fi

    update-initramfs -u -k all
    log "Dropbear initramfs configurat (port $DROPBEAR_PORT)."
    info "La reboot, conectează-te cu: ssh -p $DROPBEAR_PORT root@<VPS-IP>"
    info "Apoi rulează: /usr/local/sbin/luks-unlock-remote"

# -------------------------------------------------------------------------
# METODA B: Clevis + Tang (Network Bound Disk Encryption)
# -------------------------------------------------------------------------
elif [[ "$LUKS_MODE" == "tang" ]]; then
    echo "    Metodă: Clevis + Tang (NBDE)"
    [[ -z "$TANG_SERVER" ]] && fail "TANG_SERVER nu este setat. Export: TANG_SERVER=<ip> și rerunează."

    apt-get install -y -q clevis clevis-luks clevis-initramfs tang

    # Leagă fiecare volum LUKS de serverul Tang
    while IFS= read -r CRYPT_DEV; do
        [[ -z "$CRYPT_DEV" ]] && continue
        # Găsește dispozitivul backing
        BACKING=$(dmsetup deps -o devname "$CRYPT_DEV" 2>/dev/null | grep -oP '\(.*?\)' | tr -d '()' | head -1 || echo "")
        if [[ -n "$BACKING" ]]; then
            BLKDEV="/dev/$BACKING"
            info "Leg $BLKDEV de Tang ($TANG_SERVER)..."
            clevis luks bind -d "$BLKDEV" tang \
                "{\"url\":\"http://${TANG_SERVER}\"}" || \
                warn "Binding eșuat pentru $BLKDEV — verifică că Tang e accesibil."
        fi
    done <<< "$LUKS_DEVS"

    update-initramfs -u -k all
    log "Clevis+Tang configurat."
    warn "Tang trebuie să fie accesibil la boot din rețeaua de management."
    warn "Testează cu: clevis luks unlock -d /dev/<dispozitiv>"

# -------------------------------------------------------------------------
# METODA C: Clevis + TPM2 (dacă hypervisorul expune vTPM 2.0)
# -------------------------------------------------------------------------
elif [[ "$LUKS_MODE" == "tpm2" ]]; then
    echo "    Metodă: Clevis + TPM2"

    if [[ ! -e /dev/tpm0 && ! -e /dev/tpmrm0 ]]; then
        fail "TPM2 nu este disponibil (/dev/tpm0 sau /dev/tpmrm0 lipsesc). Verifică dacă hypervisorul expune vTPM 2.0."
    fi

    apt-get install -y -q clevis clevis-luks clevis-initramfs clevis-tpm2 tpm2-tools

    while IFS= read -r CRYPT_DEV; do
        [[ -z "$CRYPT_DEV" ]] && continue
        BACKING=$(dmsetup deps -o devname "$CRYPT_DEV" 2>/dev/null | grep -oP '\(.*?\)' | tr -d '()' | head -1 || echo "")
        if [[ -n "$BACKING" ]]; then
            BLKDEV="/dev/$BACKING"
            info "Leg $BLKDEV de TPM2 (PCR 0+7)..."
            clevis luks bind -d "$BLKDEV" tpm2 \
                '{"pcr_bank":"sha256","pcr_ids":"0,7"}' || \
                warn "Binding TPM2 eșuat pentru $BLKDEV."
        fi
        
