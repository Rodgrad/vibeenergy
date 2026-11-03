# Validation

Verified on the development Manjaro desktop, 2026-11-02:

- Python 3.14.7, Qt 6.11.2, Plasma 6.7.5; Qt extension builds successfully with CMake/C++17.
- 27 unittest tests pass, including integration, gaps, clock jumps, suspend/resume clock simulation, counter wrap, daily/DST boundaries, overlap exclusion, tariff validation/repricing, raw retention with permanent summaries, Powerstat timestamps/rotation/truncation, unknown energy, corrupt database preservation, AMD microwatt conversion, real-style sysfs symlinks, single-instance lock, subprocess shutdown/restart and demo persistence/isolation.
- Real collector successfully discovers the CPU package, integrated Intel GPU and NVIDIA RTX 5070 Ti. CPU explicitly reports `Unavailable: permission denied`. Integrated GPU is excluded from accounting.
- User service is installed, enabled and active; systemd sandboxing starts successfully on this host. Its child is a persistent nvidia-smi query process with 10-second loop. Actual NVIDIA watts (approximately 19–27 W during these checks) reach the local snapshot and accumulate in SQLite daily GPU summaries. No Powerstat installed or running is required.
- QML root and expanded dashboard instantiate using the native extension. An offscreen Qt Quick window renders the dashboard with actual collector readings; screenshot was inspected for layout, unavailable-state wording and text wrapping.
- Installed package loads in `plasmawindowed` using the real Plasma runtime with the offscreen platform. Timeout terminates this smoke-test window deliberately.
- Staged initial installation, repeated upgrade, uninstall that preserves history, and explicit `--delete-data` uninstall pass without touching real usage history.
- Service startup initially exposed a quoted WorkingDirectory error. Corrected installer path escaping; actual user service startup then passed.

Commands:

```sh
python3 -m unittest discover -s tests -v
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build -j2
python3 scripts/install.py --prefix /tmp/energytlk-test-home
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  build/energytlk-qml-smoke \
  /tmp/energytlk-test-home/.local/share/plasma/plasmoids/org.energytlk.monitor/contents/ui/main.qml \
  /tmp/energytlk-dashboard.png
```

The standalone smoke harness supplies KDE localization context. Plasma supplies that context in normal use. Optional smoke-target development dependency: KI18n. Installer sets BUILD_TESTING=OFF.

Still requiring real-world validation: physical suspend/resume/reboot on this computer; an actual readable CPU package counter; AMD/Intel discrete hardware beyond sysfs fixtures; hot removal/driver reset on physical GPUs; compatibility with a specific independently managed Powerstat log (none was supplied); interactive high-DPI panel placement, theme switching and keyboard navigation. Simulated clock and fixture tests cover those accounting/error paths but do not establish physical hardware compatibility.

CPU permissions were not changed, and no privileged daemon, root collector, sensor permission rule, mount change or Powerstat service was installed.

## Dashboard and 30-day graph update

- Overview now has summary cards, a clearer live status and a rolling 30-day stacked CPU/GPU graph; History includes a Last 30 days preset.
- Calendar buckets preserve missing days, measured zero remains distinct from missing readings, and per-day details include costs and quality labels.
- Qt Quick tests: four graph logic tests pass (six QtTest entries including setup/cleanup): 30-day boundaries across DST, missing days, multiple GPU/CPU aggregation, source qualities, zero values, leap day and invalid ranges. All 27 collector tests still pass.
- Expanded dashboard rendered offscreen with live data and inspected for layout.

## Readability and visual refresh

- Added theme-aware surfaces, larger live power, responsive metric cards, clearer sensor status, a segmented navigation bar, and grouped settings with larger form controls.
- Small energy totals and graphs use Wh; larger totals use kWh. Tiny nonzero costs show < 0.001 instead of rounding to zero.
- Chart labels use a readable scale; keyboard arrow navigation complements pointer/touch day selection.
- QML dashboard, History and Settings instantiated and rendered offscreen; normal (760 px) and narrow (360 px) overview layouts were inspected. All 27 collector tests and four graph tests (six QtTest entries) pass. Theme colors remain driven by KDE; physical dark-theme/high-DPI switching still needs interactive validation.

## CPU activation and independent Powerstat setup

