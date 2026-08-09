# Background mode and single-instance behavior

Parla is a single-instance application: the first process to start owns
the `io.github.trufae.Parla` D-Bus name, and every later invocation
forwards its command line to that primary instance and exits. This is
what lets a second `parla` (or a click on an `openpgp4fpr:` invite link)
raise the already-running window instead of starting a duplicate.

## Command line

### `parla`

Normal launch. Starts the application, connects to the Delta Chat
JSON-RPC server, and shows the main window. If an instance is already
running, its window is presented instead (on the current desktop, with
proper focus, via D-Bus activation).

### `parla --background` (`-b`)

Starts Parla as a background service, on Linux and other freedesktop
platforms. Everything a normal startup brings up is initialized — the
RPC server, the account event stream, desktop notifications, the D-Bus
name — but no window is presented. The process keeps running with no
window until explicitly terminated (quit from the tray menu, Ctrl+Q in
the window, or a signal).

While in background mode, closing the window only hides it; messages
keep arriving and notifications keep firing. Clicking a notification, or
running `parla` / `parla --show`, brings the window back.

If an instance is already running, `parla --background` is a no-op: the
services are already up and an open window is left alone.

This is useful for autostarting Parla with your session, e.g. with a
`~/.config/autostart/` entry whose `Exec` line is `parla --background`.

On macOS and Windows the flag is accepted but degrades to a normal
launch — the background/service pattern relies on freedesktop D-Bus
semantics that do not exist there.

### `parla --show` (`-s`)

Presents the main window. If an instance is already running (visible,
hidden in the tray, or started with `--background`), it is asked over
D-Bus to present its window. If no instance is running, this behaves
like a plain `parla` launch.

## D-Bus activation

The desktop entry sets `DBusActivatable=true` and a matching
`io.github.trufae.Parla.service` file is installed under
`share/dbus-1/services/`. Desktop shells that support it start Parla by
asking the session bus for the name (the service file runs
`parla --gapplication-service`) and then call the
`org.freedesktop.Application.Activate` or `Open` method, which gives
correct startup notification, focus stealing prevention, and
single-instance semantics for free.

Invite links (`x-scheme-handler/openpgp4fpr`) arrive through the `Open`
method on this path. GLib's GFile round-trip mangles such scheme-only
URIs (`openpgp4fpr:FPR#...` → `openpgp4fpr:///FPR%23...`), so the
application repairs that known damage before handing the link to the
SecureJoin flow; terminal invocations (`parla openpgp4fpr:...`) bypass
GFile entirely and arrive verbatim.

## Lifecycle notes

Application lifetime and window lifetime are decoupled: the process
stays alive while either a window exists, the "minimize to status bar"
tray hold is active, or the permanent background-mode hold taken by
`--background` is in place. Quitting (Ctrl+Q or the tray menu's Quit)
always terminates the process regardless of those holds.

## The tray on macOS

The freedesktop StatusNotifierItem has no watcher on macOS, so there the
"minimize to menu bar" option is backed by a native `NSStatusItem`
(`src/tray_macos.m`, compiled only on macOS; the SNI implementation in
`src/tray_icon.vala` is compiled only elsewhere). The menu mirrors the
GNOME one: Show/Hide, Notifications, Quit. While hidden, the app also
switches to the *accessory* activation policy — it leaves the Dock and
the Cmd-Tab switcher and exists only as the menu-bar icon, matching how
a closed window on GNOME lives only in the tray. Re-launching Parla
from the Dock, Launchpad, or Spotlight is routed to the running
instance and restores the window (LaunchServices reopen semantics stand
in for the D-Bus single-instance activation used on Linux).
