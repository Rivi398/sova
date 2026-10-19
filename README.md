<p align="center"><img src="Resources/AppIcon-1024.png" width="128" alt="Sova icon"></p>

<h1 align="center">Sova</h1>

<p align="center"><b>Keep your MacBook awake with the lid closed. One switch in the menu bar.</b><br>
Free and open source · Apple Silicon and Intel · macOS 13+ · <a href="README.ru.md">По-русски</a></p>

Close a MacBook without an external display and macOS goes to sleep: downloads stop, builds stall,
AI agents freeze mid-task. `caffeinate` only blocks *idle* sleep. `sudo pmset -a disablesleep 1`
works, but stays on until you remember to undo it, and a sleepless Mac in a bag gets hot.

Sova is that `pmset` command behind a switch, with the undo built in.

## Install

```bash
brew install --cask Rivi398/tap/sova
```

Or download `Sova-x.y.z.zip` from [Releases](https://github.com/Rivi398/sova/releases),
move `Sova.app` to Applications, and run once:

```bash
xattr -dr com.apple.quarantine /Applications/Sova.app
```

Sova isn't notarized by Apple (that takes a paid developer account), so without this macOS
refuses to open it. Homebrew does the same step for you.

## Use

Click the owl in the menu bar and flip **Stay awake with lid closed**.

- Owl with closed eyes: normal sleep.
- Green owl with open eyes: the Mac stays awake with the lid closed, on battery too.

The first time you turn it on, macOS asks for your password once (see below).

## Sleep always comes back

Sova turns sleep back on by itself when:

- you flip the switch off or quit Sova;
- the battery drops below a limit you choose (20% by default);
- the Mac gets too hot (macOS thermal state *serious* or *critical*);
- Sova crashes, is force-quit, or the Mac restarts: a small system guard checks every minute and
  at boot, and if sleep is off while Sova isn't running, it turns sleep back on.

## What the password is for

Changing sleep with the lid closed needs root. Instead of a resident root helper, Sova installs
two small files, once:

| File | What it does |
|---|---|
| `/etc/sudoers.d/sova` | lets your user run exactly `pmset -a disablesleep 0` and `pmset -a disablesleep 1` without a password. Nothing else. |
| `/Library/LaunchDaemons/ru.studiasok.sova.guard.plist` | the guard: at boot and every 60 s, if sleep is disabled and Sova isn't running, runs `pmset -a disablesleep 0`. |

Both are generated in [`Sources/Sova/System.swift`](Sources/Sova/System.swift); the sudoers file is
checked with `visudo` before it's installed. You can verify the rule yourself:
`sudo -n pmset -a disablesleep 0` works without a password, `sudo -n pmset -a sleep 0` doesn't.

Sova has no network access, analytics, or accounts.

## Uninstall

Menu → **Remove system settings…**, then drag Sova to the Trash.
With Homebrew: `brew uninstall --cask sova` removes everything.

By hand:

```bash
sudo pmset -a disablesleep 0
sudo launchctl bootout system/ru.studiasok.sova.guard
sudo rm /etc/sudoers.d/sova /Library/LaunchDaemons/ru.studiasok.sova.guard.plist
```

## Build from source

Needs only the Command Line Tools (`xcode-select --install`), no Xcode:

```bash
scripts/build.sh          # → dist/Sova.app and dist/Sova-<version>.zip
```

## License

MIT © 2026 Sergey Cheberko
