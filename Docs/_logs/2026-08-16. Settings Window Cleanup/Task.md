# Settings Window Cleanup

Make the Settings window look like a native macOS settings pane, and cut the three
things in it that are wrong or no longer earn their place: the animation folder picker,
a plugin status that is always a lie on launch, and a raw CoreBluetooth UUID shown to
the user.

## Decisions reached

- **The animation folder goes entirely.** It was a dev-era escape hatch from the Python
  era: point at a folder of GIFs and `AnimationLibrary.overrideFolder` prefers them over
  the bundled art. Art is now authored by `art/generate.py` and shipped inside the
  bundle, so nobody has a folder to point at. Remove the Settings section, the
  `animationFolder` `@AppStorage`, `animationFolderURL`, `AppModel`'s wiring (init and
  the per-tick re-read), `AnimationLibrary.overrideFolder` and the two override branches
  in `url(for:)`, plus the tests that cover them. Removing the UI alone would leave dead
  code that `periphery` flags.
  - The bundled `Animations/custom/` precedence **stays** — that is the art pipeline's
    hand-imported-art path, not the user override.
- **Plugin status is probed, not remembered.** `PluginInstaller.outcome` is initialised
  to `.notInstalled` on every launch and only ever mutated by `install()`/`uninstall()`,
  so Settings reads "Plugin not installed" until the user touches it. Fix by reading
  `~/.claude/plugins/installed_plugins.json` and looking for
  `claude-mascot@claude-mascot`. Chosen over `claude plugin list` because it is instant,
  spawns no process, and cannot fail because the `claude` binary is unreachable from a
  LaunchServices-launched app.
  - Probe on `PluginInstaller` init and again when the Settings window appears.
  - The install/uninstall buttons follow the probed state: offer **Install** when it is
    absent, **Uninstall** when present.
- **The device row shows connection, not identity.** Replace the raw per-host
  CoreBluetooth UUID with "Connected" / "Not connected" (and the transient
  scanning/connecting wording), driven by `appModel.bleClient.state`. Keep the Rescan
  action, which is what the row is actually for.
- **Native chrome throughout.** `.formStyle(.grouped)`, `LabeledContent` rows, real
  section headers, no hand-rolled `.padding(20)`, and a width that stops truncating
  button titles ("Reveal i…", "Bund…tions" in the current build).

## Approved layout

Wireframe **A** (see `Wireframe.canvas`): a single `Form` in `.formStyle(.grouped)`,
four sections in this order, window ~500pt wide:

| Section | Rows |
|---|---|
| General | Launch at login · Auto-connect |
| Panel | Brightness (slider + % readout) · Sleep after · Panel off after |
| Device | Connection status · **Rescan** |
| Plugin | Install status · **Install**/**Uninstall** · conditional re-register row |

B (tabbed panes) and C (Preferences + Status with indicator dots) were considered and
rejected: B adds navigation for five controls, C re-architects the information design
beyond what this cleanup is for.

## Out of scope

- `FirstRunView` — untouched.
- The menu bar menu and its status line.
- Any change to BLE, the art pipeline, the plugin itself, or the event policy.
- Letting the user pick a specific panel when several are in range; Rescan keeps its
  current forget-and-rediscover behaviour.

## Specs

- [[Menu Bar App]]
- [[Claude Code Plugin]]
