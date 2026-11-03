# KDE Store upload kit

Upload the `.plasmoid` file as a **Plasma 6 Applet**, not an AppImage or source installer.

- Name: VibeEnergy Cost Monitor
- Version: 1.0.8
- License: GPL-3.0-only
- Tags: plasma6, system-monitor, cpu, gpu, energy, electricity, nvidia, amd, intel
- Description: use DESCRIPTION.md; retain its app/collector dependency notice.
- Screenshots: `widget-preview.png` shows the current widget with Turbo off; `widget-turbo.png` shows Turbo on. Both use illustrative synthetic 60-day history, not measurements of a particular PC.
- Source/support: https://github.com/Rodgrad/vibeenergy

The Store package has ID `org.energytlk.monitor.companion`, separate from the full native widget `org.energytlk.monitor`. Do not replace the full widget with this package ID.

Test installation as a normal user:

```sh
kpackagetool6 --type Plasma/Applet --install vibeenergy-monitor-1.0.8.plasmoid
# To update an existing companion installation:
kpackagetool6 --type Plasma/Applet --upgrade vibeenergy-monitor-1.0.8.plasmoid
```

Then add **VibeEnergy Cost Monitor** from Plasma's widget picker. Open VibeEnergy to start recording. It is normal for a fresh installation to show Offline until the backend is installed and running.

KDE does not support Store widgets that require compilation: https://develop.kde.org/docs/plasma/widget/c-api/
This companion is pure QML/JavaScript and reads an existing snapshot. It intentionally does not bundle the C++ EnergyLocal plugin, Python collector, privileged commands, native Turbo renderer, or app settings/uninstaller.

Nothing is published automatically by the packaging script.
