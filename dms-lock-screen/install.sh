#!/usr/bin/env bash
# Install (or with "uninstall": remove) the DMS lock screen video wallpaper patch.
# usage: sudo bash install.sh [uninstall]
set -e
here=$(cd "$(dirname "$0")" && pwd)

if [ "${1:-}" = "uninstall" ]; then
    rm -f /etc/pacman.d/hooks/dms-lock-video.hook /usr/local/bin/dms-lock-video-patch
    if grep -q lockVideoWallpaper /usr/share/quickshell/dms/Modules/Lock/LockScreenContent.qml; then
        patch -d /usr/share/quickshell/dms -p1 -R -s --no-backup-if-mismatch \
            < /usr/local/share/dms-lock-video/lock-video-wallpaper.patch
    fi
    rm -rf /usr/local/share/dms-lock-video
    echo "dms-lock-video: removed, lock screen is stock again"
    exit 0
fi

install -Dm644 "$here/lock-video-wallpaper.patch" /usr/local/share/dms-lock-video/lock-video-wallpaper.patch
install -Dm755 "$here/dms-lock-video-patch" /usr/local/bin/dms-lock-video-patch
install -Dm644 "$here/dms-lock-video.hook" /etc/pacman.d/hooks/dms-lock-video.hook
/usr/local/bin/dms-lock-video-patch
