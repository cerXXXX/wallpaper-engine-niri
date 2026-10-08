#!/usr/bin/env bash
# Install, update (or with "uninstall": remove) the DMS lock screen patch: video wallpapers,
# the desktop's Wallpaper Engine video on the lock screen and the "Blur Wallpaper" toggle.
# usage: sudo bash install.sh [uninstall]
set -e
here=$(cd "$(dirname "$0")" && pwd)
shell=/usr/share/quickshell/dms
lock="$shell/Modules/Lock/LockScreenContent.qml"
installed=/usr/local/share/dms-lock-video/lock-video-wallpaper.patch
# only the current version of the patch has this (keep in sync with dms-lock-video-patch)
marker=lockVideos

# take out whatever version is applied, using the patch file it was applied from
unpatch() {
    if grep -q lockVideoWallpaper "$lock" && [ -f "$installed" ]; then
        patch -d "$shell" -p1 -R -s --no-backup-if-mismatch < "$installed"
    fi
}

if [ "${1:-}" = "uninstall" ]; then
    rm -f /etc/pacman.d/hooks/dms-lock-video.hook /usr/local/bin/dms-lock-video-patch
    unpatch
    rm -rf /usr/local/share/dms-lock-video
    echo "dms-lock-video: removed, lock screen is stock again"
    exit 0
fi

# updating from an older version: revert it before the new patch goes in
if ! grep -q "$marker" "$lock"; then
    unpatch
fi

install -Dm644 "$here/lock-video-wallpaper.patch" /usr/local/share/dms-lock-video/lock-video-wallpaper.patch
install -Dm755 "$here/dms-lock-video-patch" /usr/local/bin/dms-lock-video-patch
install -Dm644 "$here/dms-lock-video.hook" /etc/pacman.d/hooks/dms-lock-video.hook
/usr/local/bin/dms-lock-video-patch
