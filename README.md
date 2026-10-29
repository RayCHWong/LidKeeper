# LidKeeper

A tiny macOS menu-bar app that keeps your Mac awake — including with the
**lid closed** when it's plugged in, or on battery too if you install its
[root helper](#keep-awake-on-battery). Keep it awake indefinitely, for a
set time, or turn on **Auto** to keep it awake only while Claude Code is
working, pausing when the battery gets low. No Dock icon, no window; it lives
quietly in the menu bar.

This is an **original, clean-room implementation** written from scratch on top
of Apple's public power-management APIs. It is not derived from, and shares no
code with, any other application.

## How it works

macOS exposes *power assertions* through the IOKit framework. While keeping the
Mac awake, LidKeeper holds:

| Assertion type | Effect |
| --- | --- |
| `kIOPMAssertionTypePreventSystemSleep` | Keeps the Mac running when the lid is closed (it's what `caffeinate -s` does) — on AC power only; macOS ignores it on battery. See [Will closing the lid sleep?](#will-closing-the-lid-sleep) |
| `kIOPMAssertionTypePreventUserIdleSystemSleep` | Stops idle sleep, and is documented to work **on battery** too (`caffeinate -i`). |
| `kIOPMAssertionTypePreventUserIdleDisplaySleep` | Optional. Also keeps the display awake. Toggled by "Also Keep Screen On". |

They're created with `IOPMAssertionCreateWithName` and released with
`IOPMAssertionRelease`; macOS also drops them automatically if the app quits
or crashes. Battery state comes from `IOPSCopyPowerSourcesInfo`.

You can see the live assertions yourself while the app is active:

```bash
pmset -g assertions | grep LidKeeper
```

## Will closing the lid sleep?

It depends on whether the Mac is plugged in. While LidKeeper is keeping the Mac
awake, a line in the menu says what closing the lid will do right now:

| Menu line | What happens when the lid closes |
| --- | --- |
| Closing the lid turns off the screen; this Mac keeps running | You're on AC power. macOS starts lid sleep, but LidKeeper's `PreventSystemSleep` assertion turns it into *dark wake*: the screen turns off (and locks, if you've set that up), but the Mac keeps running. |
| ⚠︎ On battery, closing the lid will sleep this Mac | macOS ignores that assertion on battery, as Apple documents, so the Mac really sleeps. |
| Closing the lid won't sleep this Mac | macOS itself won't start lid sleep right now, or sleep is turned off system-wide — either way, not because of LidKeeper. |
| ⚠︎ Closing the lid will sleep this Mac | LidKeeper couldn't take its assertion (rare), so it can't keep a closed Mac running. |

On battery, assertions alone can't keep a closed Mac running. Getting around
macOS there means turning sleep off system-wide, which needs administrator
rights — **Also Keep Awake on Battery** does exactly that, through a small root
helper you install once. It's off until you turn it on; see
[Keep Awake on Battery](#keep-awake-on-battery).

The menu combines what macOS reports with the power source. macOS's own
`AppleClamshellCausesSleep` flag only says whether closing the lid starts lid
sleep; it doesn't count LidKeeper's assertion, so it can say `Yes` even when a
plugged-in Mac will keep running. You can check it, and whether sleep is off
system-wide, yourself:

```bash
ioreg -r -k AppleClamshellState -d 1 | grep -E 'AppleClamshellCausesSleep|SleepDisabled'
```

To see what actually happened after you close and reopen the lid:

```bash
pmset -g log | grep "Clamshell Sleep" | tail -n 1
```

`Entering DarkWake state` means the Mac kept running; `Entering Sleep state`
means it slept. A closed MacBook that keeps running still uses power and can
get warm in a bag.

## Keep Awake on Battery

Power assertions can't keep a closed lid awake on battery — macOS ignores
`PreventSystemSleep` there, as Apple documents (`man caffeinate`). The one
switch that works is `pmset disablesleep`, which turns sleep off system-wide
and needs root. **Also Keep Awake on Battery** in the menu uses it, and only
while LidKeeper is keeping the Mac awake.

The first time you turn it on, LidKeeper explains what it's about to do and
asks for an administrator password through the standard macOS prompt. Two
files go in:

| File | Owner / mode | What it is |
| --- | --- | --- |
| `/usr/local/libexec/lidkeeper-helper` | `root:wheel` `0755` | A 40-line `/bin/sh` script. It takes one argument — `on`, `off` or `status` — and runs `pmset -a disablesleep 1/0`, then reports back what macOS actually did. |
| `/etc/sudoers.d/lidkeeper` | `root:wheel` `0440` | Lets **your user only** run that helper, with exactly those three arguments, without a password. |

That's the whole of LidKeeper's root surface: one setting, three fixed
commands. The app itself keeps running as you, and calls the helper with
`sudo -n` (never prompting, so it fails cleanly rather than hanging).

A few deliberate choices:

- **It's held, not set.** Sleep goes off when keep-awake turns on and back on
  when it turns off — including when a timer expires, when Auto decides Claude
  Code has gone quiet, and when you quit.
- **A crash can't leave your Mac awake forever.** LidKeeper remembers that it
  turned sleep off, and the next launch puts it back.
- **It won't undo someone else's setting.** If sleep was already off when
  LidKeeper started, it leaves it alone.
- **The installer refuses an unsafe install** — it won't put a root-run script
  anywhere that isn't root-owned and root-writable-only, and `visudo` checks
  the rule before it's moved into place, so a bad file can't lock you out of
  `sudo`.

Install or remove it from a terminal instead, if you'd rather:

```bash
sudo bash Scripts/install-helper.sh install
sudo bash Scripts/install-helper.sh uninstall
```

**Remove the Root Helper…** in the menu does the same as `uninstall`: it turns
sleep back on and takes both files away.

## Auto mode (Claude Code + battery)

**Auto: While Claude Code Works** keeps the Mac awake only while a Claude Code
session is doing something, and lets it sleep once Claude Code goes quiet. It
checks every 15 seconds:

1. **Is Claude Code working?** Every Claude Code front end (terminal, IDE,
   desktop app) writes session transcripts to `~/.claude/projects/` as it
   works. Auto looks at when those files were last written — it never reads
   their contents. A session counts as working until it has been quiet for the
   chosen period (default 15 minutes), which covers long thinking and slow
   commands that don't write to the transcript.
2. **Is the battery OK?** On AC power, always. On battery, Auto pauses below
   20% by default (or below 50%, or whenever unplugged — your choice).

Change both under **Auto Settings**. Auto is remembered across launches, so
with Start at Login it's back on after a restart.

Picking **Keep Awake** or **Keep Awake For** switches to manual mode and turns
Auto off; turn Auto back on from the menu.

> Auto deliberately doesn't count "a command Claude started is still running"
> as activity: a hung command or a dev server left in the background would keep
> the Mac awake forever. If Claude runs a long job in the background, choose
> the 1-hour quiet period or use Keep Awake For.

## Build & run

Requires the Swift toolchain (Xcode or the Command Line Tools — `xcode-select
--install`). macOS 13+.

Quick run from a terminal:

```bash
swift run
```

Build a double-clickable, menu-bar-only `.app`:

```bash
bash Scripts/make-app.sh
open build/LidKeeper.app
```

To install or update it (quit LidKeeper first if it's running):

```bash
ditto build/LidKeeper.app /Applications/LidKeeper.app
```

> First launch of an ad-hoc-signed app: if Gatekeeper blocks it, right-click the
> app → **Open**, or allow it under **System Settings → Privacy & Security**.

## Using it

Click the laptop in the menu bar. It's just an outline while sleep is allowed,
and shows the light from its screen while the Mac is being kept awake:

- **Keep Awake / Let It Sleep** — toggle staying awake indefinitely.
- **Keep Awake For ▸** — 15 min, 30 min, 1 / 2 / 5 hours, or until you turn it off.
- **Auto: While Claude Code Works** — see Auto mode above.
- **Auto Settings ▸** — how long to stay awake after Claude Code goes quiet, and what to do on battery.
- **Also Keep Screen On** — additionally prevent the display from sleeping.
- **Also Keep Awake on Battery** — keep a closed lid awake on battery too. Needs a one-time administrator password; see [Keep Awake on Battery](#keep-awake-on-battery).
- **Start at Login** — open LidKeeper automatically when you log in.
- **Remove the Root Helper…** — shown once the helper is installed; takes it away again.
- The header line shows the current state and why.
- While it's keeping the Mac awake, a line near the bottom says what closing the lid will do — keep running on AC power, or sleep on battery.

### Command-line flags

Each does what the matching menu item does, for scripts:

```bash
LidKeeper --keep-awake        # manual keep-awake (turns Auto off)
LidKeeper --keep-screen-on    # same, and keep the display on
LidKeeper --auto              # turn Auto on (remembered)
LidKeeper --start-at-login    # open at login; prints the result
```

## Start at login

Use **Start at Login** in the menu. It registers LidKeeper with macOS
(`SMAppService`), so it shows under **System Settings → General → Login Items**,
where you can also turn it off. Install the app in /Applications first, so the
login item points at a copy that stays put — `make-app.sh` replaces
`build/LidKeeper.app` on every build.

## Limitations

- **Lid closed:** with assertions alone, a closed Mac only keeps running on AC
  power. On battery it takes **Also Keep Awake on Battery** and its root helper
  (see [Will closing the lid sleep?](#will-closing-the-lid-sleep)).
- **Keep Awake on Battery is a blunt switch.** `pmset disablesleep` turns sleep
  off for the whole system, not just for a closed lid, and not just on battery.
  LidKeeper only holds it while keep-awake is on, but while it's held, nothing
  idle-sleeps.
- Auto watches `~/.claude/projects`. If you've moved Claude Code's config with
  `CLAUDE_CONFIG_DIR`, Auto won't see its activity.
- Other apps can hold sleep assertions of their own (the Claude desktop app,
  for example), so the Mac may stay awake even when LidKeeper lets go. Check
  with `pmset -g assertions`.
- Unless you turn on **Also Keep Awake on Battery**, LidKeeper only *prevents
  sleep* and changes no system power settings — quitting it (or letting a timer
  expire) always returns your Mac to its normal behaviour. With that option on,
  the one setting it changes is put back the same way.

## Project layout

```
LidKeeper/
├── Package.swift
├── Design/logo-artwork.png             # the original logo the code is traced from
├── Scripts/
│   ├── make-app.sh                     # bundle into LidKeeper.app
│   ├── install-helper.sh               # install/remove the root helper
│   └── lidkeeper-helper                # the helper itself (runs as root)
└── Sources/
    ├── LidKeeper/
    │   ├── main.swift                  # entry point (menu-bar-only app)
    │   ├── AppDelegate.swift           # lifecycle + launch flags
    │   ├── PowerAssertionManager.swift # IOKit power assertions
    │   ├── PowerSource.swift           # AC vs battery, charge level
    │   ├── Lid.swift                   # what closing the lid will do
    │   ├── SleepSettings.swift         # client of the root helper
    │   ├── ClaudeCodeActivity.swift    # last Claude Code transcript write
    │   ├── AutoKeepAwake.swift         # Auto mode rules + 15 s checks
    │   ├── StartAtLogin.swift          # login item (SMAppService)
    │   └── StatusMenuController.swift  # menu-bar item + menu
    ├── LidKeeperArt/Logo.swift         # the logo: app icon + menu-bar glyph
    └── make-icon/main.swift            # renders the icon for make-app.sh
```

The logo is drawn in code rather than shipped as images, so the app icon and
the one-tone menu-bar glyph share one design and stay sharp at every size.
`make-app.sh` renders the icon at each size macOS wants and packs it into
`AppIcon.icns` with `iconutil`.

## License

LidKeeper is released under the [MIT License](LICENSE).
