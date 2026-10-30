#!/usr/bin/env bash
#
# setup_victim.sh -- configures a Raspberry Pi as the victim machine for the
# CSC442 Recon & Password-Cracking labs, following Pi_Victim_Setup.qmd.
#
# It runs in TWO phases so that nothing weak is ever exposed while the Pi is
# still reachable on the school/public network:
#
#   sudo ./setup_victim.sh            SETUP phase. Run now, while the Pi is on
#                                     the school network. Creates the four lab
#                                     accounts with their LOGIN DISABLED (no
#                                     password yet), installs and configures
#                                     SSH and FTP, but sets NO lab passwords,
#                                     leaves FTP stopped, and does NOT enable
#                                     SSH root/password login. Safe to leave
#                                     briefly on the internet.
#
#   sudo ./setup_victim.sh --go-live  GO-LIVE phase. Run LAST, only after the
#                                     Pi has been moved to the isolated LAN.
#                                     Sets the weak lab passwords, turns on SSH
#                                     password + root login, starts FTP, and
#                                     runs the verification checklist. REFUSES
#                                     to run if the Pi still has a public IP
#                                     (override with --go-live --force).
#
# The static IP is intentionally NOT configured here -- set it by hand at the
# last minute (see Pi_Victim_Setup.qmd, "Assign a Static IP Address").
#
# Teardown after the labs: see the end of Pi_Victim_Setup.qmd.

set -euo pipefail

# ---- account definitions (single source of truth) -------------------------
# Format: user:password:sudo(yes|no):login(yes|no)  -- must match Pi_Victim_Setup.qmd
# login=no accounts get a nologin shell: their hash still populates /etc/shadow
# for the offline lab, but they cannot be used to log in over SSH or FTP.
ACCOUNTS=(
  "labuser:sunshine1:yes:yes"
  "alice:dragon:no:no"
  "bob:c0bra:no:no"
  "carol:abc123:no:no"
)

# Path to nologin, for accounts that exist only as hash fodder.
NOLOGIN=/usr/sbin/nologin
[[ -x "$NOLOGIN" ]] || NOLOGIN=/sbin/nologin

# Trophy file students find and download in Lab 2 (must match the student lab).
TROPHY=/home/labuser/notes/credentials.txt

GO_LIVE=0
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --go-live) GO_LIVE=1 ;;
    --force)   FORCE=1 ;;
    -h|--help) grep '^#' "$0" | sed 's/^#\s\{0,1\}//'; exit 0 ;;
    *) echo "unknown argument: $arg (try --help)" >&2; exit 2 ;;
  esac
done

if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root:  sudo $0 $*" >&2
  exit 1
fi

say(){  printf '\n== %s ==\n' "$*"; }
ok(){   printf '  [ok] %s\n' "$*"; }
warn(){ printf '  [!!] %s\n' "$*" >&2; }

# Force a sha512crypt ($6$) hash so the labs' hashcat mode (-m 1800) is correct.
CHPASSWD_CM=()
if chpasswd --help 2>&1 | grep -q -- '--crypt-method'; then
  CHPASSWD_CM=(-c SHA512)
fi

primary_ipv4(){ ip -4 route get 1.1.1.1 2>/dev/null \
  | awk '{for(i=1;i<=NF;i++) if($i=="src"){print $(i+1); exit}}'; }

is_private_ip(){
  local ip="${1:-}"
  [[ "$ip" =~ ^10\. ]] && return 0
  [[ "$ip" =~ ^192\.168\. ]] && return 0
  [[ "$ip" =~ ^172\.(1[6-9]|2[0-9]|3[0-1])\. ]] && return 0
  return 1
}

port_listening(){ [[ -n "$(ss -tlnH "sport = :$1" 2>/dev/null)" ]]; }

# --------------------------------------------------------------------------- #
# SETUP phase helpers
# --------------------------------------------------------------------------- #
force_sha512(){
  # Current Pi OS yields yescrypt ($y$) via login.defs and often MD5 ($1$) via
  # PAM. The labs need sha512crypt ($6$ / hashcat -m 1800), and the algorithm is
  # chosen by TWO independent subsystems -- fix both.
  if [[ -f /etc/login.defs ]]; then
    # chpasswd / useradd path. The [# ]* also rewrites a commented-out line.
    sed -i -E 's/^[# ]*ENCRYPT_METHOD\b.*/ENCRYPT_METHOD SHA512/' /etc/login.defs
    grep -q '^ENCRYPT_METHOD SHA512' /etc/login.defs \
      || echo 'ENCRYPT_METHOD SHA512' >> /etc/login.defs
    ok "login.defs ENCRYPT_METHOD = SHA512 (chpasswd / useradd path)"
  fi
  local pam=/etc/pam.d/common-password
  if [[ -f "$pam" ]]; then
    # interactive passwd / adduser path (PAM). Replace any algorithm token with
    # sha512; if the pam_unix line names none, add it.
    sed -i -E '/^password[[:space:]].*pam_unix\.so/ s/\b(yescrypt|gost_yescrypt|md5|sha256|bigcrypt|blowfish|des)\b/sha512/g' "$pam"
    sed -i -E '/^password[[:space:]].*pam_unix\.so/ { /sha512/! s/pam_unix\.so/pam_unix.so sha512/ }' "$pam"
    ok "PAM common-password = sha512 (interactive passwd / adduser path)"
  fi
}

