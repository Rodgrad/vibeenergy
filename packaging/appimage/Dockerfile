FROM debian:trixie-slim@sha256:f6b08b09a05725f9431502d3b5714f5c4576e82c1a84fa1debe0c24a7e0c3ec4
RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    make cmake g++ qt6-base-dev qt6-declarative-dev qt6-multimedia-dev libkf6i18n-dev libkf6windowsystem-dev libkf6statusnotifieritem-dev liblayershellqtinterface-dev layer-shell-qt plasma-workspace \
    qml6-module-qtquick-controls qml6-module-qtquick-layouts qml6-module-qtquick-window \
    qml6-module-qtqml-workerscript qml6-module-qtmultimedia qml6-module-org-kde-kirigami \
    qml6-module-org-kde-desktop qml6-module-qtquick-templates qt6-wayland python3 \
    squashfs-tools curl file ca-certificates libqt6svg6 qt6-svg-plugins qt6-image-formats-plugins fonts-dejavu-core fonts-noto-core \
    && rm -rf /var/lib/apt/lists/*
CMD ["sh", "/src/packaging/appimage/build.sh"]
