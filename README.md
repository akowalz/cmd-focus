# CmdFocus

A replacement for the Mac's Cmd+Tab app switcher that only shows apps you can actually see.

The built-in switcher lists every running app. CmdFocus leaves out:

- apps you've hidden (Cmd+H)
- apps whose windows are all minimized or closed

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

## Setting it up

You need a Mac running macOS 26 or newer, and Xcode.

1. Open `CmdFocus.xcodeproj` in Xcode.
2. Press the Run button (or Cmd+R).
3. macOS will ask to let CmdFocus control your computer. Click **Open System Settings** and switch CmdFocus on under **Privacy & Security → Accessibility**.

That's it. The menu bar icon turns from a warning triangle into ⌘ when it's working.

### Why does it need Accessibility access?

That permission is what lets CmdFocus notice Cmd+Tab before macOS does. It doesn't read or record anything else you type.

## If it stops working

**After rebuilding the app**, macOS forgets the permission. To fix it:

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Select CmdFocus and click the **–** button to remove it.
3. Run the app again and switch it back on.

**If the normal switcher shows up instead**, CmdFocus isn't running or doesn't have permission. Check for the ⌘ icon in the menu bar.

## Good to know

- An app with windows on another desktop (Space) still shows up.
- The order is most recently used first. Right after CmdFocus starts, the order may be a little different from what you expect until you've switched apps a few times.
- If the app you're in has no windows, it won't be in the list.