create_accounts(){
  local spec user pw grp login
  for spec in "${ACCOUNTS[@]}"; do
    IFS=: read -r user pw grp login <<<"$spec"
    if id "$user" &>/dev/null; then
      ok "user '$user' already exists"
      # login=no accounts get a nologin shell (SSH/FTP login blocked). Leave
      # a login=yes account's existing shell untouched.
      if [[ "$login" == no ]]; then
        usermod --shell "$NOLOGIN" "$user"
        ok "'$user' shell set to nologin (hash fodder only)"
      fi
    else
      if [[ "$login" == no ]]; then
        adduser --disabled-login --gecos "" --shell "$NOLOGIN" "$user" >/dev/null
        ok "created '$user' (nologin; password set at go-live)"
      else
        adduser --disabled-login --gecos "" "$user" >/dev/null
        ok "created '$user' (login disabled; password set at go-live)"
      fi
    fi
    if [[ "$grp" == yes ]]; then
      usermod -aG sudo "$user"
      ok "'$user' added to the sudo group"
    fi
  done
}

plant_trophy(){
  # A fictional "sensitive" file in labuser's home for the Lab 2 find/grep
  # exercise. Owned by labuser (readable with the Lab 1 foothold, no root).
  if ! id labuser &>/dev/null; then
    warn "labuser missing -- skipping trophy file"; return 0
  fi
  install -d -o labuser -g labuser -m 755 "$(dirname "$TROPHY")"
  cat >"$TROPHY" <<'EOF'
CONFIDENTIAL -- internal use only. Do not share.

Backup server login (reused from my main account, I know, I know):
  host     : 10.7.7.50
  username : admin
  password : hunter2-backup!

TODO: stop keeping passwords in plaintext files.
EOF
  chown labuser:labuser "$TROPHY"
  chmod 600 "$TROPHY"
  ok "planted trophy file at $TROPHY"
}

install_ssh_locked(){
  apt-get install -y openssh-server >/dev/null
  systemctl enable ssh >/dev/null 2>&1 || true
  systemctl start  ssh >/dev/null 2>&1 || true
  # Locked-down drop-in: defer root login; do NOT touch PasswordAuthentication
  # so we can't lock you out of the session you're setting this up from. The
  # lab accounts have no password yet, so nothing weak is reachable regardless.
  cat >/etc/ssh/sshd_config.d/00-lab.conf <<'EOF'
# CSC442 lab -- SETUP phase (locked down). Overwritten at go-live.
PermitRootLogin prohibit-password
EOF
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl restart ssh
    ok "SSH installed; root login deferred to go-live"
  else
    warn "sshd config test failed -- removing lab drop-in, SSH left as-is"
    rm -f /etc/ssh/sshd_config.d/00-lab.conf
  fi
}

install_ftp_stopped(){
  apt-get install -y vsftpd >/dev/null
  if [[ -f /etc/vsftpd.conf && ! -f /etc/vsftpd.conf.orig ]]; then
    cp /etc/vsftpd.conf /etc/vsftpd.conf.orig
  fi
  cat >/etc/vsftpd.conf <<'EOF'
listen=YES
listen_ipv6=NO
anonymous_enable=NO
local_enable=YES
write_enable=NO
local_umask=022
chroot_local_user=YES
allow_writeable_chroot=YES
EOF
  systemctl disable vsftpd >/dev/null 2>&1 || true
  systemctl stop    vsftpd >/dev/null 2>&1 || true
  ok "vsftpd installed and configured; left STOPPED until go-live"
}

# --------------------------------------------------------------------------- #
# GO-LIVE phase helpers
# --------------------------------------------------------------------------- #
set_lab_passwords(){
  local spec user pw grp login
  for spec in "${ACCOUNTS[@]}"; do
    IFS=: read -r user pw grp login <<<"$spec"
    if ! id "$user" &>/dev/null; then
      warn "user '$user' missing -- run the SETUP phase first"; continue
    fi
    echo "$user:$pw" | chpasswd "${CHPASSWD_CM[@]}"
    ok "password set for '$user'"
  done
}

