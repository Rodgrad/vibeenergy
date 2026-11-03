# Plasma Store companion

This directory is a separate, pure-QML companion to the full native VibeEnergy app/widget. It reads the installed app collector's snapshot; it does not include the native EnergyLocal plugin or a collector installer.

Build the upload files without building an AppImage:

```sh
python3 builders/package_widget_store.py
```

Output: `release/kde-store/`. Upload the `.plasmoid` as a Plasma 6 Applet, use `DESCRIPTION.md` for the Store description, and follow `UPLOAD.md`. Screenshots use illustrative sample data. Nothing is published automatically.

The app/collector dependency must remain clear in the listing. The full current native widget needs compilation and cannot be distributed as a one-click KDE Store widget: https://develop.kde.org/docs/plasma/widget/c-api/

The companion has a distinct ID, `org.energytlk.monitor.companion`, and does not replace `org.energytlk.monitor`.

Turbo follows the app: always-on mode reads the shared appearance setting; five-second bursts read the optional, expiring `energytlk/turbo.json` state published by current app builds. The companion reuses the app’s Canvas lightning renderer without audio or a native plugin. Missing settings/state disable the effect. The app does not probe for or require the widget.
