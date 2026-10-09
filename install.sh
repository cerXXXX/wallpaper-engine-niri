#!/usr/bin/env bash
# Installs or updates everything: the patched engine, both DMS plugins, the lock screen patch.
# Safe to rerun after `git pull`: an engine that's already at this version isn't rebuilt, the plugins are
# updated with `git pull --ff-only`, the lock screen patch replaces an older version of itself.
#
# usage: ./install.sh [--no-engine] [--rebuild-engine] [--no-lock-screen] [--no-restart]
# Run it as your user, it asks for sudo itself where it needs it.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
plugins_dir="${XDG_CONFIG_HOME:-$HOME/.config}/DankMaterialShell/plugins"

# plugin id, folder under plugins_dir, repo; upstream repo an existing checkout is switched away from
plugins=(
    "linuxWallpaperEngine|linuxWallpaperEngine|https://github.com/cerXXXX/dms-wallpaperengine|sgtaziz/dms-wallpaperengine"
    "weDashBridge|weDashBridge|https://github.com/cerXXXX/dms-wallpaperengine-dashbridge|"
)

do_engine=1
rebuild_engine=0
do_lock=1
do_restart=1

for arg in "$@"; do
    case "$arg" in
        --no-engine) do_engine=0 ;;
        --rebuild-engine) rebuild_engine=1 ;;
        --no-lock-screen) do_lock=0 ;;
        --no-restart) do_restart=0 ;;
        -h | --help)
            sed -n '2,7p' "$0" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "unknown option: $arg (see --help)" >&2
            exit 2
            ;;
    esac
done

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }
warn() { printf '\033[33mwarning:\033[0m %s\n' "$*" >&2; }

if [ "$(id -u)" -eq 0 ]; then
    echo "Run it as your user, not root: makepkg refuses root and the plugins go to your ~/.config." >&2
    exit 1
fi

dms_running() { command -v dms >/dev/null && dms ipc call plugins list >/dev/null 2>&1; }

# --- engine
if [ "$do_engine" = 1 ]; then
    step "Engine (linux-wallpaperengine-git)"
    wanted=$(cd "$here/engine" && bash -c 'source ./PKGBUILD && echo "$pkgver-$pkgrel"')
    installed=$(pacman -Q linux-wallpaperengine-git 2>/dev/null | awk '{print $2}' || true)

    if [ "$installed" = "$wanted" ] && [ "$rebuild_engine" = 0 ]; then
        echo "already installed: $installed (--rebuild-engine builds it again)"
    else
        echo "installed: ${installed:-none}, building $wanted"
        # no -C: the previous build's objects are reused (prepare() resets the patched sources); all cores unless
        # MAKEFLAGS says otherwise
        (cd "$here/engine" && MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}" makepkg -si --noconfirm)
    fi
fi

# --- plugins
step "DMS plugins"
mkdir -p "$plugins_dir"
new_plugins=()

for entry in "${plugins[@]}"; do
    IFS='|' read -r id folder repo upstream <<< "$entry"
    dir="$plugins_dir/$folder"

    if [ ! -e "$dir" ]; then
        echo "$id: cloning $repo"
        git clone --quiet "$repo" "$dir"
        new_plugins+=("$id")
        continue
    fi

    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
        warn "$id: $dir isn't a git checkout, left as it is (move it away and rerun to get the fork)"
        continue
    fi

    origin=$(git -C "$dir" remote get-url origin 2>/dev/null || true)
    if [ -n "$upstream" ] && [[ "$origin" == *"$upstream"* ]]; then
        echo "$id: switching the checkout from $origin to $repo"
        git -C "$dir" remote set-url origin "$repo"
    fi

    branch=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
    if [ "$branch" != "main" ]; then
        warn "$id: the checkout is on branch '$branch', not main; not updated"
        continue
    fi

    before=$(git -C "$dir" rev-parse --short HEAD)
    if git -C "$dir" pull --quiet --ff-only; then
        after=$(git -C "$dir" rev-parse --short HEAD)
        if [ "$before" = "$after" ]; then echo "$id: up to date ($after)"; else echo "$id: updated $before -> $after"; fi
    else
        warn "$id: 'git pull --ff-only' failed in $dir (local changes or diverged history?); not updated"
    fi
done

# --- lock screen
if [ "$do_lock" = 1 ]; then
    step "Lock screen patch (sudo)"
    sudo bash "$here/dms-lock-screen/install.sh"
fi

# --- niri: the rule can't be merged into someone's config blindly, so only check for it
niri_config="${XDG_CONFIG_HOME:-$HOME/.config}/niri/config.kdl"
if [ -f "$niri_config" ] && ! grep -q 'linux-wallpaperengine' "$niri_config"; then
    warn "add the layer rule from system/niri-layer-rule.kdl to $niri_config (keeps the wallpaper out of the overview's workspace cards)"
fi

# --- DMS: it doesn't watch plugin files, so a restart picks the updates up; new plugins get enabled after it
if [ "$do_restart" = 1 ]; then
    if dms_running; then
        step "Restarting DMS"
        dms restart >/dev/null 2>&1 || warn "'dms restart' failed"

        # wait for the new shell to answer before enabling plugins in it
        sleep 2
        for _ in $(seq 30); do
            dms_running && break
            sleep 0.5
        done

        for id in "${new_plugins[@]}"; do
            if dms ipc call plugins enable "$id" >/dev/null 2>&1; then
                echo "$id: enabled"
            else
                warn "$id: couldn't enable it, do it in DMS Settings -> Plugins"
            fi
        done
    else
        warn "DMS isn't running; the changes apply when it starts (enable new plugins in DMS Settings -> Plugins)"
    fi
else
    echo
    echo "Run 'dms restart' to load the updated plugins and lock screen."
fi

step "Done"
