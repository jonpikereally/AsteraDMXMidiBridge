# Changelog

## 1.3.0 (build 4) · 2026-11-17

- Added Astera profile **16 · Effect Mode RGB** (21 channels). Pick a built-in program, strobe, speed, crossfade, direction, size, offset, restart and four colours per tube. The MIDI note and master level drive the dimmer.
- Added **Import…** and **Export…** on the Fixture patch page to save and reload patches as JSON files. Error codes AX1-210 to AX1-213 cover failed imports and exports.
- Moved **Check for Updates…** to the app menu (**AsteraDMXMidiBridge → Check for Updates…**).

## 1.2.0 (build 3) · 2026-11-17

- Renamed AX1 Bridge to AsteraDMXMidiBridge. Existing MIDI and fixture preferences remain available.
- Added **Help → Check for Updates** for stable GitHub Releases, with manual download and installation.
- Added public setup instructions and an error code reference.

## 1.1.0 (build 2) · 2026-11-17

- Added direct USB output for the FT232R-based ENTTEC Open DMX USB when a serial port is unavailable, with automatic device discovery.

## 1.0.0 (build 1) · 2026-11-17

- Initial macOS app with a MIDI console, an eight-tube patch, five AX1 profiles, MIDI Learn, velocity, blackout, and a preview of fixture output.
- Included automatic DMX and MIDI patching and a minimum 50 ms hold for short notes.
- Added serial output for ENTTEC Open DMX USB and unicast Art-Net output, including the QLC+ loopback preset.
