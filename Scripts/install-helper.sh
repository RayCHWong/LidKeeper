#!/bin/bash
#
# Installs (or removes) LidKeeper's privileged helper.
#
# It puts two files in place:
#   /usr/local/libexec/lidkeeper-helper   root:wheel 0755  — the helper
#   /etc/sudoers.d/lidkeeper              root:wheel 0440  — a rule letting
#       one named user run that helper, with one of three fixed arguments,
#       without a password. Nothing else gains root.
#
# Usage:   sudo bash Scripts/install-helper.sh install [--user NAME]
#          sudo bash Scripts/install-helper.sh uninstall
#
# LidKeeper's menu runs this for you through the usual macOS admin prompt;
# run it by hand if you'd rather see what it does.
set -euo pipefail

HELPER_DIR="/usr/local/libexec"
HELPER="${HELPER_DIR}/lidkeeper-helper"
SUDOERS="/etc/sudoers.d/lidkeeper"

die() { echo "install-helper: $*" >&2; exit 1; }

action="${1:-install}"
shift || true

user=""
source_helper=""
while [ $# -gt 0 ]; do
    case "$1" in
        --user)   user="${2:-}"; shift 2 ;;
        --helper) source_helper="${2:-}"; shift 2 ;;
        *) die "unknown option: $1" ;;
    esac
done

[ "$(id -u)" -eq 0 ] || die "run this with sudo"

case "$action" in

uninstall)
    # Let the Mac sleep again before taking the helper away.
    [ -x "$HELPER" ] && "$HELPER" off >/dev/null 2>&1 || true
    rm -f "$SUDOERS" "$HELPER"
    echo "Removed $HELPER and $SUDOERS"
    ;;

install)
    # Default to whoever invoked sudo; LidKeeper passes --user explicitly.
    [ -n "$user" ] || user="${SUDO_USER:-}"
    [ -n "$user" ] || die "no user to grant the rule to (pass --user NAME)"
    id -u "$user" >/dev/null 2>&1 || die "no such user: $user"
    case "$user" in
        *[!A-Za-z0-9._-]*) die "refusing an unusual user name: $user" ;;
    esac

    [ -n "$source_helper" ] || source_helper="$(cd "$(dirname "$0")" && pwd)/lidkeeper-helper"
    [ -f "$source_helper" ] || die "can't find the helper to install at $source_helper"

    # The helper runs as root, so nothing below root may be able to rewrite
    # it. Bail out rather than install into a directory anyone else can
    # write to.
    mkdir -p "$HELPER_DIR"
    chown root:wheel "$HELPER_DIR"
    chmod 755 "$HELPER_DIR"
    for dir in /usr/local "$HELPER_DIR"; do
        # A symlink here would send the helper somewhere we haven't checked.
        if [ -L "$dir" ]; then die "$dir is a symlink; install the helper by hand instead"; fi
        owner="$(stat -f '%Su' "$dir")"
        mode="$(stat -f '%Lp' "$dir")"
        [ "$owner" = "root" ] || die "$dir belongs to $owner, not root"
        # Group- or other-writable would let someone else swap the helper out.
        [ $(( 8#$mode & 8#022 )) -eq 0 ] || die "$dir is mode $mode — it must be writable only by root"
    done

    install -o root -g wheel -m 755 "$source_helper" "$HELPER"

    # Write the rule to a temporary file, have visudo check it, and only
    # then put it where sudo reads it: a bad sudoers file locks out sudo.
    # The temporary name contains a dot, which sudo's include directory
    # ignores, so a half-written rule is never read.
    tmp="$(mktemp "$(dirname "$SUDOERS")/lidkeeper.pending.XXXXXX")"
    trap 'rm -f "$tmp"' EXIT
    cat > "$tmp" <<RULE
# Installed by LidKeeper (Scripts/install-helper.sh).
# Lets $user turn system sleep off and on through LidKeeper's helper, so a
# closed lid can stay awake on battery. These three commands, with exactly
# these arguments, are all it permits.
$user ALL=(root) NOPASSWD: $HELPER on, $HELPER off, $HELPER status
RULE
    chown root:wheel "$tmp"
    chmod 440 "$tmp"
    visudo -cf "$tmp" >/dev/null || die "the sudoers rule didn't pass visudo; nothing was installed"
    mv "$tmp" "$SUDOERS"
    trap - EXIT

    echo "Installed $HELPER and $SUDOERS for $user"
    ;;

*)
    die "usage: install-helper.sh install|uninstall"
    ;;
esac
