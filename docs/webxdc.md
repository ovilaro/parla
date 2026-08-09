# Webxdc apps (experimental)

[Webxdc](https://webxdc.org/) apps are tiny offline web apps (`.xdc` zip
archives) shared as Delta Chat attachments. Parla can run them in an
embedded [WebKitGTK](https://webkitgtk.org/) view, but the feature is **off
by default**: it adds WebKitGTK — a large dependency and a browser-sized
attack surface — so it will only be enabled once it has seen enough
testing.

## Building

```sh
make run WITH_WEBXDC=1     # mac and linux; needs webkitgtk-6.0 pkg-config
# or directly:
meson setup builddir -Dwebxdc=true
```

A plain `make` (or `-Dwebxdc=false`) reverts to the default build, which
does not link WebKitGTK at all.

## How it works

The whole feature lives in one file, `src/webxdc.vala`, compiled only when
the option is on; `src/webxdc_stub.vala` provides the same `Dc.Webxdc`
entry points as no-ops otherwise, so no other file needs conditional
compilation and linking stays trivial.

- Apps appear in the chat as a start button and in the media gallery under
  **Apps**; both call `Webxdc.open ()`, one window per app instance.
- Every window gets its own `WebKit.WebContext` with a custom `webxdc:`
  URI scheme. Files are extracted from the `.xdc` archive by deltachat
  core (`get_webxdc_blob` over jsonrpc) — Parla never unzips anything
  itself and serves nothing from disk.
- `webxdc.js` is the one synthetic file: it installs `window.webxdc` and
  bridges to Vala through a WebKit script message handler.
- Status updates flow through the core jsonrpc calls
  `send_webxdc_status_update` / `get_webxdc_status_updates`; incoming
  `WebxdcStatusUpdate` events are routed to the matching open window,
  and `WebxdcInstanceDeleted` closes it.

## Security boundaries

Webxdc's contract is that apps run **offline and sandboxed**; Parla
enforces it with GNOME/WebKit primitives:

- **No network.** The `WebKit.NetworkSession` is ephemeral (no cookies or
  cache on disk) and configured with a blackhole SOCKS proxy, so any
  `http(s)` request an app attempts dies before reaching the network.
  `webxdc:` content is served in-process and is unaffected.
- **No navigation escape.** `decide-policy` refuses any navigation or
  `window.open` outside the `webxdc:` scheme.
- **No filesystem.** All content comes from the archive via jsonrpc.
- **No persistence.** Ephemeral session: `localStorage` survives only as
  long as the window (a deliberate, safer deviation from the official
  client).
- Developer extras and modal dialogs are disabled.

## JS API exposed to apps

Only the core of the [official webxdc spec](https://webxdc.org/docs/spec/)
as used by the official Delta Chat clients — nothing else is injected:

| member | behaviour |
|---|---|
| `webxdc.selfAddr` | account address |
| `webxdc.selfName` | display name (falls back to the address) |
| `webxdc.sendUpdate(update, descr)` | `send_webxdc_status_update` |
| `webxdc.setUpdateListener(cb, serial)` | replays updates after `serial`, then live ones |

Optional spec extras (`sendToChat`, `importFiles`, `joinRealtimeChannel`)
are intentionally absent; apps must feature-detect them, and well-behaved
ones degrade gracefully.
