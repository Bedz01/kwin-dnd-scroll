# kwin-dnd-scroll

Scroll with the mouse wheel **while dragging** on KDE Plasma (Wayland).

Drag a file over a folder view that's scrolled too far, turn the wheel, and the view under the cursor
scrolls. Windows and macOS do this. On Wayland every compositor I checked (KWin, wlroots, Weston, Mutter)
throws wheel events away for the whole length of a drag, so nothing scrolls until you drop.

This is a small KWin plugin that hands those wheel events to the window under the cursor instead.

- [Install](#install)
- [Turning it off: Scroll Lock](#turning-it-off-scroll-lock)
- [How it works](#how-it-works)
- [Limitations](#limitations)
- [Background](#background)

## Install

Needs KWin 6 on Wayland, with its development headers. Tested on KWin 6.7.5 and 6.8.2 (Arch Linux), with
Qt 6 apps and Firefox.

```sh
# Arch: KWin's headers ship in the kwin package
sudo pacman -S --needed cmake extra-cmake-modules vulkan-headers

git clone https://github.com/Bedz01/kwin-dnd-scroll.git
cd kwin-dnd-scroll
cmake -B build -DCMAKE_INSTALL_PREFIX=/usr -DCMAKE_BUILD_TYPE=Release
cmake --build build
sudo cmake --install build
```

Other distros need their KWin development package plus the libraries KWin's CMake config asks for
(Qt 6 Quick/DBus/Widgets, KF6 Config/CoreAddons/WindowSystem, Wayland, epoxy, libdrm, Vulkan headers).

No CMake? `./build.sh` builds the same plugin with plain `g++` and `moc` into `build/kwin/plugins/`.

KWin loads it on its next start. To load it into the running session right away:

```sh
qdbus6 org.kde.KWin /Plugins org.kde.KWin.Plugins.LoadPlugin dndscroll     # on
qdbus6 org.kde.KWin /Plugins org.kde.KWin.Plugins.UnloadPlugin dndscroll   # off
```

> [!IMPORTANT]
> **Rebuild after every KWin update.** A KWin plugin only loads into the exact KWin release it was built
> against (the plugin interface id carries the version, e.g. `6.8.2`). After an update the old build is
> silently skipped: nothing breaks, scrolling during drags just stops until you rebuild and reinstall.

To stop it loading at startup, set `dndscrollEnabled=false` in the `[Plugins]` group of `kwinrc`, or delete
`/usr/lib/qt6/plugins/kwin/plugins/dndscroll.so`.

## Turning it off: Scroll Lock

While the Scroll Lock LED is on, the plugin stands aside and drags behave as in stock KWin. Off (the
default) means scrolling during drags works.

On most setups the Scroll Lock key does nothing and its LED never lights. The default keymap gives the key a
lock action on a modifier that isn't bound to anything. To fix that, turn on the xkb option
`scrolllock:mod3`:

- System Settings → Keyboard → Key Bindings → Configure keyboard options → Compatibility options →
  **Map Scroll Lock to Mod3**

Mod3 is also where xkb puts the "level 5" modifier, which only layouts with a fifth level (Neo and
similar) use.

## How it works

During a pointer drag, KWin sends the drop target `wl_data_device` events instead of pointer events, takes
pointer focus away from every window that takes part in drag-and-drop, and drops wheel events in
`SeatInterface::notifyPointerAxis`. A Wayland wheel event (`wl_pointer.axis`) has no surface argument; it
goes to whichever surface last got `wl_pointer.enter`. So the plugin needs to do two things:

1. An input filter that sits just ahead of KWin's own forwarding filter catches wheel events during a
   pointer drag. Global shortcuts, effects and window decorations still see them first.
2. It lends pointer focus to the drag target: `wl_pointer.enter` at the cursor position the first time,
   `wl_pointer.motion` on later notches, then the axis event and a frame. The loan ends with
   `wl_pointer.leave` when the drag moves to another surface or ends. If KWin moves pointer focus itself
   in the meantime, the plugin backs off.

The seat's own focus record is never touched, so the button release that ends the drag still goes to the
drag and not to the target as a click.

Focus is lent for the whole visit, not per notch, because Qt merges pointer frames that arrive within
100 µs onto a timer. An enter, axis, leave burst loses the scroll, because by the time the timer fires the
window no longer has focus.

## Limitations

- **Qt apps ignore the wheel in their own windows while they're the one dragging.** Qt's drag loop
  (`QBasicDrag::eventFilter`) eats wheel and key events in the app that started the drag
  ([QTBUG-71288](https://bugreports.qt.io/browse/QTBUG-71288)). Dragging from a Qt app into another app
  works; scrolling inside the source app needs that app to install its own event filter after the drag
  starts. Firefox has no such filter and scrolls within its own window too.
- **Xwayland windows** as drop targets are skipped.
- Tested with Qt apps and Firefox. GTK and Chromium are untested; reports welcome.
- While a window has the lent focus it sees hover at the scroll position, updated only on wheel notches.
  The cursor stays KWin's drag cursor throughout.
- It runs inside the compositor: a crash takes the session down with it. `UnloadPlugin` is the quick off
  switch.

## Background

- [wayland-protocols#189](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/issues/189): the
  protocol-level request, open, with a good comment on why a general fix is hard.
- [KDE bug 194231](https://bugs.kde.org/show_bug.cgi?id=194231): "scrolling folder view during drag-n-drop
  action does not work" (Dolphin, 2009).
- [QTBUG-71288](https://bugreports.qt.io/browse/QTBUG-71288): Qt eats wheel events during its own drags.

## License

GPL-2.0-or-later, like KWin. See [LICENSE](LICENSE).
