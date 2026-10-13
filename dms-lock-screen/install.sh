#!/usr/bin/env bash
# Install, update (or with "uninstall": remove) the DMS lock screen patch: video wallpapers,
# the desktop's Wallpaper Engine video and live scenes on the lock screen, the "Blur Wallpaper" toggle.
#
# DMS 1.6+ carries its UI inside the dms binary, so there are no installed QML files to patch any more:
# the dms user service runs a patched copy of the binary's UI instead (dms-lock-ui, rebuilt before every
# DMS start, so dms-shell upgrades keep the patch). Takes effect on the next DMS start (dms restart).
# usage: bash install.sh [uninstall]   (as your user; sudo only to remove the old pacman hook if it's there)
set -e
here=$(cd "$(dirname "$0")" && pwd)
# the drop-in names these paths with %h and %t
share=$HOME/.local/share/dms-lock-screen
dropin_dir=${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/dms.service.d
runtime=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}

# versions before DMS 1.6 patched /usr/share/quickshell/dms from a pacman hook; that path is gone and the
# hook only logs an error on every dms-shell upgrade
legacy=(/etc/pacman.d/hooks/dms-lock-video.hook /usr/local/bin/dms-lock-video-patch /usr/local/share/dms-lock-video)
remove_legacy() {
    local found=()
    for f in "${legacy[@]}"; do
        [ -e "$f" ] && found+=("$f")
    done
    [ ${#found[@]} -eq 0 ] && return
    echo "dms-lock-screen: removing the old pacman hook (sudo): ${found[*]}"
    sudo rm -rf "${found[@]}" || echo "dms-lock-screen: couldn't remove them, they're harmless (the hook only logs that the patch doesn't apply)" >&2
}

if [ "${1:-}" = "uninstall" ]; then
    rm -f "$dropin_dir/lock-screen.conf"
    rmdir "$dropin_dir" 2>/dev/null || true
    rm -rf "$share" "$runtime/dms-lock-ui" "$runtime/dms-lock-ui.env"
    systemctl --user daemon-reload
    remove_legacy
    echo "dms-lock-screen: removed, the lock screen is stock again after the next DMS start (dms restart)"
    exit 0
fi

install -Dm755 "$here/dms-lock-ui" "$share/dms-lock-ui"
install -Dm644 "$here/lock-video-wallpaper.patch" "$share/lock-video-wallpaper.patch"
install -Dm644 "$here/lock-screen.conf" "$dropin_dir/lock-screen.conf"
systemctl --user daemon-reload
remove_legacy

# build it now, so a patch that doesn't fit this DMS shows up here and not only in the journal
if "$share/dms-lock-ui" && [ -f "$runtime/dms-lock-ui.env" ]; then
    echo "dms-lock-screen: installed, DMS picks it up on its next start (dms restart)"
else
    echo "dms-lock-screen: installed, but the patch doesn't apply to this DMS: the lock screen stays stock" >&2
    exit 1
fi
