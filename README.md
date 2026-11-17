# AsteraDMXMidiBridge

AsteraDMXMidiBridge turns MIDI notes into live DMX for up to eight Astera AX1 or AX1-BTB PixelTubes on one universe. It supports the ENTTEC Open DMX USB (70303) connected to an AsteraBox ART7, or unicast Art-Net to a network node. The fixtures receive DMX over CRMX.

[Download the latest macOS release](https://github.com/jonpikereally/AsteraDMXMidiBridge/releases/latest) · [Changelog](CHANGELOG.md) · [Error list](docs/error-list.md)

## Open the app

1. Download the app ZIP from [GitHub Releases](https://github.com/jonpikereally/AsteraDMXMidiBridge/releases/latest), unzip it, and open `AsteraDMXMidiBridge.app` on an Apple silicon Mac with macOS 13 or later. You can move it to Applications.
2. In **Console**, click **Run preview** to see a demo. Click **Stop preview** before testing MIDI. You can also click a fixture to light it in the preview, then click it again to release it.
3. Connect your MIDI controller and choose it under **MIDI input**. For a DAW, enable the IAC Driver in Audio MIDI Setup and route a MIDI track to an IAC bus. Select that bus as the input in AsteraDMXMidiBridge. [Apple's IAC setup instructions](https://support.apple.com/en-ca/guide/audio-midi-setup/ams1013/mac)

The app is signed ad hoc for local use. If Gatekeeper asks you to approve it after the first launch attempt, see [Apple’s instructions for opening an app from an unidentified developer](https://support.apple.com/en-us/102445).

Choose **AsteraDMXMidiBridge → Check for Updates** to check the latest stable public GitHub release. If an update is available, open its release page, download the new ZIP, quit the app, and replace the old copy. The app checks when you ask and leaves installation to you. The console footer shows the installed version, build number, and build time.

## Connect the ENTTEC and ART7

1. Connect the ENTTEC Open DMX USB to your Mac using its USB-B port. Connect the ENTTEC’s five-pin DMX **OUT** to the ART7’s **DMX** jack with the Astera ART7-DMXA adapter. The adapter activates the ART7’s CRMX module when inserted. A five-pin DMX extension cable can go between the ENTTEC and the adapter if needed. [ENTTEC 70303 datasheet](https://cdn.enttec.com/pdf/assets/70303/70303_OPEN_DMX_USB_DATASHEET.pdf) · [AsteraBox datasheet](https://astera-led.com/wp-content/uploads/ART7_AsteraBox_Datasheet_V3.pdf)
2. Turn on the ART7 and check that **TX** is blue. If the box is in RX, press the green **Link** button five times in quick succession and hold it for about three seconds. When **DMX** and **Link** flash in turn, press **Link** once to switch modes, then hold it again for about three seconds to confirm. [AsteraBox manual](https://rental-supplier.nl/wp-content/uploads/2024/11/ART7_AsteraBox_Manual_EN_AV-Supplier.pdf)
3. Power on the tubes. If a tube is already linked to a different CRMX transmitter, unlink it first using AsteraApp or the tube’s reset procedure. A reset can clear fixture settings, so set the patch below afterward. Press **Link** on the ART7 once and allow about 10 seconds for the tubes to link. [AX1 manual](https://static1.squarespace.com/static/5dc5a5ce772cfe59c2c1ff22/t/65380a714f57b211dc42555c/1698171509714/AX1_PixelTube_Manual_EN_DE_IT_ES_FR_CN.pdf) · [AX1-BTB manual](https://fccid.io/X55AX1-BTB/User-Manual/User-Manual-6169416)
4. In AsteraApp’s **DMX Configuration**, set **Input Select** to **CRMX Wireless DMX**. Match the profile and start address shown for each tube in AsteraDMXMidiBridge. After you send a configuration from AsteraApp, press the button on each intended tube when prompted to apply its settings. [Astera AX1 Technical Reference Manual](https://cdn.cvp.com/pdf/ax1-manual--en-.pdf#page=31)
5. In **Console** under **DMX output**, select **ENTTEC Open DMX USB** and choose its entry. It may appear as a `usbserial…` port or as **Open DMX (direct USB)**. AsteraDMXMidiBridge checks automatically, and the circular refresh button checks immediately. Click **Arm live output**, then play note **36** or click the first fixture with the default patch. Check that the ART7’s **DMX** indicator lights and that tube 1 responds. Verify the rest of the tubes one at a time.

## Patch and play

| Tube | MIDI note number | Default DMX start address |
| --- | ---: | ---: |
| 1 | 36 | 1 |
| 2 | 37 | 4 |
| 3 | 38 | 7 |
| 4 | 39 | 10 |
| 5 | 40 | 13 |
| 6 | 41 | 16 |
| 7 | 42 | 19 |
| 8 | 43 | 22 |

The default patch uses Astera profile **1 RGB** with one pixel and strobe off. In **Fixture patch**, change a tube’s start address, profile, colour or note to suit your rig. Profiles 2 and 5 also have a separate **W** control for white. Click **Learn** in a fixture row and play the key or pad on your controller to assign a note. Select **Omni** to listen on all MIDI channels or choose a particular channel. Use **Auto-patch** to pack the enabled fixtures back to back by DMX address or MIDI note. Click **Apply patch** to save your changes. Disarm live output before editing the patch.

Note velocity sets intensity. Note Off, including a zero-velocity Note On, releases the tube. Very short notes are held for at least 50 ms so they have a chance to reach the next DMX frame. MIDI CC 7 controls the master level by default. Use **Blackout** to force zero output while the connection is armed.

| Astera profile | Mode | DMX slots per tube |
| --- | --- | ---: |
| 1 | RGB · 1 pixel | 3 |
| 2 | RGBW · 1 pixel | 4 |
| 4 | Dimmer + RGB · 1 pixel | 4 |
| 5 | Dimmer + RGBW · 1 pixel | 5 |
| 16 | Effect Mode RGB | 21 |
| 42 | RGB · 16 pixels | 48 |

For profile 42, each tube occupies 48 consecutive channels, with RGB repeated for all sixteen pixels. Choose **All pixels** to trigger the whole tube with one note or choose **Note per pixel** to assign sixteen consecutive notes starting from the row’s base note. For eight tubes all on profile 42, use DMX start addresses **1, 49, 97, 145, 193, 241, 289, 337**. If all eight use **Note per pixel**, base notes **0, 16, 32, 48, 64, 80, 96, 112** cover all 128 MIDI notes without overlap. Set both the app and the tubes to the same profile. Leave room for the full channel count when mixing profiles. [Astera AX1/AX1-BTB DMX profiles](https://www.nashvillegrip.com/uploads/9/8/7/3/98739938/ax1_ax1-btb_ax1_pixeltube_dmx_profiles_v2.pdf)

### Effect Mode RGB (profile 16)

Effect Mode RGB runs Astera’s built-in programs on the tube itself. When you choose it in **Fixture patch**, extra controls appear under that row. The channel map follows Astera’s AX1/AX1-BTB DMX Profiles sheet (V2, page 278):

| Ch | Function | How the app sets it |
| ---: | --- | --- |
| 1 | Dimmer | The fixture’s MIDI note velocity × master level. Closed when the note is released. |
| 2 | Strobe | **Strobe**: Off, Random fast/medium/slow, or Variable (0.4–25 Hz, values 7–255). |
| 3 | Program | **Program**: one of the 20 programs on the sheet, from One Color Static to Rotor Split 4. |
| 4 | Speed | **Speed** slider, slow → fast. |
| 5 | Crossfade | **Crossfade** slider, no fade → smooth fade. |
| 6 | Direction | **Direction**: forward or reverse, looping or once. |
| 7 | Size | **Size**: 1–4 groups. |
| 8 | Offset | **Offset** slider. Shifts the tube within the program when Size is more than 1 group. |
| 9 | Restart program | **Restart** slider. Changing the value restarts the program. |
| 10–12 | Colour 1 RGB | The row’s main colour. |
| 13–21 | Colours 2–4 RGB | The three colour wells under the row. |

Channels 2–21 are sent continuously while output is armed, so the program keeps running between notes; only the dimmer follows MIDI. Set the tube to profile 16 at the same start address in AsteraApp.

## Save and share patches

On **Fixture patch**, click **Export…** to save the patch shown, including every fixture’s profile, address, note, colours and effect settings, plus the MIDI channel and master CC, as a `.json` file. Click **Import…** to load one into the editor, check it, and click **Apply patch** to use it. Imports leave your output method, Art-Net address and universe unchanged. If an import or export fails, the error code is listed in the [error list](docs/error-list.md).

## QLC+ fallback with the same ENTTEC

If you need another way to send DMX through the ENTTEC, QLC+ 5 can receive AsteraDMXMidiBridge’s Art-Net on the same Mac and forward it to USB. Keep the ENTTEC connected to the ART7 as above. Let QLC+ be the only app with the USB device open. [QLC+ downloads](https://www.qlcplus.org/download)

1. Start with a blank workspace in QLC+. In **Inputs/Outputs**, drag **Art-Net 127.0.0.1** onto the left side of **Universe 1** as the input. Drag the ENTTEC device under **DMX USB** to the right side as the output. If you need to force the USB device type, choose **Open TX** in the DMX USB plug-in configuration.
2. Toggle the small **Passthrough** arrow on the Universe 1 block. This forwards the incoming channel values to that universe’s output, with no fixture patch needed inside QLC+.
3. In AsteraDMXMidiBridge, choose **Art-Net** and click **Use QLC+ loopback** to fill in address **127.0.0.1** and Art-Net universe **0**. Click **Arm live output** and try a fixture. QLC+ Universe 1 receives Art-Net universe 0 by default. Leave QLC+ open for as long as you’re using this route.

[QLC+ universe passthrough](https://docs.qlcplus.org/v5/input-output#universe-passthrough) · [QLC+ Art-Net plug-in](https://docs.qlcplus.org/v5/plugins/art-net) · [QLC+ DMX USB plug-in](https://docs.qlcplus.org/v5/plugins/dmx-usb)

With a network Art-Net node, use its unicast IPv4 address and the universe configured on the node. A node that sends CRMX can reach the tubes directly. A node with wired DMX output can feed the ART7 through the Astera adapter. Allow AsteraDMXMidiBridge access if macOS asks for Local Network permission.

The direct USB option is for the FT232R-based ENTTEC Open DMX USB when the interface appears in the Mac’s USB device tree without a serial port. The app opens the device when you arm output. Check the ART7’s DMX indicator during setup and use the QLC+ route if the direct connection does not reach the ART7.

## If a tube stays dark

- If the preview stays dark too, check the MIDI input, note number and MIDI channel. Click a fixture in **Console** to check the patch without using the MIDI source.
- If the preview works but the ART7 **DMX** indicator stays dark, check that output is armed, that you selected the correct output, and that the DMX adapter is fully seated. For USB detection, check that the ENTTEC appears under USB in macOS System Information, then quit other apps using the interface. [ENTTEC’s macOS troubleshooting](https://support.enttec.com/dmx/usbdmx-open-dmx-usb-70303/open-dmx-usb-macos-software-not-recognizing-device)
- If the ART7 receives DMX, check the tube’s CRMX link, input selection, DMX start address and profile. Check the master level and Blackout switch.
- If the app reports an error, look up the displayed code in the app’s **Error list** or the [public error list](docs/error-list.md).

## Build from source

Use a Mac with Xcode or the Xcode Command Line Tools and Swift 5.9 or later. These commands clone the source into Downloads, run the tests, and package the app for the Mac running the build.

```zsh
worktree="$HOME/Downloads/AsteraDMXMidiBridge"
git clone https://github.com/jonpikereally/AsteraDMXMidiBridge.git "$worktree" &&
  swift test --package-path "$worktree" &&
  "$worktree/Scripts/package-app.zsh" "$HOME/Downloads/AsteraDMXMidiBridge.zip"
```

Send changes to `staging` for testing before merging to `main`. GitHub Actions runs the Swift tests and a release build on macOS. Tagged releases on `main` carry the downloadable app archive.
