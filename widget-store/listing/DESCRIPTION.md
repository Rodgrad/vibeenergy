# VibeEnergy Cost Monitor

A lightweight Plasma 6 companion widget for VibeEnergy: see CPU/GPU power, recorded energy, and estimated electricity costs on your desktop or panel.

## Features

- Live CPU, GPU, and combined component power.
- Today, This month, and All time energy/cost summaries.
- Current-currency cost display, without mixing currencies or applying exchange rates.
- Compact panel view and expanded dashboard.
- Automatic warning after five seconds without a new collector reading; disappears when readings resume.
- Local data only; no telemetry or cloud account.

## Required: VibeEnergy app / collector

**This is a read-only companion, not the full VibeEnergy desktop app.** Install and open [VibeEnergy](https://github.com/Rodgrad/vibeenergy/releases) separately to start recording. Manage price, currency, recording at login, and optional Powerstat CPU setup in the app. The widget does not install or launch a collector automatically.

The widget needs Plasma 6, Kirigami, Qt Quick Controls, and the Plasma 5 Support executable data engine. It ships no native binaries and needs no compilation. The separate VibeEnergy AppImage currently targets x86-64 Linux with glibc 2.41+; source installation has its own dependencies.

Hardware coverage depends on the collector, sensors, and drivers: supported Intel/AMD CPUs and NVIDIA/AMD dedicated GPUs. CPU recording may require separately configured Powerstat. NVIDIA needs its driver-provided nvidia-smi. Intel GPUs and shared integrated GPU power domains are excluded to prevent double counting.

Energy readings cover CPU/GPU components, not total wall power. Costs are estimates based on the price entered in VibeEnergy.

Website: https://vibeenergy.techtoapes.com/

License: GPL-3.0-only. Source and support: https://github.com/Rodgrad/vibeenergy
