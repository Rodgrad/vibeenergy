# vibeenergy

Developed by Luka Beslic with AI assistance from GPT-6.1. [GitHub repository](https://github.com/Rodgrad/vibeenergy) · [Luka Beslic](https://github.com/Rodgrad).

Existing installations keep the internal `energytlk` service, widget ID and XDG directories so saved history and installed widgets continue to work.

A standalone KDE desktop app, optional Plasma 6 widget, and independent unprivileged Python collector for local CPU/GPU energy measurements. No network access, telemetry, root execution, permission changes, or storage/mount management. It never runs Powerstat itself; CPU setup can enable the separate Powerstat service through system authorization. Missing utilities and unreadable sensors appear as diagnostics, and the other components keep working.

VibeEnergy uses one desktop window per session. Launching it again raises the existing window without replaying the splash. The collector remains independent.

## Install and launch

Requires Python 3.10+, Qt 6 Core/QML/Multimedia and Layer Shell Qt and KDE WindowSystem and StatusNotifierItem development files, CMake, a C++17 compiler, and Plasma 6 with Kirigami and Qt Quick Controls. On Manjaro these are typically supplied by python, cmake, gcc, qt6-base, qt6-declarative, qt6-multimedia, layer-shell-qt, kwindowsystem, kstatusnotifieritem, kirigami, plasma-workspace and libplasma. NVIDIA polling additionally uses the driver-provided nvidia-smi. Powerstat is optional. No Python pip dependencies. The optional offscreen smoke-test target (`-DBUILD_TESTING=ON`) also requires KI18n development files; the installer builds without that target.

From this source directory, as your ordinary desktop user:

```sh
python3 scripts/install.py --autostart
```

This builds the local Qt extension, installs under XDG user directories, starts the collector, and enables it at login. Open **vibeenergy** from your application menu. It runs in its own window; adding a widget is optional. The installer creates `~/.vibeenergy/logs/`, an empty `powerstat.log`, and its recording lock file. Temporary, cron, and existing Powerstat service recording all use this same log path. The widget also requests collector startup when loaded. The collector starts and manages its own persistent nvidia-smi polling process; you do not need a terminal or a separately launched nvidia-smi. Failed driver access is retried automatically. To install without enabling login startup, omit `--autostart`. Settings provides Enable/Disable autostart buttons; disabling also stops the service. Removing the widget does not stop collection.

```sh
systemctl --user start energytlk.service
systemctl --user stop energytlk.service
systemctl --user restart energytlk.service
systemctl --user status energytlk.service
journalctl --user -u energytlk.service -n 100
systemctl --user enable --now energytlk.service
systemctl --user disable --now energytlk.service
```

No systemd? Run `python3 -m energytlk` from this directory (or installed `~/.local/share/energytlk/app`) and use your desktop's autostart mechanism with that working directory. Widget service buttons require systemd; readings still work with the manually launched collector. The collector takes an advisory file lock; multiple widgets or duplicate collector launches cannot duplicate accounting.

The overview follows a three-card CPU/GPU/total layout, a live wattage graph with a 5/15/60-minute range selector, compact Today/This month/All time summaries, and sidebar navigation/electricity information. The live graph and GPU sparkline use actual samples observed by the current window; they do not fabricate older history. Persistent daily reports remain in History. The sidebar displays the saved price and currency; changes are made in Settings.

The dashboard uses a restrained charcoal palette with CPU cyan, GPU green and total-power purple accents. The right sidebar provides a cosmetic **TURBO BOOST** button (a compact header button on narrow windows). It plays a five-second electrical effect with a segmented countdown, then fades out over 750 ms; it never changes sampling, values, prices or hardware settings. The effects renderer is unloaded in normal mode. On supported Wayland plasmawindowed hosts, the existing surface reserves 32 logical pixels of transparent edge space, with a rounded input mask excluding the margins. The margins stay constant across Turbo transitions and are removed when maximized/fullscreen. X11 and unsupported hosts use an inset effect because Qt's X11 window mask also clips rendering. No separate overlay windows are created. KDE's disabled-animation preference (or `VIBEENERGY_REDUCED_MOTION=1`) selects a static glow. Native Qt Quick scene-graph geometry renders the accelerated ribbons; software renderers use a bounded fallback. Normal mode unloads both effect layers.

## Portable AppImage (recommended for testing on another PC)

Download or copy `release/VibeEnergy-x86_64.AppImage`, enable **Allow executing file as program** in its file properties, and double-click it. No source installer, Git, compiler, or separate Python/Qt installation is needed. You can also launch it from a terminal:

```sh
chmod +x VibeEnergy-x86_64.AppImage
./VibeEnergy-x86_64.AppImage
```

This build is for **x86-64 Linux with glibc 2.41 or newer**, including Debian 13 and recent compatible Ubuntu releases. Older distributions need a build against an older runtime. Plasma is the primary supported desktop; graphics drivers remain provided by the host. The AppImage bundles Python, Qt/KDE modules, fonts, and sounds. If FUSE mounting is unavailable, use `./VibeEnergy-x86_64.AppImage --appimage-extract-and-run`.

First launch prepares user-owned logs/settings and the background collector. Keep the AppImage in a stable location; if you move it, open it again to refresh the collector service path. Autostart remains controlled from Settings. Supported dedicated AMD/NVIDIA GPU monitoring needs no Powerstat setup; CPU recording is configured separately. The image never runs Powerstat or requests sudo.

Rebuild with one command: `sh builders/build-appimage.sh`. This also refreshes the website download. A SHA-256 checksum accompanies the file. Build instructions and runtime details are in [packaging/appimage/README.md](packaging/appimage/README.md).

## Single-file standalone installer

Build a transferable installer from this checkout:

```sh
python3 builders/package_standalone.py
```

Copy `release/vibeenergy-1.0.0-standalone.run` to the other Linux machine, then run as your regular user:

```sh
sh vibeenergy-1.0.0-standalone.run --autostart
```

This is a **source-based installer**, not a dependency-bundled executable. It builds against the target machine's Qt libraries and requires the same Plasma 6, Python, Qt development, CMake, and compiler prerequisites as installation from Git. Qt Multimedia is needed for Turbo sounds. No Git checkout or network download is needed by the installer itself. Open VibeEnergy from the application menu after installation. GPU readings require supported hardware and a readable driver power sensor; Powerstat is separate CPU setup.

Use `--help` for options, `--check` to check archive readability, or `--extract NEW_DIRECTORY` to inspect the bundled source. A SHA-256 checksum is generated alongside the installer. The package excludes chat exports, Git history, build outputs, and local settings/logs.

## Sensors and scope

* CPU: discovers Intel/AMD powercap **package** energy counters. Existing read permissions are required. RAPL subdomains (cores, DRAM, uncore, integrated GPU) are excluded to prevent overlap. Package counters can include integrated graphics and other package components. Some AMD systems expose no unprivileged powercap sensor; these show unavailable.
* NVIDIA: one persistent `nvidia-smi --query-gpu=pci.bus_id,name,power.draw --format=csv,noheader,nounits --loop-ms=...` process for all boards. This is board power, not per-process attribution. Missing executable, N/A, stale output, suspended/disconnected hardware and failed drivers do not stop CPU accounting. Polling is restarted with backoff.
* Other DRM GPUs: detects hwmon power1_average or power1_input (microwatts converted to watts). No invented wattage. Intel GPUs and AMD devices with absent/small dedicated VRAM are conservatively excluded because they may overlap CPU/SoC energy. This heuristic can exclude discrete Intel and small-VRAM AMD boards; diagnostics explain the exclusion. Unsupported sensor layouts remain unavailable.
* No usage-percentage power estimate is substituted. Demo readings alone are labeled estimated and stored separately.

These readings exclude some motherboard/RAM/storage/fans, PSU conversion losses and monitors. CPU+GPU is **not whole-PC wall consumption**. Use a plug-in watt meter for that.

## CPU monitoring: Powerstat → home log → app

**AMD compatibility:** Powerstat can measure CPU power on supported AMD systems, including Ryzen and EPYC processors, when the Linux kernel exposes compatible RAPL energy counters. Support depends on the CPU and kernel; it is not guaranteed for every AMD machine. Test availability with:

```sh
sudo powerstat -R -D -d 0 1 5
```

If Powerstat reports no RAPL domains, this recording method cannot provide CPU measurements. GPU monitoring can still work independently. See the [Powerstat project](https://github.com/ColinIanKing/powerstat) for details.

On supported AMD CPU/APU systems, Powerstat's package-energy reading may include integrated-GPU consumption, depending on the processor's counters. VibeEnergy displays that combined package reading under **CPU**; it does not split it into separate CPU and integrated-GPU values. Integrated AMD GPUs are excluded from separate GPU accounting to avoid double counting. Dedicated AMD GPUs are measured independently through readable DRM/hwmon power sensors and do not require Powerstat.


The app installer creates:

```text
~/.vibeenergy/
└── logs/
    └── powerstat.log
```

The unprivileged app reader automatically looks for `.log` files in this folder and prefers the shared `powerstat.log`; if it is empty or absent, it falls back to the newest nonempty log. It does not scan the rest of your home directory or follow links outside the log folder. You can still choose an explicit custom log in Settings.

When CPU counters are restricted, click the blue **Activate CPU** button. The popup checks whether Powerstat is installed and running and whether a recent log exists. It provides copy buttons for:

- Installing Powerstat using Ubuntu/Debian APT or Manjaro Pamac/AUR.
- Starting Powerstat temporarily in a terminal.
- Enabling Powerstat as a systemd service that starts at boot.
- Checking or stopping that service.

The recommended service section also offers **Enable CPU autostart**. Confirm the action, then authorize it through the system’s Polkit dialog. The app sends a fixed Powerstat unit to standard system tools, enabling recording immediately and at boot; VibeEnergy and its Python collector remain unprivileged. Your password is handled by the system authentication agent, never by the app. The copy/view command remains available, including when Polkit is unavailable. Use only one Powerstat recording method at a time.

Powerstat is the only process requiring administrator privileges. The temporary command runs Powerstat once per second, restarts it every 12 hours, and appends plain output using `tee -a`. Cron and the installer-prepared service append the same output to `~/.vibeenergy/logs/powerstat.log`. No application code runs as root. The standalone installer prepares the log folder/files and permits the unprivileged collector to clean the shared log.

The **collector handles CPU and GPU daily accounting**. It processes each new CPU sample and commits daily energy, recorded costs and the log read cursor in one SQLite transaction. A restart cannot replay already committed samples. Fresh clock-only samples observed while collecting receive the current local date/UTC offset; ambiguous offline history is not reconstructed. Gaps, restarts and non-monotonic times do not create invented energy. Older recorder-managed logs remain supported without counting their totals twice.

At a new local day, or at the 40 MiB managed Powerstat raw threshold, the collector clears consumed raw output **in place**, retaining the header and the same inode so existing `tee`/cron/service writers continue. It defers cleanup if unread or incomplete output remains. Cleanup requires the collector running; the file can grow while it is stopped. Cleanup and source transitions may leave short unknown measurement gaps. Only the shared default log is cleaned automatically; explicit external logs are read-only. CPU/GPU SQLite raw samples also keep only the current day; permanent daily kWh/cost summaries are combined in History's selected-range totals. The raw threshold does not cap SQLite or system journals.

Every copy button has **View command**. For cron, run the block from **Copy cron autostart** once. It preserves existing jobs, adds the boot entry directly and avoids exact duplicate entries. Cron must be installed/enabled; recording starts at the next boot. No Python, application helper, privilege-switching tool or cleanup script is needed in the cron entry. Use only one Powerstat recording method, and remove older cron entries before switching.

The standalone installer prepares the optional system service; its service runner activates that file and restarts Powerstat. Existing recorder-based services require running the updated service runner to adopt plain-log recording. Existing plain temporary/cron commands work directly with the collector.

```sh
systemctl status vibeenergy-powerstat.service
journalctl -u vibeenergy-powerstat.service -n 30
sudo systemctl disable --now vibeenergy-powerstat.service
```

To remove that optional service, stop/disable it, remove `/etc/systemd/system/vibeenergy-powerstat.service`, then run `sudo systemctl daemon-reload`. App uninstall leaves this independently configured service and home log folder alone. Stop it before manually deleting or archiving its files.

## Accounting, reports and retention

Default sample interval: 10 seconds. Integration uses a trapezoid between consecutive valid power readings in one collector session. RAPL readings already average counter deltas over the preceding interval, so their interval energy uses a rectangle. Counter wrap uses max_energy_range_uj. Implausible power (>10 kW/package) is rejected. Very long intervals or multiple counter wraps cannot be reconstructed; they remain unmeasured.

Monotonic time determines elapsed integration. CLOCK_BOOTTIME detects suspend; wall-time jumps, missing readings, collector restarts, reboots, intervals over 2.5 times the configured period and source changes break continuity. Startup/warm-up intervals remain unknown. No energy is extrapolated over offline periods. Valid intervals are split at local midnight, including DST; timezone changes affect future accounting, without rewriting historical day labels. Tiny scheduling differences between wall and monotonic timestamps are tolerated (one second).

SQLite uses transactions, WAL, schema versioning, checkpoints and an integrity check at startup. Corruption stops collection without deleting the original database. Back up `energy.sqlite3` using SQLite's backup API or stop the collector before copying database files. Newer unsupported schemas fail explicitly.

Raw samples store source, status, quality, account flags and nullable derived Wh. Raw samples keep only the current local day and are pruned on startup and day changes. Daily per-device, per-quality energy and coverage aggregates remain permanently; the `monthly` SQL view preserves monthly totals. The overview shows Today, Last 30 days and All time cards, plus a rolling 30-day graph. Reports support today, last seven days, last 30 days, calendar month, calendar year, all time, and inclusive custom date ranges. Stacked daily CPU/GPU bars show recorded energy only; gray baseline marks identify days with no readings. Hover or tap a day for its energy, cost and source quality. The graph does not reconstruct days before collection began. Diagnostics shows measured seconds relative to collector observation time; this is not a claim of coverage while the collector was off. Unknown energy is not zero; every report is a partial component total. Estimates/imported records retain distinct quality labels in storage and diagnostics.

Tariff defaults to 0.177 EUR/kWh. Decimal dot/comma is accepted. Costs retain the tariff and currency used when recorded; changing price affects future recording. Fixed charges and tariff schedules are excluded.

To change currency, select it in Settings and click **Save changes**. Confirm **Save and start [currency] history**, or **Save and continue [currency] history** if that branch already exists. Selecting a currency or cancelling the confirmation does not save it. Enter the electricity price in the new currency before saving. Old history is preserved; no foreign-exchange conversion is applied.

Currency histories share one SQLite database, with separate daily energy and cost summaries per currency. In History, choose **All currencies** or a single currency. All-currency reports combine kWh while listing costs separately, never adding EUR and USD together. Today, weekly, monthly, yearly and custom date ranges use the selected histories. Returning to a previously used currency continues its branch.

On upgrade, existing summaries are assigned to the previously configured currency without changing stored costs or energy. Old summaries that lack a stored cost are valued once using the previous tariff. If currencies were already mixed before this upgrade, their original units cannot be recovered automatically. Restart the collector and any independent CPU recorder after upgrading so both use the new database schema.

## Files and architecture

* `energytlk/sensors.py`: discovery, RAPL/hwmon readers, persistent NVIDIA process.
* `energytlk/powerstat.py`: bounded, read-only external log parser.
* `energytlk/energy.py`: integration and local calendar boundaries.
* `energytlk/database.py`: samples, permanent summaries, migrations and retention.
* `energytlk/collector.py`: service loop, lock, suspend handling and atomic state output.
* `native/plugin.cpp`: Qt QML extension, reads local snapshot, validates/writes settings, invokes fixed systemctl argument lists asynchronously.
* `plasmoid/`: Plasma 6 PlasmoidItem compact/dashboard UI.
* `scripts/`: user-only installer and safe uninstaller.

Powerstat text logs live in `~/.vibeenergy/logs/`. Defaults: config `~/.config/energytlk/config.json`, database/app `~/.local/share/energytlk/`, snapshot/lock `~/.local/state/energytlk/`. XDG_CONFIG_HOME, XDG_DATA_HOME and XDG_STATE_HOME are honored. All paths are local; the app does not choose or alter manually mounted drives. Do not configure XDG roots on external storage if you want all data kept on the home filesystem.

The UI reads an atomic local JSON snapshot every two seconds; it does not own logging. Collector service uses NoNewPrivileges, a private temporary directory, read-only system/home paths except its data/state, and AF_UNIX-only networking. User namespace sandbox support depends on the host's systemd/kernel setup. NVIDIA device access is not hidden by PrivateDevices.

## Test / demo

```sh
python3 -m unittest discover -s tests -v
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software /usr/lib/qt6/bin/qmltestrunner -input tests/qml
cmake -S . -B build -DBUILD_TESTING=ON
cmake --build build -j2
python3 -m energytlk --simulate --interval 1
```

The command-line simulated collector is available for development testing. Its state/database live in `energytlk/demo` subdirectories and never mix with real history. It is independent of the real user service. Stop it with Ctrl+C.

For short smoke tests: `python3 -m energytlk --simulate --interval 1 --samples 3`. Stage and validate install/upgrade/uninstall without touching home or systemd: `python3 scripts/install.py --prefix /tmp/energytlk-test-home`, then `python3 scripts/uninstall.py --prefix /tmp/energytlk-test-home`.

## Uninstall

Open **Settings → Remove VibeEnergy → Uninstall…** and confirm. This stops/disables the user collector and removes its service and desktop integration, while preserving history, settings, raw CPU logs, and the AppImage file. After completion, the confirmation stays open until you choose **Close app**. Delete the AppImage afterward if desired; reopening it prepares the app again. If uninstall fails before removal, it preserves the app and attempts to restore recording. Losing the collector shows Offline instead of automatically closing the window.

Settings also provides **Copy uninstall commands (no sudo)** with a command preview. The separate **Copy Powerstat service removal (sudo)** option is only for the optional system-wide Powerstat service. Terminal/cron Powerstat jobs remain independently managed. No sudo is needed to uninstall VibeEnergy itself.


Close the app (and remove the optional widget if added), then:

```sh
python3 scripts/uninstall.py
```

Or use the installed copy: `python3 ~/.local/share/energytlk/app/uninstall.py`. This stops/disables the service and removes installed application/widget/service files. Database, settings and history remain. Only add `--delete-data` if you explicitly want all vibeenergy history and settings deleted. Stop any manually launched demo/fallback collector before uninstalling.

## Verified development host and limits

Inspected Manjaro host: Python 3.14.7, Qt 6.11.2, CMake/C++ compiler, kpackagetool6, Intel and NVIDIA DRM devices, package RAPL interfaces. CPU energy_uj read returned permission denied; nvidia-smi could not communicate with the driver; powerstat was absent. The sandbox cannot reach the systemd user bus. Outside the sandbox, verified Plasma 6.7.5, successful RTX 5070 Ti NVIDIA power readings, and an active, login-enabled user service with its own persistent nvidia-smi child. CPU RAPL remains permission denied. The installed widget loads offscreen and the expanded dashboard was rendered and inspected. See VALIDATION.md for actual tests and remaining desktop validation.

Plasma APIs follow KDE's [Plasma 6 porting guide](https://develop.kde.org/docs/plasma/widget/porting_kf6/). Sensor semantics follow the [Linux powercap documentation](https://www.kernel.org/doc/html/latest/power/powercap/powercap.html), [hwmon ABI](https://www.kernel.org/doc/Documentation/hwmon/sysfs-interface), and [NVIDIA SMI documentation](https://docs.nvidia.com/deploy/nvidia-smi/).

Settings → Appearance includes **Turbo Boost always on**. This saves an appearance-only preference, keeps effects active while the window is visible, and pauses them when minimized. Turn it off in Settings or click the active Turbo Boost button to return to ordinary five-second operation. Reduced motion remains supported; collection frequency and hardware settings are unaffected.

Turbo Boost audio is organized in `plasmoid/contents/sounds/`. It mixes `electricity-loop.wav` (a seamless loop derived from `electricity.mp3`), `zap.wav`, `power_on.wav`, and `poweroff.wav` into one shared audio output while Turbo is active. Buzz and lightning can overlap without creating a new output for each effect. The output closes after the power-off sound, or immediately when sounds are disabled. **Settings → Appearance → Turbo Boost lightning sounds** mutes it. Audio is loaded only while animated Turbo Boost is active and is stopped when disabled or minimized. The optional sound feature uses Qt Multimedia; all samples are bundled locally, with no downloads or network access.

## Website

The static site and its images are in [`website/`](website/README.md). Publish that folder’s contents. Place `preview.mp4` next to `website/index.html`; refresh the ignored `website/downloads/` files from `release/` when publishing a new AppImage.

The standalone app provides a KDE system tray bolt icon. Closing the window hides it to the tray; click the icon or launch VibeEnergy again to restore it. The tray menu offers Show, Hide, and Quit VibeEnergy. Quit VibeEnergy stops the app’s background collector before exiting, including portable fallback collectors; Powerstat remains a separate system service. Recording starts automatically when the app opens. Settings only controls recording at login; disabling autostart does not stop the current recording. If no system tray host is available, closing the window exits the interface normally.

Settings → Logs & history → Clear all logs & history requires confirmation. It clears all currencies and demo history, raw app logs, and the configured CPU log while preserving settings. The app collectors pause during clearing and restart if previously running. Stop Powerstat first to prevent recording sources from immediately creating new data.
