#!/bin/bash
# SPDX-FileCopyrightText: 2026 Bedz01
# SPDX-License-Identifier: GPL-2.0-or-later
# Quick build without CMake/ECM: dndscroll.so against the KWin installed here.
#   ./build.sh [outdir]      default outdir: ./build
#   KWIN_INC=<dir> ./build.sh [outdir]
#       build against another machine's /usr/include/kwin instead (copied out),
#       e.g. a container without vulkan headers. Its Qt MUST match this one's.
# The result only loads into that exact KWin release (the plugin IID carries
# KWIN_PLUGIN_VERSION_STRING), so build for where it will run.
set -euo pipefail
HERE=$(dirname "$(readlink -f "$0")")
OUT=$(readlink -f "${1:-$HERE/build}")
mkdir -p "$OUT/kwin/plugins"

KWIN_INC=${KWIN_INC:-/usr/include/kwin}
# Against foreign headers, leave KWin's symbols for kwin_wayland to resolve at load.
LIBKWIN=-lkwin
[[ $KWIN_INC != /usr/include/kwin ]] && LIBKWIN=""

MOC=${MOC:-$( (qtpaths6 --query QT_HOST_LIBEXECS || /usr/lib/qt6/bin/qtpaths6 --query QT_HOST_LIBEXECS) 2>/dev/null)/moc}
KF=/usr/include/KF6
INC=(-I"$KWIN_INC" -I"$OUT"
     -I$KF/KConfig -I$KF/KConfigCore -I$KF/KConfigGui -I$KF/KCoreAddons -I$KF/KWindowSystem
     $(pkg-config --cflags Qt6Core Qt6Gui Qt6Widgets Qt6DBus Qt6Qml wayland-server libdrm epoxy))

"$MOC" "${INC[@]}" "$HERE/src/dndscroll.cpp" -o "$OUT/dndscroll.moc"
cp "$HERE/src/metadata.json" "$OUT/"
g++ -std=c++23 -O2 -fPIC -shared -fvisibility=hidden \
    "${INC[@]}" "$HERE/src/dndscroll.cpp" \
    -o "$OUT/kwin/plugins/dndscroll.so" \
    $LIBKWIN $(pkg-config --libs Qt6Core Qt6Gui)

echo "built $OUT/kwin/plugins/dndscroll.so for kwin $(grep -oP 'KWIN_PLUGIN_VERSION_STRING "\K[^"]+' "$KWIN_INC/config-kwin.h")"
