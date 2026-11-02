#!/bin/bash
# SPDX-FileCopyrightText: 2026 Bedz01
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Arch: rebuild dndscroll.so whenever pacman installs or upgrades kwin.
#
#   sudo contrib/pacman-hook.sh install   copy this script (root-owned) + write the hook
#   sudo contrib/pacman-hook.sh remove    remove both again (the plugin itself stays)
#        contrib/pacman-hook.sh run       what the hook does; as a normal user it builds
#                                         and checks but does not install
#
# The hook runs a root-owned copy, which builds as the repo's owner and installs only
# the resulting .so as root: CMake runs the repo's files, and root MUST NOT execute those.
set -uo pipefail

LIBDIR=/usr/local/lib/kwin-dnd-scroll
HOOK=/etc/pacman.d/hooks/kwin-dnd-scroll.hook
DEST=/usr/lib/qt6/plugins/kwin/plugins/dndscroll.so
REPO=""   # filled in by `install`

die()  { echo "kwin-dnd-scroll: $*" >&2; exit 1; }
# A failed rebuild MUST NOT fail the pacman transaction; the old plugin just stops loading.
warn() { echo "kwin-dnd-scroll: $* - the plugin will not load until it is rebuilt" >&2; exit 0; }

install_hook() {
    [[ $EUID -eq 0 ]] || die "install needs root (sudo)"
    local repo
    repo=$(dirname "$(dirname "$(readlink -f "$0")")")
    [[ -f $repo/CMakeLists.txt && -f $repo/src/dndscroll.cpp ]] || die "$repo is not the kwin-dnd-scroll repo"

    install -d -m755 "$LIBDIR"
    sed "s|^REPO=\"\"|REPO=\"$repo\"|" "$0" > "$LIBDIR/pacman-hook.sh"
    chmod 755 "$LIBDIR/pacman-hook.sh"
    install -d -m755 "$(dirname "$HOOK")"
    cat > "$HOOK" <<EOF
# Written by kwin-dnd-scroll contrib/pacman-hook.sh install. Source: $repo
[Trigger]
Type = Package
Operation = Install
Operation = Upgrade
Target = kwin

[Action]
Description = Rebuilding kwin-dnd-scroll for the new KWin...
When = PostTransaction
Exec = $LIBDIR/pacman-hook.sh run
EOF
    echo "kwin-dnd-scroll: hook installed ($HOOK), builds from $repo as $(stat -c %U "$repo")"
}

remove_hook() {
    [[ $EUID -eq 0 ]] || die "remove needs root (sudo)"
    rm -f "$HOOK" "$LIBDIR/pacman-hook.sh"
    rmdir "$LIBDIR" 2>/dev/null
    echo "kwin-dnd-scroll: hook removed ($DEST left in place)"
}

run() {
    local repo=${REPO:-$(dirname "$(dirname "$(readlink -f "$0")")")}
    [[ -f $repo/CMakeLists.txt ]] || warn "source repo $repo is missing"
    local owner build want so
    owner=$(stat -c %U "$repo")
    build=$repo/build-pacman
    want=$(grep -oP 'KWIN_PLUGIN_VERSION_STRING "\K[^"]+' /usr/include/kwin/config-kwin.h) ||
        warn "no KWin headers in /usr/include/kwin"

    # The log is the caller's own temp file, never a path inside the owner's repo.
    local as=() log
    [[ $EUID -eq 0 ]] && as=(runuser -u "$owner" --)
    log=$(mktemp /tmp/kwin-dnd-scroll-build.XXXXXX.log)
    "${as[@]}" cmake -S "$repo" -B "$build" -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr >"$log" 2>&1 ||
        warn "cmake configure failed, see $log"
    "${as[@]}" cmake --build "$build" >>"$log" 2>&1 ||
        warn "build failed, see $log"
    rm -f "$log"

    so=$build/bin/kwin/plugins/dndscroll.so
    [[ -f $so && ! -L $so ]] || warn "$so is missing or a symlink"
    grep -qa "PluginFactoryInterface$want" "$so" || warn "$so was not built for KWin $want"
    if [[ $EUID -ne 0 ]]; then
        echo "kwin-dnd-scroll: built $so for KWin $want (not installed: not root)"
        return
    fi
    install -m644 "$so" "$DEST" || warn "could not install $DEST"
    echo "kwin-dnd-scroll: rebuilt for KWin $want; it loads at the next KWin start"
}

case ${1:-} in
    install) install_hook ;;
    remove)  remove_hook ;;
    run)     run ;;
    *)       sed -n '5,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
