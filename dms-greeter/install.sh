#!/usr/bin/env bash
# Install, update (or with "uninstall": remove) the live Wallpaper Engine scene on the DMS login screen.
#
# greetd runs dms-greeter-live in place of dms-greeter (the command in /etc/greetd/config.toml); it runs
# dms-greeter with a patched copy of its own UI (greeter-live-wallpaper.patch), which starts the scene the
# linuxWallpaperEngine plugin names (greeter-wallpaper.json) under the login screen. The greeter user needs to
# reach the scenes in Steam's folder: a traverse-only ACL for the greeter group on ~/.local/share/Steam.
# Takes effect at the next login screen.
# usage: bash install.sh [uninstall]   (as your user; sudo only when /etc/greetd/config.toml isn't yours)
set -e
here=$(cd "$(dirname "$0")" && pwd)
share=$HOME/.local/share/dms-greeter-live
config=/etc/greetd/config.toml
wrapper=$share/dms-greeter-live
steam=$HOME/.local/share/Steam

# writes stdin to the greetd config in place (/etc/greetd itself is root's); never in the same pipe as read_config
write_config() {
    if [ -w "$config" ]; then
        cat > "$config"
    else
        sudo tee "$config" > /dev/null
    fi
}

read_config() {
    if [ -r "$config" ]; then cat "$config"; else sudo cat "$config"; fi
}

if [ "${1:-}" = "uninstall" ]; then
    if read_config | grep -qF "$wrapper"; then
        new=$(read_config | sed "s|$wrapper|/usr/bin/dms-greeter|")
        printf '%s\n' "$new" | write_config
    fi
    rm -rf "$share"
    echo "dms-greeter: removed, the login screen is stock again"
    exit 0
fi

if ! read_config | grep -qE '^command *= *"[^"]*dms-greeter'; then
    echo "dms-greeter: $config doesn't run dms-greeter, nothing to do" >&2
    exit 1
fi

install -Dm755 "$here/dms-greeter-live" "$wrapper"
install -Dm644 "$here/greeter-live-wallpaper.patch" "$share/greeter-live-wallpaper.patch"
chmod 755 "$share"

# the greeter user reaches the scenes and the assets in Steam's folder (it's private to you otherwise)
if [ -d "$steam" ] && command -v setfacl > /dev/null && getent group greeter > /dev/null; then
    setfacl -m g:greeter:x "$steam"
fi

# the patch fits this dms-greeter: build the patched UI once in a scratch cache dir
scratch=$(mktemp -d)
if ! DMS_GREETER_LIVE_CHECK=1 "$wrapper" --cache-dir "$scratch" > /dev/null; then
    chmod -R u+w "$scratch"; rm -rf "$scratch"
    echo "dms-greeter: the patch doesn't fit this dms-greeter, the login screen stays stock" >&2
    exit 1
fi
chmod -R u+w "$scratch"; rm -rf "$scratch"

if ! read_config | grep -qF "$wrapper"; then
    cp -n "$config" "$share/config.toml.orig" 2>/dev/null || read_config > "$share/config.toml.orig"
    new=$(read_config | sed -E "s#^(command *= *\")[^ \"]*dms-greeter #\1$wrapper #")
    printf '%s\n' "$new" | write_config
fi
if read_config | grep -qF "$wrapper"; then
    echo "dms-greeter: installed, the next login screen shows the live scene"
else
    echo "dms-greeter: couldn't point greetd at $wrapper (in $config)" >&2
    exit 1
fi
