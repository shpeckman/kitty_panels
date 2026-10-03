# AGENTS.md

kitty_panels is a Crystal shard for creating and managing kitty desktop panels
(layer-shell windows) through kitty's remote-control protocol. This file tells
coding agents how to work in this repository.

## Setup

- Crystal 1.21.0 or newer. No shard dependencies.
- Link libraries: `libgmp`, `libyaml`, `libssl`, `libpcre2`.
- This is a library: no binaries are built. Consumers add it to their `shard.yml`.

## Testing

Run the suite before you call a change done, and add or update specs with every
behaviour change.

| Command | What it runs |
|---|---|
| `make test` / `crystal spec` | All unit specs against the in-process fake kitty |

- `spec/support/fake_kitty.cr` is an in-process fake kitty you can script:
  `focus`, `blur`, `exit_command`, `adopt`, `fail`, `stalled`.
- Poll asynchronous effects with `eventually` from `spec/spec_helper.cr`; do not
  add fixed sleeps.

## Layout

| Path | Contents |
|---|---|
| `src/kitty_panels.cr` | Entry point, requires the whole shard |
| `src/kitty_panels/rc.cr` | `RC`: remote-control client and panel lifecycle (`launch_panel`, `close_panel`, `set_visibility`, `configure_panel`, `send_text`, `apply_overrides`, `live_panels`) |
| `src/kitty_panels/rc/` | `commands.cr` (typed rc command wrappers), `crypto.cr` (encrypted rc), `j.cr` (JSON helpers) |
| `src/kitty_panels/definition.cr` | `PanelDefinition`: panel settings model, validation, `to_os_panel_args` |
| `src/kitty_panels/wire.cr` | Choice enums; their dashed spellings are the JSON, YAML and API format |
| `src/kitty_panels/colors.cr` | X11 color name and hex parsing |
| `src/kitty_panels/engine.cr` | `Engine`: optional helper that spawns a managed hidden kitty with remote control enabled |
| `src/kitty_panels/config.cr` | `KittyPanels.load_definitions(path)` for `panels.yaml`-style files |

## Architecture rules

- **Apply to kitty, then report success.** `launch_panel` closes the window
  again if a step after the launch fails; follow that pattern for new
  multi-step operations.
- **kitty windows are found by the user variable `kitty_panels_name`.** Use
  `RC.panel_match`, never window ids, to address a panel.
- **Failures raise `RCError`** with kitty's own error message when there is one.

## Single sources of truth

Change these tables instead of adding parallel lists:

- **Panel settings:** `PanelDefinition::FIELDS` in `definition.cr`. One row
  gives a setting its kitty flag, its parser and its `configure` eligibility.
- **Choices:** the `Wire.define` enums in `wire.cr`. Their dashed spellings are
  the JSON, YAML and API format; never compare against string literals.
- **rc commands:** the wrappers and validation sets in `rc/commands.cr`.

## Code standards

- Every source file starts with a comment holding its own path, for example
  `# src/kitty_panels/rc.cr`. No other comments in code.
- Compiler-friendly, performance-focused, idiomatic Crystal. Prefer data-driven
  tables over repeated `case` branches.
- The public API (`KittyPanels::RC`, `KittyPanels::Engine`,
  `KittyPanels::PanelDefinition`, `KittyPanels.load_definitions`) must stay
  ergonomic.
- Deliver complete files: no stubs or placeholders.
- Do not add functionality that was not asked for.
- Never change the `version` field in `shard.yml`.
- Write everything in English.
