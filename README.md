# LidKeeper

A tiny macOS menu-bar app that keeps your Mac awake — including with the
**lid closed** (clamshell). Keep it awake indefinitely, for a
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
| `kIOPMAssertionTypePreventSystemSleep` | Stops the system sleeping, including when the lid is closed (it's what `caffeinate -s` does). Apple documents it as working on AC power only — see [Will closing the lid sleep?](#will-closing-the-lid-sleep) |
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

Apple documents the lid-closed assertion as working on AC power only, and other
settings or software on a Mac can also stop a closed lid from sleeping. Rather
than guess, LidKeeper asks macOS: while it's keeping the Mac awake, the menu
shows either "Closing the lid won't sleep this Mac" or a ⚠︎ warning that it
will. That's macOS's own `AppleClamshellCausesSleep` flag, which you can check
yourself:

```bash
ioreg -r -k AppleClamshellState -d 1 | grep AppleClamshellCausesSleep
```

`No` means closing the lid won't sleep the Mac right now, for whatever reason —
not necessarily because of LidKeeper. If it still says `No` after you quit
LidKeeper, something else is keeping a closed lid awake, and LidKeeper's
settings (including Auto's battery rule) can't change that. A closed MacBook
that stays awake keeps using battery and can get warm in a bag.

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

Click the menu-bar cup icon (it's filled while the Mac is being kept awake):

- **Keep Awake / Let It Sleep** — toggle staying awake indefinitely.
- **Keep Awake For ▸** — 15 min, 30 min, 1 / 2 / 5 hours, or until you turn it off.
- **Auto: While Claude Code Works** — see Auto mode above.
- **Auto Settings ▸** — how long to stay awake after Claude Code goes quiet, and what to do on battery.
- **Also Keep Screen On** — additionally prevent the display from sleeping.
- **Start at Login** — open LidKeeper automatically when you log in.
- The header line shows the current state and why.
- While it's keeping the Mac awake, a line near the bottom says whether closing the lid will sleep the Mac.

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

- **Lid closed:** whether a closed Mac stays awake depends on whether it's
  plugged in, and on the Mac's own settings and software. The menu shows what
  macOS reports (see [Will closing the lid sleep?](#will-closing-the-lid-sleep)).
- Auto watches `~/.claude/projects`. If you've moved Claude Code's config with
  `CLAUDE_CONFIG_DIR`, Auto won't see its activity.
- Other apps can hold sleep assertions of their own (the Claude desktop app,
  for example), so the Mac may stay awake even when LidKeeper lets go. Check
  with `pmset -g assertions`.
- LidKeeper only *prevents sleep*; it doesn't change any system power settings,
  so quitting it (or letting a timer expire) always returns your Mac to its
  normal behaviour.

## Project layout

```
LidKeeper/
├── Package.swift
├── Scripts/make-app.sh                 # bundle into LidKeeper.app
└── Sources/LidKeeper/
    ├── main.swift                      # entry point (menu-bar-only app)
    ├── AppDelegate.swift               # lifecycle + launch flags
    ├── PowerAssertionManager.swift     # IOKit power assertions
    ├── PowerSource.swift               # AC vs battery, charge level
    ├── Lid.swift                       # what macOS says closing the lid will do
    ├── ClaudeCodeActivity.swift        # last Claude Code transcript write
    ├── AutoKeepAwake.swift             # Auto mode rules + 15 s checks
    ├── StartAtLogin.swift              # login item (SMAppService)
    └── StatusMenuController.swift      # menu-bar item + menu
```
