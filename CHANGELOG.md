# Changelog

## 1.13.0 (build 14) · 2026-11-19

- Added **moving looks**. Open a look and set **Motion**: **One at a time** lights one fixture while the others are dark; **One brighter** keeps the others on at a dimmer level (**Others** %) and makes one at a time brighter. **Order** is 1 → 4, 4 → 1, Bounce, Outside in, Inside out or Random; **Speed** is every 2 beats, every beat, 8ths, 8th triplets, 16ths or 32nds; **Tail** makes each light fade into the next step instead of cutting.
- Motion moves across the fixtures that follow looks (fixed-warmth groups are left out), in patch order. It only scales each fixture's level, so level CCs, fades, group maximums and the master still apply. Flash looks can move too.
- Tick **Movement only** on a look to add just its motion and keep the colour of the look under it. With **Flash** also ticked, holding its note chases whatever colour is showing (the song's look, or a flash colour on top), and colour changes under it don't restart the chase.
- Steps follow **MIDI clock** when it arrives on the selected input (in Ableton, turn on **Sync** for that output port), and Song Position keeps them on the bar when you start mid-song. Without clock they run at the look's **BPM**, starting from the first step when the look is chosen.

## 1.12.0 (build 13) · 2026-11-18

- Added **fixed warmth** for groups. Tick **Fixed warmth** on a group on the Fixture patch page and its lights ignore looks (including flashes) and show a steady white; they still take brightness from MIDI. A **Warmth** slider under the group's maximum brightness on the Console sets it from 2700 K (warm) to 6500 K (cool). It works while output is armed and is saved straight away.
- The kelvin values are approximate: the tubes mix the white from red, green and blue.
- A fixture in a fixed-warmth group shows where its warmth comes from, and its **Follows looks** switch is turned off.
- Patch files keep each group's warmth. Groups saved before 1.12.0 have none.

## 1.11.0 (build 12) · 2026-11-18

- Each square on the fixture deck now has a small **Test fixture** button. It lights that fixture at full until you click **Stop test**, which is what clicking the whole square used to do. Clicking the rest of the square does nothing, so a stray click can't switch a light on.

## 1.10.0 (build 11) · 2026-11-18

- Under **Run live preview**, a row of small squares shows what each fixture in the patch is sending over DMX: lit in its current colour and brightness, outlined when it's ready at 0, and faded when the fixture is disabled. During a live preview they light in turn with the tubes. They stay dark while output is disarmed.

## 1.9.0 (build 10) · 2026-11-18

- **Arm live output** no longer switches lights on. Every enabled fixture gets DMX straight away (its colour and effect settings) with the dimmer at 0, and waits for MIDI to set a level. The fixture deck marks these fixtures **READY**. This replaces the 1.7.0 behaviour.
- Added **Run live preview** under **Arm live output**. While output is armed, it lights each enabled fixture in turn over DMX so you can check every tube responds. MIDI is ignored until you stop it. Disarming stops it too.

## 1.8.0 (build 9) · 2026-11-18

- Added **flash looks**. Tick **Flash** on a look and it shows only while its note is held; when the note ends, the fixtures go back to the look they had before. A look note that arrives during a flash becomes the look underneath. Flash looks keep the same 50 ms minimum as fixture notes, so very short notes still reach the tubes.
- The console's **Look** menu lists only the looks that latch, and says when a flash is showing.
- Patch files keep the flash setting. Looks saved before 1.8.0 aren't flashes.

## 1.7.0 (build 8) · 2026-11-18

- **Arm live output** now switches on every enabled light at full, as if you had clicked each one on the fixture deck. Before, every light stayed dark until its MIDI arrived.
- Each light hands over to MIDI as soon as its own note or level CC arrives, so Ableton's levels, fades and blackouts work as before. Lights you click yourself stay latched until you click them again.

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
