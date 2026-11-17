# Changelog

## 1.6.0 (build 7) · 2026-11-17

- Added **Maximum brightness** for each light, on the Console under the fixture deck. It scales everything the light outputs and works while output is armed.
- Added **Groups** on the Fixture patch page. A group has its own maximum brightness on the Console. A light can be in several groups; its output is scaled by its own maximum and every group's, so 80% in a 50% group peaks at 40%.
- Patch files are now version 3 and include maximums and groups. Older patches still import, with every maximum at 100%.

## 1.5.0 (build 6) · 2026-11-17

- Added **Looks**. A look is a MIDI note with a colour and Effect Mode settings. Playing its note switches every fixture that has **Follows looks** turned on, until the next look note. Edit looks on the **Fixture patch** page and pick one from **Look** on the console.
- Added a **Level CC** per fixture. The CC sets the fixture's level (0–127) without holding a note, so a DAW can fade tubes with a CC envelope. The dimmer uses the held note or the CC, whichever is higher, scaled by the master. CC 120 and 123 reset level CCs to 0 as well as releasing notes.
- Patch files are now version 2 and include looks and level CCs. Version 1 patches still import. Error codes AX1-214 and AX1-215 cover invalid level CCs and look notes.

## 1.4.0 (build 5) · 2026-11-17

- Added **Install and relaunch** to the update banner. The app downloads the release's `AsteraDMXMidiBridge.zip` from GitHub, checks the bundle identifier, version and code signature, replaces itself and reopens. Error codes AX1-408 to AX1-415 cover failed installs. **View release** still opens the release page for a manual install.

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