expose_ssh(){
  cat >/etc/ssh/sshd_config.d/00-lab.conf <<'EOF'
# CSC442 lab -- GO-LIVE. Isolated LAN only. Revert these for teardown.
PasswordAuthentication yes
PermitRootLogin yes
EOF
  if sshd -t; then
    systemctl restart ssh
    ok "SSH: password + root login ENABLED"
  else
    warn "sshd config test failed -- SSH not restarted; check sshd_config.d/00-lab.conf"
  fi
}

expose_ftp(){
  systemctl enable vsftpd >/dev/null 2>&1 || true
  systemctl restart vsftpd
  ok "vsftpd ENABLED and started"
}

verify(){
  say "Verification"
  local spec user pw grp login h sh
  for spec in "${ACCOUNTS[@]}"; do
    IFS=: read -r user pw grp login <<<"$spec"
    h=$(getent shadow "$user" 2>/dev/null | cut -d: -f2 || true)
    case "$h" in
      \$6\$*)      ok  "$user: sha512crypt \$6\$ hash present" ;;
      \$y\$*)      warn "$user: yescrypt \$y\$ hash -- labs assume \$6\$ (hashcat -m 1800); reset with SHA512" ;;
      ''|'!'*|'*') warn "$user: no usable password hash (field = '${h:-empty}')" ;;
      *)           warn "$user: unexpected hash prefix '${h:0:3}'" ;;
    esac
    # login=no accounts must have a nologin shell (no interactive SSH/FTP).
    if [[ "$login" == no ]]; then
      sh=$(getent passwd "$user" 2>/dev/null | cut -d: -f7 || true)
      case "$sh" in
        */nologin|*/false) ok "$user: shell is '$sh' (login blocked)" ;;
        *) warn "$user: shell is '${sh:-unknown}', expected nologin -- account could be logged into" ;;
      esac
    fi
  done
  if groups labuser 2>/dev/null | grep -qw sudo; then
    ok "labuser is in the sudo group"
  else
    warn "labuser is NOT in the sudo group"
  fi
  port_listening 22 && ok "SSH listening on :22" || warn "SSH not listening on :22"
  port_listening 21 && ok "FTP listening on :21" || warn "FTP not listening on :21"

  local RY=/usr/share/wordlists/rockyou.txt
  if [[ -f "$RY" ]]; then
    grep -qxF sunshine1 "$RY" && ok "labuser password is in rockyou" \
      || warn "labuser password NOT in rockyou -- it will not crack"
    grep -qxF cobra "$RY" && ok "'cobra' (bob's base word) is in rockyou" \
      || warn "'cobra' not in rockyou -- best64 cannot derive bob's password"
    if grep -qxF c0bra "$RY"; then
      warn "'c0bra' IS in rockyou -- bob would crack in the plain dictionary round; pick another leet word (e.g. v1per from viper)"
    else
      ok "'c0bra' is absent from rockyou (needs the rule-based attack -- correct)"
    fi
  else
    ok "rockyou not present on this Pi (expected) -- run the rockyou checks on the attacker machine"
  fi
}

# --------------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------------- #
if [[ $GO_LIVE -eq 1 ]]; then
  ip=$(primary_ipv4 || true)
  say "GO-LIVE phase (primary IP: ${ip:-unknown})"
  if [[ -n "${ip:-}" ]] && ! is_private_ip "$ip" && [[ $FORCE -ne 1 ]]; then
    warn "This Pi has a PUBLIC IP ($ip)."
    warn "Going live here would expose weak root SSH + FTP to the internet."
    warn "Move the Pi to the isolated LAN first, then re-run."
    warn "To override deliberately: sudo $0 --go-live --force"
    exit 1
  fi
  set_lab_passwords
  expose_ssh
  expose_ftp
  verify
  cat <<EOF

Go-live complete. Reminders:
  * Set the static IP by hand now if you have not (see Pi_Victim_Setup.qmd).
  * This machine now has weak passwords + root SSH + open FTP. Keep it ONLY on
    the isolated, no-internet LAN.
  * After the labs, run the teardown steps at the end of Pi_Victim_Setup.qmd.
EOF
else
  say "SETUP phase (safe to run while on the school network)"
  apt-get update -y >/dev/null 2>&1 || warn "apt update failed (continuing)"
  force_sha512
  create_accounts
  plant_trophy
  install_ssh_locked
  install_ftp_stopped
  cat <<EOF

Setup phase complete. Nothing weak is exposed yet:
  * The four lab accounts exist but have NO password (login disabled).
  * SSH root login is deferred; FTP is installed but stopped.

At the last minute, on the ISOLATED (no-internet) LAN:
  1. Set the static IP by hand (see Pi_Victim_Setup.qmd).
  2. Run:  sudo $0 --go-live
EOF
fi
