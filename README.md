# usb-headset-sidetone

A macOS menu bar app that controls sidetone (microphone self-monitoring) on USB headsets.

Sidetone lets you hear your own voice through the headset while speaking, reducing the tendency to talk too loudly. Most USB headsets support it at the hardware level, but macOS provides no built-in UI to adjust it.

## How it works

macOS's `AppleUSBAudio` driver exposes the headset's internal sidetone mixer as CoreAudio play-through controls (`kAudioDevicePropertyScopePlayThrough`). This app sets those controls directly — no root access, no kernel extensions, no USB packet injection required.

**Device detection** is generic: any USB audio device that has both input and output streams and a settable play-through mute qualifies. Multiple devices are supported simultaneously.

**On every connect**, the app re-enables sidetone and restores your saved volume level. (The hardware mute resets to its default state on every USB power cycle.)

**Volume** is persisted per-device UID in `NSUserDefaults`, so each headset remembers its own level across launches and reconnects.

## Requirements

- macOS 13 (Ventura) or later
- A USB headset whose `AppleUSBAudio` driver exposes play-through controls (most USB headsets with a built-in microphone qualify)

### Confirmed working hardware

- C-Media CM6533 (VID `0x0D8C`, PID `0x0147`) — the reference device this was built and tested on

## Build

No Xcode required. From the project directory:

```bash
./build.sh
```

This produces `Sidetone.app` in the current directory. Open it with:

```bash
open Sidetone.app
```

To have it launch at login, open the menu and enable **Launch at Login**. You can also manage it later from **System Settings → General → Login Items**.

## Usage

Click the ear icon in the menu bar to open the menu. Each connected qualifying device appears with its name and a volume slider. The dB value shown is read back directly from the device.

Dragging the slider to the far left silences sidetone without a separate mute toggle.

## Technical notes

### Play-through mute is inverted

On the CM6533 (and likely other C-Media devices), the `kAudioDevicePropertyMute` property on `kAudioDevicePropertyScopePlayThrough` has **inverted semantics**:

- `mute = 1` → sidetone **enabled**
- `mute = 0` → sidetone **disabled**

This is the opposite of what the property name implies and the opposite of what Apple's documentation suggests for other devices. If you are adapting this code for a different device, test both values empirically.

## Project structure

```
AppDelegate.h / AppDelegate.m   — all app logic
main.m                          — NSApplicationMain entry point
Info.plist                      — LSUIElement=YES (menu bar only, no dock icon)
build.sh                        — builds Sidetone.app without Xcode
```

## License

MIT. See [LICENSE](LICENSE).
