# DualCast

Use two Bluetooth headphones on your Mac at the same time — without touching Audio MIDI Setup.

<img width="240" alt="DualCast menu bar" src="https://github.com/user-attachments/assets/placeholder.png">

## What it does

DualCast is a lightweight macOS menu bar app that creates a Multi-Output audio device from two Bluetooth headphones, so you can share audio with someone on a flight, while watching a movie, or whenever your MacBook speakers aren't an option.

Under the hood it uses macOS CoreAudio APIs to do what Audio MIDI Setup does manually — but in one click.

## Features

- **Guided setup** — step-by-step wizard to select your two headphones
- **One-click switching** — toggle between Dual Audio, either headphone individually, or built-in speakers from the menu bar
- **Colour-coded icon** — two headphones in the menu bar show green when active
- **Remembers your devices** — no need to reconfigure after the first setup
- **No dock icon** — lives entirely in the menu bar

## Requirements

- macOS 13.0 (Ventura) or later
- Two Bluetooth audio devices paired to your Mac

## Install

### Download
1. Go to [Releases](../../releases)
2. Download the latest `DualCast-x.x.x.dmg`
3. Open the DMG and drag **DualCast** to Applications
4. Launch from Applications — the headphones icon appears in your menu bar

### Build from source
```bash
git clone https://github.com/YOUR_USERNAME/DualCast.git
cd DualCast
open DualCast.xcodeproj
# Build and run (⌘R) in Xcode
```

## Usage

1. **First launch** — the setup wizard walks you through selecting two Bluetooth headphones
2. **Menu bar** — click the headphones icon to switch output:
   - 🟢🟢 **Dual Audio** — both headphones play simultaneously
   - 🟢⚪ **Device 1** — first headphone only
   - ⚪🟢 **Device 2** — second headphone only
   - ⚪⚪ **Built-in Speakers** — Mac speakers
3. **Reconfigure** — select "Reconfigure Devices…" to pick different headphones

## How it works

DualCast uses `AudioHardwareCreateAggregateDevice` with `kAudioAggregateDeviceIsStackedKey` to programmatically create a Multi-Output Device — the same thing you'd manually create in Audio MIDI Setup. It then sets this as the default output via `AudioObjectSetPropertyData`.

## Limitations

- Multi-Output Devices don't support system volume control — adjust volume on each device individually
- Devices must already be paired and connected via Bluetooth before using DualCast
- Not available on iOS (Apple doesn't expose these APIs on iOS)

## License

MIT
