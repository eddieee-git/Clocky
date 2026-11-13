# Install guide

[← Back to README](../README.en.md) · [한국어](install.md)

## Requirements

- A Mac with Apple silicon (M1 or later). Intel Macs aren't supported.
- macOS 13 or later. Clocky was developed and tested on macOS 26.

## Install

1. Download `Clocky-<version>.dmg` (`Clocky.dmg` up to 0.2.1) from [Releases](https://github.com/eddieee-git/mac-app-clocky/releases).
2. Open the dmg and drag Clocky to the Applications folder. Open Clocky from the Applications folder, not from the dmg window, or it quits when you eject the dmg.
3. Eject the dmg.
4. Open Clocky from the Applications folder.

Clocky doesn't add a Dock icon. If an alarm-clock icon appears in the menu bar at the top of the screen and the clock window opens, it's working.

You can check the download against the SHA-256 value listed on the release:

```bash
shasum -a 256 ~/Downloads/Clocky*.dmg
```

## The security warning on first launch

The first time you open Clocky after downloading it, macOS blocks it and shows a warning. The wording depends on your macOS version; it usually says Apple can't check the app for malicious software.

**Why does this happen?** By default, macOS blocks apps that aren't signed and notarized through Apple's paid developer program. Clocky is a free project and isn't notarized. The warning doesn't mean a problem was found, but it does mean Apple hasn't checked the app. Only open files from sources you trust. The code is public in this repository, so you can review it and [build it yourself](../README.en.md#building-from-source).

### Option 1: Allow it in System Settings

1. Click **Done** (or **OK**) to close the warning. Don't click **Move to Trash**.
2. Open **System Settings → Privacy & Security**.
3. Scroll down to **Security** and click **Open Anyway** next to the message about Clocky.
4. In the confirmation, click **Open Anyway** again and approve with your Mac password or Touch ID.

You only need to do this once. You may need to do it again after installing a new version.

### Option 2: Terminal

If you use Terminal, this single command does the same thing. Run it after moving Clocky to the Applications folder.

```bash
xattr -dr com.apple.quarantine /Applications/Clocky.app
```

This also fixes the "is damaged and can't be opened" message.

## Open at login

Turn on **Settings → General → Open at Login**. Do this after Clocky is in the Applications folder. If you use alarms or calendar alerts, keep this on; nothing rings while Clocky is quit.

## Calendar access

When you turn on **Settings → Calendar → Alert for Mac Calendar events**, macOS asks for calendar access. Allow it so Clocky can read events from the Calendar app. To change it later, go to **System Settings → Privacy & Security → Calendars** and turn on Clocky.

## Update

Clocky checks GitHub for a new version once a day. When there is one, the menu bar menu shows **Get New Version, Clocky …**, and so does **Settings → General → Updates**. To check right away, choose **Check for Updates…** from the menu. You can turn off automatic checks in Settings.

1. Choose **Get New Version…** → **Download**. Clocky saves `Clocky 0.x.x.dmg` to your Downloads folder and opens it. Clocky checks that the file matches the one on GitHub (SHA-256) and that the developer's signature is valid. It won't download a file that's unsigned or doesn't match.
2. Click **Quit Clocky** in the window that explains the next steps.
3. In the window that opened, drag Clocky to the Applications folder to replace the old app, then open Clocky again.
4. If the security warning appears again, allow it as above. If you use the Mac Calendar option, macOS may ask for calendar access again.

Version 0.2.0 doesn't check for updates, so update from 0.2.0 by hand once:

1. Click the menu bar icon → **Quit Clocky**.
2. Open the new `Clocky-<version>.dmg` and drag Clocky to the Applications folder to replace the old app.
3. If the security warning appears again, allow it as above. If you use the Mac Calendar option, macOS may ask for calendar access again.

Your settings, alarms, and connected calendars are stored separately from the app and stay as they are.

## Uninstall

1. Click the menu bar icon → **Quit Clocky**.
2. Move Clocky from the Applications folder to the Trash.

To also remove your settings, alarms, connected calendars, and sound files, move the `~/Library/Containers/com.eddieee.Clocky` folder to the Trash in Finder, or run the command below. If macOS asks whether Terminal may access another app's data, allow it.

```bash
rm -rf ~/Library/Containers/com.eddieee.Clocky
```
