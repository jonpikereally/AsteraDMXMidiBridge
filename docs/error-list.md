# AsteraDMXMidiBridge error list

Find the code shown in the app below. The same reference is under **Error list** in the app. If you report a problem, include the code, version and build from the console footer, your macOS version, and the selected output method.

## MIDI and output selection

| Code | What happened | What to check |
| --- | --- | --- |
| `AX1-104` | MIDI input disconnected | Reconnect the device and select it under **MIDI input**. The app cleared any held notes. |
| `AX1-105` | No USB output selected | Connect the ENTTEC Open DMX USB, refresh the USB list, then select the device. If it stays missing, try the [QLC+ fallback](../README.md#qlc-fallback-with-the-same-enttec). |
| `AX1-301` | Core MIDI could not start | Restart the app and check that the controller appears in Audio MIDI Setup. |
| `AX1-302` | Core MIDI input port could not open | Restart the app and check Audio MIDI Setup. |
| `AX1-303` | MIDI source is unavailable | Select a connected source under **MIDI input**. |
| `AX1-304` | Could not connect to the MIDI source | Reconnect the controller or enable the IAC bus, then select it again. |
| `AX1-305` | Could not disconnect the MIDI source | Reselect the source or restart the app. |

## Patch and destination

| Code | What happened | What to check |
| --- | --- | --- |
| `AX1-201` | Missing Art-Net address | Enter the node’s unicast IPv4 address, or click **Use QLC+ loopback** for a QLC+ instance on this Mac. |
| `AX1-202` | Invalid Art-Net address | Enter a unicast IPv4 address for the Art-Net receiver. |
| `AX1-203` | Invalid Art-Net universe | Use an Art-Net universe from 0 to 32767. QLC+ Universe 1 uses Art-Net universe 0 by default. |
| `AX1-204` | Invalid MIDI channel | Select **Omni** or channel 1–16. |
| `AX1-205` | Invalid master CC | Use MIDI CC 0–119. |
| `AX1-206` | Fixture address is outside the universe | Use a start address of at least 1 and leave enough slots for its DMX profile up to slot 512. |
| `AX1-207` | Note range is outside MIDI’s 128 notes | Keep every note in 0–127. **Note per pixel** needs sixteen consecutive notes. |
| `AX1-208` | Fixtures share DMX slots | Move one fixture to a free range, or choose **Auto-patch → Pack DMX addresses from 1**. |
| `AX1-209` | Fixtures share MIDI notes | Move one fixture to a free note range, or choose **Auto-patch → Pack MIDI notes from 0**. |
| `AX1-210` | Patch file couldn’t be read | The file is damaged or not valid JSON. Export the patch again from AsteraDMXMidiBridge and import the new file. |
| `AX1-211` | Not an AsteraDMXMidiBridge patch | Choose a file made with **Export…** on the **Fixture patch** page. |
| `AX1-212` | Patch from a newer app version | Choose **AsteraDMXMidiBridge → Check for Updates**, install the update, then import again. |
| `AX1-214` | Invalid level CC | Use a level CC from 0 to 119 that isn’t the master CC, or choose **None**. |
| `AX1-215` | Look note already in use | Give the look a note that no fixture or other look uses. |
| `AX1-213` | Patch couldn’t be exported | Choose a folder you can write to, such as Documents, and export again. |

## Art-Net output

| Code | What happened | What to check |
| --- | --- | --- |
| `AX1-306` | Invalid Art-Net destination | Enter a unicast IPv4 address or use the QLC+ loopback preset. |
| `AX1-307` | Invalid Art-Net universe | Use an Art-Net universe from 0 to 32767. |
| `AX1-308` | UDP socket could not open | Check the network connection or try the QLC+ loopback preset. |
| `AX1-309` | Art-Net output is disarmed | Click **Arm live output**. |
| `AX1-310` | Wrong Art-Net frame size | Restart the app. If it repeats, report the code and build. |
| `AX1-311` | Art-Net send failed | Check the network connection and Local Network permission in macOS, then rearm. |

## USB DMX output

| Code | What happened | What to check |
| --- | --- | --- |
| `AX1-312` | Selected USB interface is unavailable | Reconnect the interface, refresh the list, and select it again. |
| `AX1-313` | USB serial port could not open | Quit other apps using the interface, reconnect it, and rearm. |
| `AX1-314` | USB serial configuration failed | Reconnect the interface. Use the [QLC+ fallback](../README.md#qlc-fallback-with-the-same-enttec) if it repeats. |
| `AX1-315` | Open DMX USB stream stopped | Check the USB connection and rearm. Try the QLC+ fallback if it recurs. |
| `AX1-316` | Wrong USB DMX frame size | Restart the app. If it repeats, report the code and build. |
| `AX1-317` | USB output is disarmed | Click **Arm live output**. |
| `AX1-318` | Previous USB stream is still closing | Wait for output to stop and try arming again. |
| `AX1-319` | Direct USB connection could not open | Quit other apps using the interface, and reconnect it. Select its serial entry if one is available, or use QLC+. |
| `AX1-320` | Direct USB stream stopped | Check the USB cable and rearm. Try the QLC+ fallback if it recurs. |

## Update check

| Code | What happened | What to check |
| --- | --- | --- |
| `AX1-401` | Installed app version is unreadable | Replace the app with a packaged build from [GitHub Releases](https://github.com/jonpikereally/AsteraDMXMidiBridge/releases). |
| `AX1-402` | GitHub could not be reached | Check your internet connection and retry. You can also open GitHub Releases manually. |
| `AX1-403` | Update check timed out | Retry from **AsteraDMXMidiBridge → Check for Updates**, or open GitHub Releases manually. |
| `AX1-404` | GitHub rate limited the check | Wait and retry, or open GitHub Releases manually. |
| `AX1-405` | GitHub returned an unexpected response | Try again later and check GitHub Releases manually if it repeats. |
| `AX1-406` | The release did not have a stable version the app could read | Check the releases page for a stable version with a version tag such as `v1.2.0`. |
| `AX1-407` | The app could not open your browser | Open the [GitHub Releases page](https://github.com/jonpikereally/AsteraDMXMidiBridge/releases) in a browser. |
| `AX1-408` | The release has no app download | Click **View release** and download `AsteraDMXMidiBridge.zip` manually, if it is there. |
| `AX1-409` | This copy can’t update itself | The app is a development build or macOS is running it from a temporary location. Move `AsteraDMXMidiBridge.app` to Applications, open it from there and try again. |
| `AX1-410` | You can’t write to the app’s folder | Move the app to a folder you own, such as Applications on your own Mac, or click **View release** and install manually. |
| `AX1-411` | The update couldn’t be downloaded | Check your internet connection and try again. |
| `AX1-412` | The downloaded update couldn’t be unpacked | Try again. If it repeats, click **View release** and install manually. |
| `AX1-413` | The downloaded update failed its checks | The app wasn’t changed. The download wasn’t AsteraDMXMidiBridge, wasn’t the expected newer version, or had a broken code signature. Install manually from **View release** and report the message. |
| `AX1-414` | The app couldn’t be replaced | Your current version is unchanged. Quit any other copy of the app, then try again or install manually from **View release**. |
| `AX1-415` | The update is installed but the app couldn’t restart | Quit AsteraDMXMidiBridge and open it again. |
