#!/usr/bin/env bash
# Installs or updates everything: the patched engine, niri with the wallpaper under the lock screen, both DMS
# plugins, the lock screen patch, the live scene on the login screen (dms-greeter).
# Safe to rerun after `git pull`: an engine that's already at this version isn't rebuilt, the plugins are
# updated with `git pull --ff-only`, the lock screen patch replaces an older version of itself.
#
# usage: ./install.sh [--no-engine] [--rebuild-engine] [--no-niri] [--rebuild-niri] [--no-lock-screen] [--no-greeter]
#                     [--no-restart]
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
do_niri=1
rebuild_niri=0
niri_updated=0
do_lock=1
do_greeter=1
do_restart=1

for arg in "$@"; do
    case "$arg" in
        --no-engine) do_engine=0 ;;
        --rebuild-engine) rebuild_engine=1 ;;
        --no-niri) do_niri=0 ;;
        --rebuild-niri) rebuild_niri=1 ;;
        --no-lock-screen) do_lock=0 ;;
        --no-greeter) do_greeter=0 ;;
        --no-restart) do_restart=0 ;;
        -h | --help)
            sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
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
    step "Engine (linux-wallpaperengine-niri)"
    wanted=$(cd "$here/engine" && bash -c 'source ./PKGBUILD && echo "$pkgver-$pkgrel"')
    installed=$(pacman -Q linux-wallpaperengine-niri 2>/dev/null | awk '{print $2}' || true)
    # the package was called linux-wallpaperengine-git before, or that's the AUR's stock engine: pacman asks to
    # replace it, so no --noconfirm then (its default answer is no)
    replaced=$(pacman -Q linux-wallpaperengine-git 2>/dev/null || true)
    confirm=(--noconfirm)
    [ -n "$replaced" ] && confirm=()

    if [ "$installed" = "$wanted" ] && [ "$rebuild_engine" = 0 ]; then
        echo "already installed: $installed (--rebuild-engine builds it again)"
    else
        echo "installed: ${installed:-${replaced:-none}}, building $wanted"
        # no -C: the previous build's objects are reused (makepkg checks out the pinned commit); all cores unless
        # MAKEFLAGS says otherwise
        (cd "$here/engine" && MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}" makepkg -si "${confirm[@]}")
    fi
fi

# --- niri: the stock one draws nothing but the lock surface while locked, the patched one (niri/) shows the running
# wallpaper under a see-through lock screen; its own package, so pacman asks to replace niri (no --noconfirm)
if [ "$do_niri" = 1 ]; then
    step "niri with the wallpaper under the lock screen (niri-lock-wallpaper)"
    wanted=$(cd "$here/niri" && bash -c 'source ./PKGBUILD && echo "$pkgver-$pkgrel"')
    installed=$(pacman -Q niri-lock-wallpaper 2>/dev/null | awk '{print $2}' || true)
    arch_niri=$(LC_ALL=C pacman -Si niri 2>/dev/null | awk '/^Version/ {print $3; exit}' || true)

    if [ "$installed" = "$wanted" ] && [ "$rebuild_niri" = 0 ]; then
        echo "already installed: $installed (--rebuild-niri builds it again)"
    else
        echo "installed: ${installed:-none (stock niri: $(pacman -Q niri 2>/dev/null | awk '{print $2}'))}, building $wanted"
        (cd "$here/niri" && MAKEFLAGS="${MAKEFLAGS:--j$(nproc)}" makepkg -si)
        niri_updated=1
    fi
    if [ -n "$arch_niri" ] && [ "$(vercmp "${arch_niri%-*}" "${wanted%-*}")" -gt 0 ]; then
        warn "Arch has niri $arch_niri, niri/PKGBUILD is still at $wanted: bump pkgver there (and check the patch still applies)"
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
    step "Lock screen patch"
    bash "$here/dms-lock-screen/install.sh" || warn "the lock screen patch doesn't fit this DMS version, the lock screen stays stock"
fi

# --- login screen: only where dms-greeter is the greetd greeter
if [ "$do_greeter" = 1 ] && command -v dms-greeter >/dev/null; then
    step "Login screen (dms-greeter)"
    bash "$here/dms-greeter/install.sh" || warn "the login screen stays stock"
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

if [ "$niri_updated" = 1 ]; then
    echo
    echo "niri was updated: log out and back in to run it (the lock screen shows the wallpaper at once with"
    echo "the plugin's Blur on Lock Screen off)."
fi

step "Done"