- Overview shows Activate when no CPU measurement is available. Popup explains the separate administrator-managed logger, provides a copyable terminal setup command and connects only a fresh readable exported log without overwriting other settings.
- Powerstat 0.04.05 is now present on the host; its help confirms -R/-D/-d modes. Previous absence was the observation at the initial inspection. No privileged Powerstat logger was installed or started by the app or these checks.
- Optional system-service bundle includes root-owned isolated Python adapter, fixed Powerstat command, package-only domain extraction, line-buffered output, full UTC receipt timestamps, stale-line rejection, boot enablement, restart handling and bounded atomic snapshots.
- Six additional tests pass (33 Python tests total), covering domain overlap prevention, invalid/stale output, bounded export/import, logger-session changes and service command configuration. Existing graph tests pass. Shell syntax, Python compilation, Qt extension build, QML popup instantiation and service-unit syntax checks pass.
- Activation popup rendered offscreen and inspected. The independent privileged service still needs the user's manual installation and a real RAPL-reading validation; fixture tests do not establish that the host Powerstat driver supports every package.

## Automatic CPU connection

- Kept the included timestamp adapter; removed the manual Connect CPU log action and native settings-writing method.
- Collector now discovers the documented adapter output on every sample when no custom log path is configured. It still validates timestamps/freshness, prefers direct readable CPU package sensors, preserves explicit paths, and excludes real imports from demo mode.
- Setup popup checks the Powerstat executable, running Powerstat processes and log freshness every two seconds. Copy buttons cover missing-package installation (Manjaro/Pamac-AUR, Ubuntu/Debian/APT), setup/autostart, status and stop. Merely finding a process does not claim measurements are available.
- 35 Python tests pass, including an actual collector-loop test importing CPU watts with empty configuration and no connection/settings write, plus path-discovery precedence tests. Qt plugin builds; popup renders successfully. The optional privileged service remains a user-run terminal setup.

## Standalone window and home log folder (supersedes prior adapter setup)

- Installer creates an application-menu launcher and `~/.vibeenergy/logs/powerstat.log` owned by the desktop user. No widget placement is required. Existing nonempty logs and their modification times are preserved during upgrade.
- Removed the privileged Python adapter and setup bundle. Linux commands in the popup run distro-installed Powerstat with stdbuf/Bash/date/printf and write timestamp-prefixed output to the home log. No app code is copied into system directories. Systemd setup still requires the user to run the displayed commands themselves.
- The app's own unprivileged parser scans only the dedicated log folder, selects the newest nonempty log, validates full dates, parses domain headers and sums only package columns. It skips summaries, rejects duplicate domains and stale/future samples, and observes service restart markers.
- All 35 Python tests pass. The generated timestamp pipeline was exercised with fixture Powerstat output and successfully imported by the real app reader. CMake and QML popup smoke checks pass. Physical privileged Powerstat recording remains a manual setup step, not a verified action performed by the app.

## Powerstat startup repair

Actual system-service logs exposed two generated-unit bugs: AF_UNIX-only sandboxing returned EAFNOSUPPORT for Powerstat's Netlink socket, and unescaped printf %s was expanded by systemd. Fixed literal percent escaping in generated ExecStart and used a socket syscall filter returning EPROTONOSUPPORT, which upstream Powerstat explicitly treats as an optional process-statistics fallback. No capabilities are granted. Existing units are detected and offered a short repair command. Generated-unit timestamp regression checks now emulate percent and dollar expansion; syntax verifies successfully. Automatic root repair with expanded capabilities was rejected by approval review and was not performed. The safer repair was approved but noninteractive sudo required the user's terminal password, so the installed system unit still awaits that manual repair.

## Direct Powerstat autostart

The autostart generator now uses a direct stdbuf/Powerstat ExecStart, with no sed repair branch, no Bash timestamp pipeline, and no privileged application code. The standard persistent unit restarts Powerstat and is enabled at boot by the user-pasted Linux command block. Plain Powerstat logs supply live watts only; absent calendar dates make CPU energy unknown. Two additional tests cover fresh/stale plain log reads and actual collector behavior proving live CPU watts do not create fabricated CPU energy.


## One-second daily logging

Powerstat temporary/cron commands now pipe one-second samples to an unprivileged recorder; the installer also prepares a matching optional system unit. Recorder transactions preserve local-day kWh, coverage and tariff-at-recording costs before daily raw reset or the 40 MiB Powerstat raw-file cap. SQLite raw rows keep only the current day; summaries are permanent. Tests cover midnight splitting, restart after days offline, size resets retaining a usable header, tariff changes, clock/restart gaps, and database-failure preservation. The collector avoids duplicate CPU integration for managed logs. Existing undated logs remain live-only, and existing recording jobs require the updated command.


