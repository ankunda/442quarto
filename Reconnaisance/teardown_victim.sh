#!/usr/bin/env bash
#
# teardown_victim.sh -- reverses setup_victim.sh / Pi_Victim_Setup.qmd, undoing
# the security-sensitive lab configuration once the labs are over.
#
#   sudo ./teardown_victim.sh           Reverts SSH and FTP to a safe state and
#                                       removes the four lab accounts (prompts
#                                       once before deleting them and their home
#                                       directories).
#
#   sudo ./teardown_victim.sh --yes     Same, without the confirmation prompt.
#
#   sudo ./teardown_victim.sh --keep-users
#                                       Reverts SSH and FTP but KEEPS the lab
#                                       accounts (only disables their exposure).
#
# What it does:
#   * removes the lab SSH drop-in (undoing PermitRootLogin yes +
#     PasswordAuthentication yes) and restarts SSH,
#   * stops and disables vsftpd, restoring the original /etc/vsftpd.conf if a
#     backup was saved at setup time,
#   * deletes labuser, alice, bob, carol with their home directories.
#
# What it intentionally leaves alone:
#   * the static IP -- revert that by hand if needed (it was set by hand), e.g.
#     nmcli connection modify "Wired connection 1" ipv4.method auto
#   * the SHA-512 password-hashing settings in /etc/login.defs and
#     /etc/pam.d/common-password -- these are not a security risk and are
#     harmless to leave in place.

set -euo pipefail

USERS=(labuser alice bob carol)
SSH_DROPIN=/etc/ssh/sshd_config.d/00-lab.conf
VSFTPD_CONF=/etc/vsftpd.conf

ASSUME_YES=0
KEEP_USERS=0
for arg in "$@"; do
  case "$arg" in
    -y|--yes)     ASSUME_YES=1 ;;
    --keep-users) KEEP_USERS=1 ;;
    -h|--help)    grep '^#' "$0" | sed 's/^#\s\{0,1\}//'; exit 0 ;;
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

revert_ssh(){
  if [[ -f "$SSH_DROPIN" ]]; then
    rm -f "$SSH_DROPIN"
    ok "removed lab SSH drop-in ($SSH_DROPIN)"
  else
    ok "no lab SSH drop-in present (nothing to remove)"
  fi
  if sshd -t 2>/dev/null; then
    systemctl restart ssh
    ok "SSH restarted"
  else
    warn "sshd config test failed -- SSH not restarted; check /etc/ssh/sshd_config"
  fi
  # Report the effective setting so a lingering manual change is visible.
  local eff
  eff=$(sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}' || true)
  case "$eff" in
    yes) warn "root SSH login is STILL enabled (permitrootlogin yes) -- set it elsewhere in sshd_config; edit /etc/ssh/sshd_config and set 'PermitRootLogin no'" ;;
    "")  ok "could not read effective permitrootlogin (verify manually)" ;;
    *)   ok "root SSH login now '$eff' (not fully open)" ;;
  esac
}

revert_ftp(){
  systemctl stop    vsftpd >/dev/null 2>&1 || true
  systemctl disable vsftpd >/dev/null 2>&1 || true
  ok "vsftpd stopped and disabled"
  if [[ -f "${VSFTPD_CONF}.orig" ]]; then
    mv -f "${VSFTPD_CONF}.orig" "$VSFTPD_CONF"
    ok "restored original $VSFTPD_CONF from backup"
  fi
}

remove_users(){
  local present=()
  local u
  for u in "${USERS[@]}"; do
    id "$u" &>/dev/null && present+=("$u")
  done
  if [[ ${#present[@]} -eq 0 ]]; then
    ok "no lab accounts present (nothing to remove)"
    return 0
  fi
  if [[ $ASSUME_YES -ne 1 ]]; then
    printf '\nAbout to DELETE these accounts and their home directories:\n'
    printf '  - %s\n' "${present[@]}"
    read -r -p 'Type "yes" to proceed: ' reply
    if [[ "$reply" != yes ]]; then
      warn "account removal cancelled -- SSH/FTP were still reverted"
      return 0
    fi
  fi
  for u in "${present[@]}"; do
    deluser --remove-home "$u" >/dev/null 2>&1 && ok "removed user '$u' (and home)" \
      || warn "could not fully remove '$u' -- check manually"
  done
}

say "Teardown"
revert_ssh
revert_ftp
if [[ $KEEP_USERS -eq 1 ]]; then
  ok "keeping lab accounts (--keep-users)"
else
  remove_users
fi

cat <<EOF

Teardown complete. Reminders:
  * If you set a static IP by hand, revert it if the Pi is being repurposed
    (e.g. nmcli connection modify "Wired connection 1" ipv4.method auto).
  * The SHA-512 hashing settings were left in place (harmless).
EOF
