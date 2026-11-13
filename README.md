# CmdFocus

A replacement for the Mac's Cmd+Tab app switcher that only shows apps you can actually see.

The built-in switcher lists every running app. CmdFocus leaves out:

- apps you've hidden (Cmd+H)
- apps whose windows are all minimized or closed
- apps whose windows are all on a different desktop (Space)

Everything else works the way you're used to.

## Using it

| Do this | To |
| --- | --- |
| Cmd+Tab | Move to the next app |
| Cmd+Shift+Tab | Move back |
| Let go of Cmd | Switch to the highlighted app |
| Cmd+Q | Quit the highlighted app |
| Cmd+H | Hide the highlighted app |
| Esc | Close the switcher without switching |
| Move the mouse over an icon | Highlight it |
| Click an icon | Switch to it |

Keep holding Cmd the whole time, just like the normal switcher.

CmdFocus lives in the menu bar (the ⌘ icon). Click it to turn on **Launch at Login** or to quit.

## Installing

You need a Mac running macOS 26 or newer.

1. Download `CmdFocus.zip` from the [latest release](https://github.com/akowalz/cmd-focus/releases/latest).
2. Double-click the zip, then drag **CmdFocus** into your **Applications** folder.
3. Open CmdFocus. macOS will say it can't be opened. Click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway** next to the CmdFocus message. Confirm when asked.
5. macOS will now ask to let CmdFocus control your computer. Click **Open System Settings** and switch CmdFocus on under **Accessibility**.

That's it. The menu bar icon turns from a warning triangle into ⌘ when it's working.

Steps 3 and 4 are only needed the first time. They're there because the app isn't signed with a paid Apple developer certificate.

### Why does it need Accessibility access?

That permission is what lets CmdFocus notice Cmd+Tab before macOS does. It doesn't read or record anything else you type.

## If it stops working

**If the normal switcher shows up instead**, CmdFocus isn't running or doesn't have permission. Check for the ⌘ icon in the menu bar.

**After updating to a new version**, macOS forgets the permission. To fix it:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Select CmdFocus and click the **–** button to remove it.
3. Open CmdFocus again and switch it back on.

## Good to know

- Only apps with a window on the desktop (Space) you're currently looking at show up. Switch desktops and the list changes.
- The order is most recently used first. Right after CmdFocus starts, the order may be a little different from what you expect until you've switched apps a few times.
- If the app you're in has no windows, it won't be in the list.

## Building it yourself

1. Install Xcode and download this code.
2. Open `CmdFocus.xcodeproj` and press Run (Cmd+R).
3. Grant Accessibility access as in step 5 above.

Each rebuild counts as a new version, so you'll need the "after updating" fix above every time.

To publish a new version, push a tag like `v0.2.0`. GitHub builds the app and adds it to the Releases page.

## License

[MIT](LICENSE)