## Collector-owned plain Powerstat accounting

Plain temporary/cron/service output is now consumed by the unprivileged collector. A SQLite cursor and CPU totals commit in the same transaction, with a trailing-byte signature detecting replaced/truncated output. Tests cover CPU plus GPU daily sums, collector restart without duplicate energy, midnight truncation retaining an open append writer and inode, three days offline, incomplete rows, database failure, old-recorder compatibility, source changes, and multi-batch ambiguous clock history. Only freshly observed clock rows acquire dates; offline ambiguity stays unknown. Only the default shared log is truncated. Cleanup requires the collector running, defers unread/partial output, and can leave a brief unknown interval at truncation. The prepared Powerstat service now runs plain Powerstat directly; no recorder/privilege-switching pipeline is needed in new commands.


## Normal / cosmetic Turbo appearance

Added restrained dark surfaces, semantic CPU/GPU/total accents, responsive sidebar navigation and a cosmetic five-second Turbo control. Effects fade for 650 ms and their Loader releases the animated Canvas at zero intensity. No new top-level windows, window flags, transparent margins, hardware commands or collection timers are involved. Native plasmawindowed hosting remains unchanged.

Validated with the Qt software/offscreen backend at 360, 480 and 1100 pixel widths, including History, Settings and CPU setup. QML tests verify normal mode has no effect renderer, cleanup releases it, and active effects do not intercept button clicks or alter button dimensions. Full-dashboard smoke checks verify automatic five-second expiry and manual cancellation both restore zero intensity, unload the renderer and preserve native window size. Effects are bounded by the current host window; beyond-frame plasma was deliberately not implemented because the host does not offer portable input-transparent margins across Wayland and X11. Physical desktop/compositor behavior remains a manual validation item.


## Reference-image layout refinement

Reorganized the overview into three semantic power cards, a real-sample live chart, compact monthly statistics, and a wider icon-navigation/electricity sidebar. Live chart samples are window-local (bounded to one hour); unavailable values remain null and measurement gaps break lines. History retains persistent daily reports. Added live-chart tests for safe empty scale, timestamp range filtering and preservation of unknown samples. The Turbo status line reserves fixed height so sidebar controls remain stationary when the effect ends. Backend collection and accounting code are unchanged.


## Cinematic Turbo and transparent edges (current implementation)

This supersedes the earlier inset-only effect. Added native Qt Quick scene-graph ribbon/glow geometry, travelling perimeter streams, a button corona, ignition wave, occasional arcs and particles. A single timeline controls exactly five seconds of active state plus a 750 ms fade. The segmented countdown reserves fixed layout space. Both foreground/background Loaders release their renderers at zero intensity. Reduced motion uses static lighting and a short fade, honoring KDE AnimationDurationFactor=0 and an explicit environment override.

The existing plasmawindowed host is retained. Native setup is guarded to avoid modifying a shared Plasma desktop/widget window. On supported Wayland hosts an alpha-capable surface and 32-DIP transparent margins use a rounded input region excluding empty margins. Maximized/fullscreen margins become zero. X11 stays inset: Qt's XCB setMask implementation uses a bounding shape, which would also clip outward rendering. No desktop-wide overlays, extra windows, compositor plugins, clock/power-limit commands or services were introduced.

Verified on the actual Wayland session using the OpenGL renderer: accelerated effects available, transparent alpha surface, 32-DIP mask exclusion, and zero margins when maximized. X11/XWayland OpenGL also passed the full effect/restore test using the inset fallback. Software and reduced-motion lifecycle tests pass. Native smoke checks verify renderer release and unchanged window/sidebar geometry after automatic expiry and cancellation. Breeze emits existing TextArea context-menu type warnings during native-platform smoke loading; effects render and lifecycle checks pass. Physical click-through to an underlying unrelated application and multi-monitor moves remain manual checks.

