# VibeEnergy Cost Monitor — Plasma 6 companion

This is a pure-QML, read-only companion to VibeEnergy. It does not contain or compile the desktop app's native plugin.

Install and open VibeEnergy separately to start its collector. The widget reads `${XDG_STATE_HOME:-$HOME/.local/state}/energytlk/state.json` every second. Recording, price, currency, history, and Powerstat setup are managed in the app. Closing the app window to its tray keeps recording; Quit VibeEnergy stops recording and this widget then reports Offline.

Requires Plasma 6, Qt Quick Controls, Kirigami, and Plasma 5 Support's executable data engine (provided by Plasma). No native build, Python interpreter, or administrator access is required for this widget itself. The separate collector/app has its own dependencies. The executable engine runs only a fixed local command to read the snapshot; it does not download or install software.

CPU and GPU wattage are shown when fresh, alongside Today, This month and All time summaries. Costs show only the app's selected currency; energy totals include the recorded components across currencies. No currency conversion is applied. Integrated/shared power domains excluded by the collector remain excluded. These are component readings, not whole-PC wall-socket measurements.

License: GNU GPL version 3. See LICENSE.

The Recording indicator and warning use the same five-second freshness limit. Re-reading an unchanged snapshot does not reset the timeout. The highlighted warning appears after five seconds without a new collector timestamp, including if the app or collector stops; it disappears as soon as fresh readings resume. There is no separate app-installation probe.

Website: https://vibeenergy.techtoapes.com/
Source and support: https://github.com/Rodgrad/vibeenergy
