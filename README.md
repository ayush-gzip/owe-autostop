# owe-autostop

[Open Wallpaper Engine](https://openwallpaperengine.app/) for macOS keeps a scene wallpaper in memory while app windows hide it. With one scene on two displays, it used about 2.1 GB.

The "Stop (free memory)" setting in Playback does not free that memory. It hides the wallpaper window, but the scene stays loaded. The app's command `--control stop` unloads the scene. In a test, memory went from 2,281 MB to 426 MB.

owe-autostop is a small background tool. It sends these commands for you when windows hide the desktop.

## What it does

Every second, it reads the visible app windows on each display. A display is hidden when windows cover 85% or more of it. Windows side by side count together.

- **Every display hidden for 5 s:** it sends `stop`. All wallpapers unload.
- **A display visible again for 1 s:** it sends `play`. The wallpapers load again.
- **Some displays hidden for 5 s:** it closes the wallpaper on a hidden display, but only if no visible display shows the same wallpaper. The app shares one scene between displays, so closing a copy frees little memory.
- **A closed display visible again for 1 s:** it opens the same wallpaper on that display again.

It does nothing while the screen is locked or while Open Wallpaper Engine is not running. It never starts the app.

## Requirements

- macOS 14 or later
- Open Wallpaper Engine in `/Applications`
- Xcode Command Line Tools, for `swiftc` (`xcode-select --install`)

## Install

```sh
git clone https://github.com/ayush-gzip/owe-autostop.git
cd owe-autostop
./install.sh
```

The script builds the tool into `~/.local/share/owe-autostop/` and adds a LaunchAgent. The tool then starts at each login, and launchd starts it again if it stops.

## Check it

```sh
tail -f ~/Library/Logs/owe-autostop.log
```

The log shows one line for each stop, play, close, and reopen.

## Uninstall

```sh
launchctl bootout gui/$(id -u)/io.github.ayush-gzip.owe-autostop
rm ~/Library/LaunchAgents/io.github.ayush-gzip.owe-autostop.plist
rm -r ~/.local/share/owe-autostop
```

Before you uninstall, show the desktop on every display, so that the tool can reopen the wallpapers it closed.

## Limits

- Each resume loads the scene again, so expect a short delay and a CPU spike.
- If you stop the wallpapers by hand and then cover every display, the tool resumes them when a display shows again.
- The tool saves the displays it closed in `~/.local/share/owe-autostop/closed.json`. If the tool stops while a display is closed, it reopens that display at its next start. If you remove the tool first, set that display's wallpaper again in the app.
- A display that shows a playlist may get back only the wallpaper that was on screen when it closed, not the playlist. This is not tested.

Tested on macOS 27 with Open Wallpaper Engine 1.0.0-beta.7.

## License

MIT
