# Portable AppImage

Recommended: run `sh builders/build-appimage.sh` from the project root to build, verify, and refresh both release/download copies automatically. See [builders/README.md](../../builders/README.md).

The x86-64 AppImage bundles Python, Qt, KDE QML modules, Plasma Windowed, the
collector, UI, and sounds. It builds in Debian 13 to target glibc 2.41+ systems
(Debian 13, Ubuntu 25.04+, and compatible newer distributions). Users do not need
Git, compilers, Qt development packages, or a separate Python installation.
A graphical Linux session, compatible graphics drivers, and basic host libraries
including glibc remain system prerequisites. Plasma is the primary supported desktop.

```sh
docker build -t vibeenergy-appimage -f packaging/appimage/Dockerfile .
mkdir -p release/appimage-build
docker run --rm -v "$PWD:/src:ro" -v "$PWD/release/appimage-build:/out" \
  -e HOST_UID="$(id -u)" -e HOST_GID="$(id -g)" vibeenergy-appimage
```

The output is `release/appimage-build/VibeEnergy-x86_64.AppImage`, with a SHA-256
checksum. The official AppImage type-2 runtime is fetched during packaging;
its FUSE support is provided by that runtime. Where mounting is blocked, launch
with `--appimage-extract-and-run`. Mark the file executable in the file manager
before double-clicking. The runtime, build package list, dependency licenses,
and staged AppDir remain available for inspection.

First launch prepares only user-owned settings, logs, the optional Powerstat unit,
and a user collector service. The service calls this AppImage with `--appimage-extract-and-run --collector` so it works with `NoNewPrivileges=yes` without relying on a privileged FUSE mount helper.
Moving the image requires opening it again to refresh the service path. Autostart
is controlled by the app's existing settings. Without a working user systemd bus,
a separate collector invocation is used. Hardware permissions remain unchanged.
Powerstat is not bundled or executed: CPU setup stays explicit and separate.

`--window-only` launches the packaged window without preparing services for validation. `--collector --simulate --samples 2`
checks the bundled Python collector against isolated demonstration data.

Host tools (`nvidia-smi`, `systemctl`, `xdg-open`) use a statically linked trampoline that clears bundled-library paths before starting the host binary. A shell wrapper cannot do this reliably because the host shell may fail to load before it can clear the environment.

AppRun disables compiled QML disk-cache reuse because temporary AppImage mount URLs change across launches and updates. Turbo renderers and audio are loaded dynamically from the current runtime.
