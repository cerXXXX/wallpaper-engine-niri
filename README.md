# Wallpaper Engine on niri + DankMaterialShell

My setup for animated [Wallpaper Engine](https://store.steampowered.com/app/431960/) wallpapers on Arch Linux with
[niri](https://github.com/YaLTeR/niri) and [DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell)
(DMS), tuned for a laptop with an Intel iGPU. Wallpapers are rendered by
[linux-wallpaperengine](https://github.com/Almamu/linux-wallpaperengine) and managed by my fork of the
[Linux Wallpaper Engine](https://github.com/sgtaziz/dms-wallpaperengine) DMS plugin.

| Part | What it does |
|---|---|
| [dms-wallpaperengine-dashbridge](https://github.com/cerXXXX/dms-wallpaperengine-dashbridge) | DMS plugin (separate repo): the whole Workshop library in the DMS wallpaper picker, keeps the DMS wallpaper from covering the engine, video wallpapers on the lock screen |
| [dms-wallpaperengine](https://github.com/cerXXXX/dms-wallpaperengine) | Fork of the Linux Wallpaper Engine DMS plugin (separate repo): **Downscale to Screen** toggle, separate scene/video FPS, per-scene render settings, scene properties with readable choices (language picker, color picker, options of other languages hidden), **Layers & Effects** to turn parts of a scene off, live scenes on the lock screen, **Power Modes** per power profile (eco holds the wallpaper still with live clocks), stale screenshot timer fix |
| [`engine/`](engine) | linux-wallpaperengine patches + PKGBUILD: zero-copy VA-API video, correct video frame pacing, video wallpapers rendered at the video's frame rate, `--downscale-to-output`, scene clocks/text and scripts that work, `--stream` (live scenes for the lock screen), hidden layers not loaded and layers/effects the user can turn off, a first-frame marker, `--eco` (held still, redrawn only when a clock changes) with a control channel and sound fades |
| [`dms-lock-screen/`](dms-lock-screen) | DMS patch + pacman hook: a video set as the lock screen wallpaper (or the desktop's Wallpaper Engine video) plays behind the clock and password field, the desktop's Wallpaper Engine scene runs live there (held still with live clocks in eco); a **Blur Wallpaper** toggle for the lock screen background |
| [`system/`](system) | niri layer rule, `makepkg.conf` without `-debug` packages |

## Install or update everything

```sh
git clone https://github.com/cerXXXX/wallpaper-engine-niri
cd wallpaper-engine-niri
./install.sh
```

Updating later: `git pull && ./install.sh`. The script, run as your user (it asks for sudo itself):

- builds and installs the patched engine with `makepkg -si` on all cores, unless that version is already installed
  (the previous build in `engine/src` is reused, so a new patch only compiles what it changed; `rm -rf engine/src`
  for a clean build);
- clones both DMS plugins into `~/.config/DankMaterialShell/plugins`, or updates existing checkouts with
  `git pull --ff-only` (a checkout of the upstream plugin is switched to the fork first; one on another branch or
  with local changes is left alone with a warning);
- installs or updates the lock screen patch (`sudo bash dms-lock-screen/install.sh`);
- warns if the niri layer rule is missing from `~/.config/niri/config.kdl` (it doesn't edit your config);
- restarts DMS and enables newly cloned plugins.

Options: `--no-engine`, `--rebuild-engine`, `--no-lock-screen`, `--no-restart`. Wallpaper Engine itself (step 1
below) and the plugin settings (step 5) are still up to you.

## Install by hand

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
   git clone https://github.com/cerXXXX/dms-wallpaperengine \
       ~/.config/DankMaterialShell/plugins/linuxWallpaperEngine
   git clone https://github.com/cerXXXX/dms-wallpaperengine-dashbridge \
       ~/.config/DankMaterialShell/plugins/weDashBridge
   dms ipc call plugins enable linuxWallpaperEngine
   dms ipc call plugins enable weDashBridge
   ```
   An existing install of the upstream plugin (a git checkout of sgtaziz's `main`) switches to the fork with
   ```sh
   cd ~/.config/DankMaterialShell/plugins/linuxWallpaperEngine
   git remote set-url origin https://github.com/cerXXXX/dms-wallpaperengine
   git pull --ff-only
   ```
5. **Plugin settings** (DMS Settings → Plugins → Linux Wallpaper Engine): enable **Generate static wallpaper**, pick a
   wallpaper once, pick the **Power Modes** for each power profile (defaults: Full / Eco / Eco), and under Advanced Settings → Performance & Rendering enable
   **Downscale to Screen** (needs the patched engine from step 3).
6. **niri:** add [`system/niri-layer-rule.kdl`](system/niri-layer-rule.kdl) to `~/.config/niri/config.kdl`.
7. **Lock screen video and blur toggle** (optional):
   ```sh
   sudo bash dms-lock-screen/install.sh   # uninstall: sudo bash dms-lock-screen/install.sh uninstall
   dms restart
   ```
   Rerun it after `git pull` to update an installed older version. With no custom lock screen wallpaper, a monitor
   showing a Wallpaper Engine **video** wallpaper plays the same video on the lock screen (the plugin fork publishes
   it; `dms ipc call linuxWallpaperEngine lockVideos` shows what it publishes), and a **scene** runs live: the plugin
   streams it while locked (patched engine, plugin toggle **Live Scene on Lock Screen**, on by default;
   `dms ipc call linuxWallpaperEngine lockStreams` shows the streams while locked). In eco the scene is held still
   and only a changed frame is written (clocks, `--frame-file`), the lock screen shows it as an image
   (`dms ipc call linuxWallpaperEngine lockFrames`). The blur is switched in DMS
   Settings → Lock Screen → Appearance → **Blur Wallpaper** (on by default, as in stock DMS).

After that wallpapers are switched from the DMS dashboard (click the bar clock → Wallpapers).

## Engine patches

All seven apply on upstream `b016d7d` (pinned in the PKGBUILD).

- **0001 zero-copy VA-API.** `GLPlayer` created the libmpv render context without `MPV_RENDER_PARAM_WL_DISPLAY`, so mpv
  had no hwdec interop and fell back to `vaapi-copy`, copying every decoded frame through system memory. The Wayland
  driver now exposes its `wl_display` and mpv decodes with `vaapi`.
- **0002 video frame pacing.** `mpv_render_context_render ()` blocked until the next video frame was due
  (`BLOCK_FOR_TARGET_TIME` defaults to 1) on top of the engine's own pacing, so some videos updated far below their
  frame rate. Pacing is left to the engine.
- **0003 video frame rate cap.** With 0002, a 24 fps video was redrawn at `--fps` (30). The engine now reads
  `container-fps` and, when every output shows a plain video, renders at the fastest video's rate; `--fps` stays the
  upper bound, scenes and web wallpapers are unaffected.
- **0004 `--downscale-to-output`.** Scenes render into framebuffers the size of their projection, and every image layer
  with effects into framebuffers the size of its texture, so a 3840x2160 scene on a 1920x1080 screen does all its
  passes at four times the pixels the screen shows; videos are drawn to a texture of the video's size. With the flag
  (the plugin's **Downscale to Screen** toggle) a wallpaper bigger than its output renders at the output's
  resolution: the scene, bloom, shadow, layer and effect framebuffers are created scaled down while the camera and
  geometry stay in scene units, and mpv renders videos into a texture of the scaled size. The scale covers the output
  for fill/stretch/default scaling and fits inside it for fit; a span group uses its bounding box at the densest
  screen's pixel ratio. Nothing is scaled up, and screenshots (the plugin's static wallpaper) read the framebuffer at
  its real size. Effects keep their size on screen (`g_TexelSize` stays in scene units); a 1:1 crop of the 4K scene
  looks the same at both resolutions.
- **0005 scene clocks, compose layers, scripts.** Found on a clock + audio visualizer scene
  ([3299228616](https://steamcommunity.com/sharedfiles/filedetails/?id=3299228616)), the fixes are generic:
  - compose layers with `"copybackground": false` start transparent (`CLEARALPHA`); before, their scroll/fisheye effects
    moved a copy of the background around, which showed up as broken rectangles over the clock;
  - objects are hidden when a parent is: scenes switch whole groups (one per language or clock position) through the
    parent's visibility, so every variant used to be drawn on top of each other;
  - text: positioned through its parents like images (it used to land off screen), Y axis and rotation like images,
    `pointsize` in points at 300 DPI and rasterized at its size in the scene, UTF-8, a monospace system font for
    `systemfont_consolas`/`courier`, opacity from `alpha`;
  - integer colors with every channel <= 1 (`"1 1 1"` in `project.json`) are normalized colors, not 0-255 (white text
    came out black);
  - property scripts (`visible`, `origin`, `alpha`... with `export function update`) never ran: evaluating a module
    doesn't expose its exports, `thisLayer` had no properties, and returned values were lost. Scripts now run from the
    module namespace, each with its own `thisLayer` (readable and assignable), `createScriptProperties ()` works at
    the top level, and `thisLayer.getTextureAnimation ()` (`setFrame`/`getFrame`/`frameCount`/`play`/`pause`/`stop`/
    `isPlaying`) drives sprite sheets (the scene's AM/PM marker). The first error of every script is logged once.

  Checked against the other ten installed scenes (screenshots before/after): no visible change except
  [3624053922](https://steamcommunity.com/sharedfiles/filedetails/?id=3624053922), which used to render black and now
  shows.
- **0006 `--stream <url>`.** Renders without showing anything (the GLFW window is created at the `--window` size and
  never mapped) and pipes every frame to an `ffmpeg` child that encodes it with VA-API H.264 into MPEG-TS at the URL
  (`udp://127.0.0.1:41300`), wall-clock timestamps, SPS/PPS on every keyframe so a player can join any time. The
  plugin fork uses it for the lock screen: while locked it starts one streaming engine per screen with a scene and
  the patched lock screen plays the stream. About 20% of one core at 1080p30 for the 4K clock scene, only while
  locked with the screens on.
- **0007 hidden layers aren't loaded.** Properties are applied once at startup, so a layer hidden by one (another
  language, another clock layout) or by the scene's author, with no script that could show it again, stays hidden for
  the whole run. Such layers are now left out of the scene together with everything inside them, unless a visible
  layer depends on them. The multi-language clock scene above is six full copies of itself (one per language), each
  with five clock layouts: 253 of its 271 objects are skipped and the first frame comes after ~1.0 s instead of
  ~3.2 s; screenshots of the installed scenes are unchanged. New options, used
  by the plugin fork's *Layers & Effects* section:
  - `--list-layers` prints the scene's layers and their effects as JSON, with what the scene hides under the given
    `--set-property` values;
  - `--hide-layer ID[,ID...]` hides a layer and everything inside it (not loaded either);
  - `--disable-effect ID[,ID...]` turns a layer effect off.
- **0008 first-frame marker.** Prints `First frame presented` once niri has shown a frame with the wallpaper's
  content on every screen of the process (the Wayland frame callback of that frame; a video counts from mpv's first
  decoded frame, `MPV_EVENT_PLAYBACK_RESTART`, not the empty texture before it). The plugin fork freezes paused
  wallpapers (power saver, battery) with SIGSTOP only after it, so a cold start while paused still shows the
  wallpaper instead of an empty screen. Measured: 0.6 s for a 1080p video, 1.9 s for the clock scene, 3.7 s for the
  4K Big Sur scene.
- **0009 eco mode, control channel, sound fades.**
  - `--eco` holds the wallpaper still once its first frame has been up for a second. The animation time stops
    (particles, shaders, texture animations; videos pause), scripts keep reading the real time. Every second, just
    after the second changes, the frame is rendered and hashed and only shown when it changed: a clock with seconds
    updates every second, one without once a minute, a wallpaper without clocks never. The tick is a `timerfd` that
    is re-aligned when the clock jumps (suspend, time zone).
  - `--control` reads commands on stdin (`eco on|off`, `fps <n>`, `mute on|off`), so the plugin switches modes
    without restarting the engine.
  - `--frame-file <path>` renders in a hidden window like `--stream` and writes each changed frame as PPM, printing
    `Frame written`: the lock screen's eco mode.
  - Sound fades out over 0.5 s (muted, or another app plays) and comes back 2 s after the other app stopped. The
    automute detector never saw anything on PipeWire (native streams carry their process id on the client, not the
    stream); it now checks the client, ignores paused streams and other wallpapers, and polls at most every 250 ms.
    The SDL device is paused while there's nothing to hear (it played silence even with `--silent`), so the sound
    card can sleep.
  - Measured (CPU of one core, 15 FPS, 75 s): the clock scene 2.2% and ~15 frames/s normally, 0.37% and one frame a
    minute (on the minute) with `--eco`; the 1080p video 2.5% → 0.33%.

Measured on Intel Iris Xe (Tiger Lake), niri, one 1920x1080@60 output; rendered frames counted from
`wl_surface.attach` with `WAYLAND_DEBUG=1`, CPU as a share of one core:

| | 1080p24 video A | 1080p23.976 video B | 4K scene |
|---|---|---|---|
| upstream | 16% CPU (`vaapi-copy`) | — | — |
| + 0001 | 13 fps, 3% CPU | 24 fps, 4% CPU | 29 fps, 1% CPU |
| + 0001–0003 | 23.4 fps, 2% CPU | 23.4 fps, 3% CPU | 29 fps, 1% CPU |

Playback speed was checked with a 24 fps video with a burned-in clock (10 s on screen per 10 s of wall time).

0004, same machine at 30 fps; render engine time of the engine process from DRM fdinfo (`drm-engine-render`) as a
share of wall time, frame rate unchanged:

| | 4K scene (two full-screen effects + bloom) | 3840x2160 H.264 video |
|---|---|---|
| full resolution | 46.7% | 9.5% |
| `--downscale-to-output` (1920x1080) | 19.4% | 5.3% |

### Updating to a newer upstream

Change `_commit` (or use `#branch=main`) in [`engine/PKGBUILD`](engine/PKGBUILD) and run `makepkg -si`. If a patch
no longer applies, `prepare()` stops with the failing hunk.

## Known limits

- Even at the output's resolution the 4K scene keeps the iGPU render engine ~19% busy at 30 fps. Idea: a per-scene FPS
  setting in the plugin.
- `--downscale-to-output` sizes the framebuffers once, when the wallpaper loads; after changing the output's mode or
  scale the engine needs a restart.
- A 24 fps video on a 60 Hz panel without VRR can't be shown evenly (3:2 pulldown).
- While the session is locked niri draws nothing but the lock surface (ext-session-lock), so the engine's layer can't
  show through. Videos play on the lock screen directly; scenes are rendered by a second engine and streamed
  (0006), so a scene shows its static screenshot while it loads (~1 s for the 4K clock scene with 0007, plus about
  1 s until the player gets a keyframe) and the stream runs ~1 s behind. Span groups keep the screenshot.

## Licenses

My own files (scripts, PKGBUILD, docs) are MIT, see [LICENSE](LICENSE). Each patch is a modification of the project
it applies to and follows that project's license: linux-wallpaperengine is GPL-3.0, DankMaterialShell is MIT. The
Linux Wallpaper Engine plugin has no license file upstream; my fork of it is for personal use.
