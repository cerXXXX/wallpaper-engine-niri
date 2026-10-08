# Wallpaper Engine on niri + DankMaterialShell

My setup for animated [Wallpaper Engine](https://store.steampowered.com/app/431960/) wallpapers on Arch Linux with
[niri](https://github.com/YaLTeR/niri) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(DMS), tuned for a laptop with an Intel iGPU. Wallpapers are rendered by
[linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) and managed by the
[Linux Wallpaper Engine](https://github.com/sgtaziz/dms-wallpaperengine) DMS plugin.

| Part | What it does |
|---|---|
| [dms-wallpaperengine-dashbridge](https://github.com/cerXXXX/dms-wallpaperengine-dashbridge) | DMS plugin (separate repo): the whole Workshop library in the DMS wallpaper picker, keeps the DMS wallpaper from covering the engine, video wallpapers on the lock screen |
| [`engine/`](engine) | linux-wallpaperengine patches + PKGBUILD: zero-copy VA-API video, correct video frame pacing, video wallpapers rendered at the video's frame rate |
| [`wallpaperengine-plugin/`](wallpaperengine-plugin) | Patch for the Linux Wallpaper Engine DMS plugin: stale screenshot timers |
| [`dms-lock-screen/`](dms-lock-screen) | DMS patch + pacman hook: a video set as the lock screen wallpaper plays behind the clock and password field |
| [`system/`](system) | niri layer rule, `makepkg.conf` without `-debug` packages |

## Install from scratch

1. **Wallpaper Engine.** Buy and install it through Steam (linux-wallpaperengine needs its `assets`), subscribe to
   wallpapers in the Workshop.
2. **No debug packages** (optional, saves ~1.4 GiB per engine build):
   `cp system/makepkg.conf ~/.config/pacman/makepkg.conf`
3. **Engine** (patched):
   ```sh
   cd engine && makepkg -si
   ```
4. **DMS plugins:**
   ```sh
   dms plugins install linuxWallpaperEngine
   git clone https://github.com/cerXXXX/dms-wallpaperengine-dashbridge \
       ~/.config/DankMaterialShell/plugins/weDashBridge
   dms ipc call plugins enable weDashBridge
   ```
   Optionally apply the plugin fix:
   `git -C ~/.config/DankMaterialShell/plugins/linuxWallpaperEngine am "$PWD"/wallpaperengine-plugin/*.patch`
   (a later `dms plugins update` may then need the commit dropped or rebased).
5. **Plugin settings** (DMS Settings → Plugins → Linux Wallpaper Engine): enable **Generate static wallpaper**, pick a
   wallpaper once, enable **Pause on Battery**.
6. **niri:** add [`system/niri-layer-rule.kdl`](system/niri-layer-rule.kdl) to `~/.config/niri/config.kdl`.
7. **Lock screen video** (optional):
   ```sh
   sudo bash dms-lock-screen/install.sh   # uninstall: sudo bash dms-lock-screen/install.sh uninstall
   dms restart
   ```

After that wallpapers are switched from the DMS dashboard (click the bar clock → Wallpapers).

## Engine patches

All three apply on upstream `b016d7d` (pinned in the PKGBUILD).

- **0001 zero-copy VA-API.** `GLPlayer` created the libmpv render context without `MPV_RENDER_PARAM_WL_DISPLAY`, so mpv
  had no hwdec interop and fell back to `vaapi-copy`, copying every decoded frame through system memory. The Wayland
  driver now exposes its `wl_display` and mpv decodes with `vaapi`.
- **0002 video frame pacing.** `mpv_render_context_render ()` blocked until the next video frame was due
  (`BLOCK_FOR_TARGET_TIME` defaults to 1) on top of the engine's own pacing, so some videos updated far below their
  frame rate. Pacing is left to the engine.
- **0003 video frame rate cap.** With 0002, a 24 fps video was redrawn at `--fps` (30). The engine now reads
  `container-fps` and, when every output shows a plain video, renders at the fastest video's rate; `--fps` stays the
  upper bound, scenes and web wallpapers are unaffected.

Measured on Intel Iris Xe (Tiger Lake), niri, one 1920x1080@60 output; rendered frames counted from
`wl_surface.attach` with `WAYLAND_DEBUG=1`, CPU as a share of one core:

| | 1080p24 video A | 1080p23.976 video B | 4K scene |
|---|---|---|---|
| upstream | 16% CPU (`vaapi-copy`) | — | — |
| + 0001 | 13 fps, 3% CPU | 24 fps, 4% CPU | 29 fps, 1% CPU |
| + 0001–0003 | 23.4 fps, 2% CPU | 23.4 fps, 3% CPU | 29 fps, 1% CPU |

Playback speed was checked with a 24 fps video with a burned-in clock (10 s on screen per 10 s of wall time).

### Updating to a newer upstream

Change `_commit` (or use `#branch=main`) in [`engine/PKGBUILD`](engine/PKGBUILD) and run `makepkg -si`. If a patch
no longer applies, `prepare()` stops with the failing hunk.

## Known limits

- Scenes render at their project resolution. A 3840x2160 scene with two full-screen effects took 47% of the iGPU
  render engine at 30 fps (23% at 15 fps, 15% at 10 fps) on a 1080p screen. Ideas: a per-scene FPS setting in the
  plugin, or rendering scenes no larger than the output.
- A 24 fps video on a 60 Hz panel without VRR can't be shown evenly (3:2 pulldown).
- Only video wallpapers animate on the lock screen; the lock screen can't host the engine.

## Licenses

My own files (scripts, PKGBUILD, docs) are MIT, see [LICENSE](LICENSE). Each patch is a modification of the project
it applies to and follows that project's license: linux-wallpaperengine is GPL-3.0, DankMaterialShell is MIT. The
Linux Wallpaper Engine plugin has no license file upstream; its patch is here for personal use.
