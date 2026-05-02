# AudioCast Driver

Virtual macOS audio device for [AudioCast](https://github.com/jobtools/audiocast) — a fork of [BlackHole](https://github.com/ExistentialAudio/BlackHole) with AudioCast branding.

System Settings → Sound shows it as **AudioCast** (not "BlackHole 2ch"). Bundle ID is `com.audiocast.driver`. 2 channels, 24-bit, any sample rate up to 768 kHz — same as BlackHole 2ch underneath.

## Install (recommended: Homebrew)

```bash
brew tap jobtools/audiocast
brew install --cask audiocast-driver
```

The AudioCast app cask depends on this, so installing the app pulls the driver in too.

## Install (manual)

Download the latest `.pkg` from [Releases](https://github.com/jobtools/audiocast-driver/releases) and double-click.

## Build from source

Requires Xcode + the AudioCast self-signed cert (or substitute your own with `AUDIOCAST_CERT_P12`/`AUDIOCAST_CERT_PASS` env vars).

```bash
bash Installer/build_audiocast.sh
# → Installer/AudioCast-<version>.pkg
```

The build script overrides only what differs from upstream BlackHole:
- `kDriver_Name` → `AudioCast`
- `kDevice_Name` → `AudioCast`
- `kManufacturer_Name` → `AudioCast`
- `kPlugIn_BundleID` → `com.audiocast.driver`

The driver source tree (`BlackHole/`) is unchanged — branding lives in build flags.

## License

GPL-3.0 (inherited from BlackHole). All source — including AudioCast's branding overrides — is in this repo.

## Credits

Built on [BlackHole](https://github.com/ExistentialAudio/BlackHole) by Existential Audio Inc. (Devin Roth). All audio engineering is theirs; this fork only renames the device for brand consistency with AudioCast.
