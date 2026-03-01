# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Goal

A macOS menu bar utility that controls sidetone (microphone self-monitoring) on USB headsets. Generic device detection — works with any USB audio device whose `AppleUSBAudio` driver exposes settable play-through controls.

**Current phase:** Shipped. App is complete and open-sourced.

## Sidetone Control — CoreAudio API

Sidetone is exposed by the `AppleUSBAudio` driver as **play-through controls** (`kAudioDevicePropertyScopePlayThrough`) on the CoreAudio device. No root, no libusb, no special entitlements required.

**Enable sidetone** (required on every power-up — device defaults to sidetone off):

```c
// ⚠️ Inverted semantics on C-Media devices: mute=1 enables sidetone, mute=0 disables it.
UInt32 mute = 1;
AudioObjectPropertyAddress ma = {kAudioDevicePropertyMute,
    kAudioDevicePropertyScopePlayThrough, 0};
AudioObjectSetPropertyData(deviceID, &ma, 0, NULL, sizeof(mute), &mute);
```

**Set volume (scalar 0.0–1.0):**

```c
Float32 scalar = 0.5f;
AudioObjectPropertyAddress va = {kAudioDevicePropertyVolumeScalar,
    kAudioDevicePropertyScopePlayThrough, 1};
AudioObjectSetPropertyData(deviceID, &va, 0, NULL, sizeof(scalar), &scalar);
```

**Read current values:** same addresses with `AudioObjectGetPropertyData`.

Volume is logarithmically mapped: scalar=0.0 → -15 dB, scalar=1.0 → +21 dB. At scalar=0.5 the device reports ~10 dB.

**Device reconnect:** sidetone resets to off on every USB connect/power cycle. The app re-applies mute=1 and the saved volume whenever the device appears. A retry loop (every 0.25 s, up to 20 attempts) handles the window where `kAudioHardwarePropertyDevices` fires before the driver is ready to accept writes.

## Build

```bash
./build.sh
```

Produces `Sidetone.app`. No Xcode required.

## App Architecture

Menu bar only (no dock icon). All logic is in `AppDelegate.m`.

**Device qualification** — a device qualifies if:
1. It has streams on both `kAudioDevicePropertyScopeInput` and `kAudioDevicePropertyScopeOutput`
2. `kAudioDevicePropertyMute` on `kAudioDevicePropertyScopePlayThrough` element 0 is settable

**Device monitoring:** `AudioObjectAddPropertyListener` on `kAudioHardwarePropertyDevices`; callback dispatches to main queue and calls `rescanDevices`.

**On connect:** enable sidetone (mute=1) + apply saved volume (keyed by device UID in `NSUserDefaults`). Apply happens before `rebuildMenu` — reading device properties during menu build can reset driver play-through state on some devices.

**Menu updates:** the menu is rebuilt in `NSMenuDelegate menuWillOpen:`, not on every device change. Calling `removeAllItems` on a visible NSMenu leaves orphaned separators due to a macOS rendering limitation.

**Persistence:** `NSUserDefaults` key `sidetone_volume_<uid>` per device UID (default scalar: 0.5).

## Known quirks

- `kAudioDevicePropertyMute` on `kAudioDevicePropertyScopePlayThrough` has inverted semantics on C-Media CM6533: `mute=1` enables sidetone, `mute=0` disables it. Other devices may behave differently — test both values empirically.
- The menu does not update in real time while open (standard macOS menu bar behavior). Content reflects the device state at the time the menu was opened.