Primary API references: [Qt QWindow mask semantics](https://doc.qt.io/qt-6/qwindow.html#setMask), [Qt XCB bounding-mask implementation](https://github.com/qt/qtbase/blob/dev/src/plugins/platforms/xcb/qxcbwindow.cpp), [PlasmaWindowedView host](https://github.com/KDE/plasma-workspace/blob/master/plasma-windowed/plasmawindowedview.cpp).

Installed-host verification reported `PlasmaWindowedView`, Wayland, alpha size 8, margin 32 and `cornerAcceptsInput=false`. The five-second accelerated smoke run counted 313 frameSwapped callbacks (approximately 60 updates/second; not an isolated benchmark), verified the mask, and returned to zero intensity with released renderers and unchanged window/sidebar geometry. The current suite passes 59 backend tests and 18 QML checks.


## Application-owned window frame

Removed the native system frame only for the standalone PlasmaWindowedView host. Header controls provide minimize, maximize/restore and close; the header starts native system moves and inside-edge handles start native system resizing. Desktop widget windows are excluded. Wayland smoke verification confirms FramelessWindowHint, visible controls and the existing transparent margin/input mask. Native drag/resize gesture behavior still warrants manual desktop verification.

## Portable AppImage (2026-11-02)

- Built the current app and bundled Python/Qt/KDE runtime in Debian 13 (x86-64, glibc 2.41 baseline). Build scripts are in `packaging/appimage/`.
- Checked normal AppImage mounting outside the restricted sandbox and extract-and-run fallback; the bundled Python collector completed two simulated samples and produced isolated state/history files.
- Tested complete first-launch preparation in an isolated HOME/XDG runtime directory. It created the shared Powerstat log, user collector unit, optional Powerstat unit, and live collector state without sudo.
- The bundled Plasma launcher loaded the current QML and SVG icons in an offscreen private D-Bus session and opened on the real Wayland desktop with OpenGL QRhi initialized. Validation windows were stopped with an intentional timeout.
- Verified Qt/Plasma libraries resolve from the bundled AppDir. Host graphics-driver libraries and the host C/C++ runtime remain external for driver compatibility. System portal/empty-containment messages are emitted by Plasma during isolated launch.
- Existing 59 Python tests, 20 QML checks, and focused number-editing/dropdown checks passed. Hardware measurements on an AMD PC and cross-distribution launch still need testing on those systems. Older glibc distributions are not supported by this build.

### AppImage collector startup repair

The initial AppImage's real user service failed with exit 127 because `NoNewPrivileges=yes` prevented its FUSE mounting path. The service and no-user-bus fallback now invoke `--appimage-extract-and-run --collector`. Shell wrappers for host tools also failed before clearing bundled-library paths (`/bin/sh: undefined symbol: rl_print_keybinding`). Replaced them with a statically linked environment-cleaning launcher and verified the packaged launcher retrieves real NVIDIA GPU watts. Added regression tests for the generated service, quoting, and fallback command. All 61 Python tests pass.

### Settings uninstall controls

Added a confirmed rootless uninstall action, previewable/copyable app-removal commands, and separate sudo commands for removing the optional Powerstat system service. Staged uninstall tests verify that history, settings, logs, the AppImage, and unrelated desktop entries are preserved; failed service-stop handling removes no files. Both confirmation and cancellation were tested using a fake backend, without uninstalling the actual app. All 63 Python tests and 20 existing QML checks passed. The packaged Settings UI loaded without QML type/reference errors.

### CPU activation and authenticated autostart

The unavailable CPU card now uses a prominent blue Activate CPU button. CPU setup and Settings include an Enable CPU autostart action with confirmation and Polkit authentication. The privileged shell receives a fixed, generated Powerstat-only unit through stdin; no application Python is run as root. Host process environment paths are cleared before launching Polkit. Copy/view commands remain available.

Compiled the native plugin, passed all 20 existing QML checks, and tested authorization success and cancellation with a fake pkexec executable (no real privileged commands executed). Inspected the generated fixed command/unit, verified escaping for spaces and percent specifiers, and validated the unit with systemd-analyze. Packaged UI loading was checked without requesting administrator authorization.

### Turbo AppImage runtime-path repair

Logs contained failed dynamic loads of TurboGpuLayer/TurboAudio from an earlier temporary AppImage mount. Disabled compiled QML disk-cache reuse in AppRun so each launch resolves components from its current runtime. Added opt-in runtime diagnostics/captures under the existing Turbo debug mechanism; no diagnostic timer is created in normal launches.

Verified the actual AppImage window with the user's always-on setting: GPU renderer Ready, reduced motion false, animation time advancing beyond 17 seconds, and distinct electrical geometry in top-border captures at two and four seconds (independent of sensor/chart changes). All 20 existing QML checks passed. Temporary diagnostics are removed from the normal launch environment.

### Lightning preserved with brighter edge geometry

The brighter edge ribbons pushed the custom plasma node past Qt's merged-geometry batching range, hiding later lightning geometry. Set the vertex-color material's NoBatching flag so the node is drawn directly. A fixed GPU frame had zero bright interior bolt pixels before the fix and visible lightning/sparks afterward. Added the optional native `energytlk-plasma-smoke` target (BUILD_TESTING=ON), which captures three strike phases and checks interior lightning pixels; the Wayland GPU check passed with 2504 bright pixels. It reports skip status 77 when no GPU renderer is available. All 20 QML checks also passed. No AppImage rebuild was performed.

### Missing NVIDIA utility help

Added an Install nvidia-smi help action on the Overview GPU card and affected Sensors entries. It shares the CPU card's activation-button component and opens a dark setup popup with matching-driver guidance, an official guide link, and a previewable copy/check command. It appears only for detected NVIDIA devices reporting a missing utility, not for AMD or unrelated driver failures. The AppImage host-tool launcher is no longer mistaken for an installed host utility. All 67 Python tests and 33 QML checks passed. Overview/popup screenshots were rendered using explicitly simulated missing-utility state; installed drivers/tools were unchanged. AppImage was not rebuilt.

### AppImage refresh after UI and asset organization

Rebuilt from the current source, including the organized audio assets, latest About/support controls, dropdown interaction fixes, NVIDIA utility help, window-size preferences, volume default, shared measurement footer, and unbatched plasma renderer. All 67 Python tests and 33 QML checks passed. The rebuilt image's collector completed isolated simulated samples, its current UI opened on Wayland without QML type/reference errors, and the real GPU lightning check against its bundled Qt runtime passed with 5543 bright interior pixels. Updated release/ and website/downloads/ copies and verified both SHA-256 checksums.


Single-window launcher regression (private session bus, no desktop changes):

```sh
dbus-run-session -- /tmp/vibeenergy-command-build/energytlk-instance-smoke /tmp/vibeenergy-command-build/energytlk-instance
```

The launcher test covers rapid startup requests, repeat activation, and a fresh launch after exit. `ENERGYTLK_SMOKE_VERIFY_SINGLE_INSTANCE=1` with `VIBEENERGY_TEST_SINGLE_INSTANCE=1`, `VIBEENERGY_TEST_ALPHA=1`, and a private session bus also checks minimized-window restoration and duplicate-window rejection. `ENERGYTLK_SMOKE_VERIFY_ICON=1` checks the VibeEnergy window icon and desktop identity.


### Splash placement across monitors (2026-11-03)

Wayland splash placement now lets the compositor select the output at surface mapping instead of pinning a queried active output. Artwork and the full-screen lightning canvas follow the actual content dimensions, removing the separately cached monitor size. X11 retains cursor-screen selection and follows screen geometry changes. Splash diagnostics now record the actual mapped artwork center.

Native build passed. A live Wayland capture verified a 2560×1440 surface with artwork centered at (1280, 720) and wordmark within one pixel of that center. This checks compositor-configured dimensions; interactive launching from each monitor still needs user verification.

The packaged-runtime check found the layer-shell Wayland plugin missing. Added Debian layer-shell-qt to the build dependencies and a packaging check that rejects an absent plugin. An initial rebuild completed before this discovery; the follow-up build was stopped at the user’s request. The corrected package awaits a manual rebuild.


### Separate currency histories (2026-11-03)

Added transactional schema-v3 migration and currency-keyed permanent daily energy/cost summaries. Legacy rows keep their original currency and stored costs; old unpriced summaries receive a one-time valuation at the previous tariff. Settings saves preserve legacy unit/tariff metadata, including when collection is stopped. Both CPU recording paths and the main collector pass the recording currency. Existing branches resume without conversion or deletion.

Saving a changed currency opens a start/continue confirmation; cancellation writes nothing. History supports all/single currency filters. Overview, range summaries, daily rows and graph selections list different currencies separately, while energy remains additive. Sidebar electricity information stays read-only.

Validation: native plugin built; 54 focused Python tests and all 40 QML checks passed, including migration, same-day switch/resume, CPU recorder/importer, transaction rollback, confirmation cancellation and grouped costs. An isolated simulated collector completed EUR → USD → EUR while preserving both histories. Broader Python discovery encountered two existing AppImage fixture errors caused by a missing mounted/vibeenergy.svg test asset. No AppImage rebuild or live-history migration was performed for this change.


### KDE taskbar identity repair (2026-11-03)

The Plasma host maps its Wayland surface before applet loading, so setting QGuiApplication.desktopFileName later did not change the compositor app ID. Added a guarded one-time startup remap after assigning the VibeEnergy identity and aligned generated/bundled desktop StartupWMClass values. Native build passed. An isolated real Wayland preview verified the replacement surface sends set_app_id("vibeenergy") with its icon, replacing the initial org.kde.plasmawindowed surface. No AppImage rebuild was performed.


### KDE system tray (2026-11-03)

Added a standalone-only KStatusNotifierItem with the bolt icon and Show, Hide, and Quit actions. Closing hides to an available KDE tray; activation through the tray or launcher restores the same window. Quit exits the interface while background recording remains independent. Uninstall uses explicit quit rather than hiding. Without a tray host, the existing close-to-exit behavior remains. Intercepting the host Hide event preserves the applet, which PlasmaWindowedView would otherwise delete; this also protects the startup identity remap. Added the StatusNotifierItem build dependency to CMake and the packaging image.

Native plugin build and six AppRun launcher tests passed. A private session-bus test with a mock KDE tray host verified registration, retained GUI after close, successful tray activation, and launcher reuse. No AppImage was rebuilt.


### Default background recording and tray shutdown (2026-11-03)

Removed Start/Stop/Restart collector controls from Settings; recording starts when opening the app, and Settings retains login-autostart controls. Disabling autostart no longer uses --now, preserving current recording. Tray Quit now stops the user service and any portable fallback collector before exiting. The stop helper identifies a same-user Python collector by its open lock inode, supports older empty lock files, sends SIGTERM for graceful history/state flushing, and refuses to kill unidentified lock owners. Powerstat remains separate. Failures keep the interface open and report a tray notification.

Three targeted collector shutdown tests and all 42 QML checks passed; native plugin compiled. No live user recording was stopped during validation and no AppImage was rebuilt.


### Dependent-process shutdown and missing-mount recovery (2026-11-03)

The reported GUI still owned activation after its AppImage mount had disappeared, making the mounted Python helper unavailable. Embedded the standalone stop helper in both GUI plugin and launcher; host Python runs it with bundled loader paths removed, with a fresh AppImage helper invocation as fallback on hosts without Python. Launcher termination forwards to its owned child process group, with parent-death handling for runtime/launcher loss. AppRun cleanup stops the collector through the retained image path, and externally terminating the splash aborts the dependent GUI. A tray-side collector-lock monitor closes the GUI if its collector is killed. GUI/session exit also attempts collector shutdown. Powerstat remains independently managed.

Validation: real tray Quit succeeded with an intentionally missing mount and isolated collector; SIGTERM to GUI stopped collector; SIGKILL to collector closed GUI; private-bus launcher test covered termination and reopening. Seven AppRun tests (including killed splash), three collector-stop tests, and three lifecycle tests passed. Native targets built. No AppImage rebuild was performed.


### Confirmed logs and history reset (2026-11-03)

Added a Settings reset action with destructive confirmation, busy state, results, and a Powerstat stop reminder. Clears real/demo SQLite recordings, all currencies, raw application logs, and the configured CPU log; settings and lock files remain. Rejects log symlinks before modifying history and truncates logs in place. Collectors pause and restart if previously active; the GUI dependency watcher is suspended during reset. Reset generations clear cached live graph points.

Three Python reset tests and all 49 QML checks passed. An isolated running demo collector reset verified old history removal, a fresh recording session, and preserved reset generation. Native plugin built and QML/shell syntax checks passed. No real user history was cleared and no AppImage rebuild was performed.


### Pre-publication verification (2026-11-03)

Passed 86 Python tests and 49 QML checks under KDE desktop styling. All native targets built. Private-bus launcher smoke passed rapid/repeated activation, fresh launch after close, terminating the launcher with child cleanup, and subsequent reopening. Real GPU regression detected 2303 bright interior lightning pixels. Zero-volume audio smoke passed PCM mixing, simultaneous outputs, power-off release, and immediate disable.

Headless Chromium checks passed at desktop and mobile widths: no horizontal overflow, Turbo hero loaded, all three setup cards had equal heights, glow animation ran normally and stopped under reduced-motion emulation. Website anchors and required local assets passed; optional preview.mp4 remains absent with the existing placeholder. Desktop entry validation, shell syntax, and git diff whitespace checks passed. Release and website AppImage SHA-256 checksums matched their files. The existing release AppImage passed isolated simulated collector sampling and complete history reset with temporary HOME/XDG directories.

Fixed the two stale AppImage test fixtures by providing their required icon asset. Fixed a SQLite connection leak on startup validation failure exposed by ResourceWarning. The existing AppImage predates that final cleanup-only source fix; no AppImage rebuild or publication was performed.


### Native shutdown replaces executable helpers (2026-11-03)

Removed executable/Python helpers from GUI and launcher collector shutdown. Native code requests systemd StopUnit and identifies same-user fallback collectors by their open lock inode before SIGTERM. Tray Quit exits even when recording shutdown cannot be confirmed, instead of reactivating a broken shell. Missing AppImage mounts trigger automatic shutdown; a vanished window also initiates cleanup.

Added native collector-stop smoke coverage with missing mount/Python environment/PATH, graceful snapshot flushing, an already-stopped collector, and preservation of an unrelated lock owner. This test passed on a private bus. Mount-loss integration also passed: GUI and isolated collector exited. Launcher regression passed termination, child cleanup, and fresh relaunch. No AppImage rebuild was performed; prior packaged-binary normal Quit also passed but did not reproduce the reported failure.


### Shutdown recheck and Plasma Store companion (2026-11-03)

Reran native shutdown without executable helpers, mount-loss GUI/collector shutdown, actual tray Quit, and launcher termination/relaunch checks successfully. Full regression suite passed 86 Python tests and 54 QML checks after adding companion metric tests. No AppImage was rebuilt.

Prepared a distinct pure-QML, read-only companion (org.energytlk.monitor.companion) because the full widget requires its C++ EnergyLocal plugin, which cannot be shipped as a compile-required KDE Store widget. Companion reads the local VibeEnergy collector snapshot through a fixed executable-engine cat command, displays live component watts and period energy/current-currency costs, and reports offline/setup guidance. It requires the separately installed app/collector. The 16.4 KiB .plasmoid contains no native binaries or Python backend. Archive/checksum verified; kpackagetool6 install and upgrade passed under temporary HOME/XDG directories. Online and offline views rendered successfully, with upload description, instructions and sample-data screenshots included in release/kde-store. No upload/publication was performed.


### Companion installation-aware notices, version 1.0.3 (2026-11-03)

The companion now checks the VibeEnergy desktop entry in user/system XDG application directories separately from recording freshness. Fresh readings hide the notice; registered app with stale/missing data prompts opening VibeEnergy; an absent registration shows the installation requirement. The same state drives compact text and tooltips. Added probe parsing, availability, stale/future timestamp and missing-interval checks. All 57 QML checks passed, and all three status views rendered against isolated fixtures. Rebuilt the .plasmoid/checksum/upload files and upgraded only the installed companion package to 1.0.3. No Plasma refresh/restart, AppImage rebuild, or publication was performed.


### Unified five-second widget status, version 1.0.4 (2026-11-03)

Removed the app-installation probe. Recording and warning now share five-second freshness; warnings require five seconds without a changed collector timestamp, with startup grace and automatic recovery. Reading the same file does not reset the timeout. Polling is once per second. Native widget-status smoke loaded the actual root QML and verified grace, timeout, and recovery after a fresh snapshot; seven companion QML checks passed. Updated the widget About website to https://vibeenergy.techtoapes.com/ and confirmed the app About link. Rebuilt and checksum-validated the .plasmoid/upload kit. No Plasma refresh/restart, installed-widget modification, AppImage rebuild, or publication was performed for this update.

### Turbo button and companion synchronization

Added an integration smoke test that loads the actual app and companion together, clicks the app Turbo button, toggles the saved always-on setting, cancels continuous mode with the button, restarts a burst, hides the app, and verifies expiry. Passed with sound disabled and with sound enabled through the desktop audio service. Companion metric and Turbo lifecycle checks passed (15 checks). App now publishes start/stop before audio work, explicitly stops when the button disables continuous mode, and preserves a widget burst while pausing a hidden app surface. The desktop launcher was found pointing to a separate `vibeenergypro` AppImage whose loaded QML did not contain `publishTurbo`; the updated AppImage is built in this checkout and refreshed in website downloads.
