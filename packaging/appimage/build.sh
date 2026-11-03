#!/bin/sh
# Run inside a Debian 13 container with the runtime/build packages installed.
set -eu
python3 /src/packaging/appimage/bundle.py
curl -fL --retry 3 https://github.com/AppImage/type2-runtime/releases/download/continuous/runtime-x86_64 -o /out/runtime-x86_64
mksquashfs /out/VibeEnergy.AppDir /out/vibeenergy.squashfs -root-owned -noappend -comp gzip -processors 2 >/out/squashfs.log
cat /out/runtime-x86_64 /out/vibeenergy.squashfs > /out/VibeEnergy-x86_64.AppImage
chmod 755 /out/VibeEnergy-x86_64.AppImage
cd /out
sha256sum VibeEnergy-x86_64.AppImage > VibeEnergy-x86_64.AppImage.sha256
chown -R "${HOST_UID:-1000}:${HOST_GID:-1000}" /out
