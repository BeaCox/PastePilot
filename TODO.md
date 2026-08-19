# PastePilot Roadmap

This file contains only open, actionable work, ordered by priority rather than
by a promised release date. Completed release history belongs in `CHANGELOG.md`.

## Product Principles

- Stay local-first: no telemetry, cloud dependency, or implicit network access.
  Link metadata remains explicit opt-in.
- Keep protected clipboard payloads encrypted at rest and unavailable to
  previews, actions, search indexes, logs, and external text files while locked.
- Preserve useful pasteboard representations only within strict type and size
  limits, and continue to ignore concealed or transient clipboard data before
  capture.
- Keep expensive capture, persistence, image, OCR, and enrichment work off the
  main actor while preserving cancellation and stale-result guards.
- Prefer native macOS controls and stable layouts; custom styling should clarify
  hierarchy without turning every surface into a card.

## Now — macOS UI Consistency

- [ ] Unify the About experience.
  - Make the application menu and menu-bar popover open the same About surface.
  - Prefer the standard macOS About panel; if the branded window remains,
    replace the system app-info command so there is still only one route.
  - Present the same localized title, version, build, and app identity from
    every entry point.
- [ ] Separate history selection from inline editing actions.
  - Keep keyboard selection and its highlight without permanently revealing
    stack, pin, and delete buttons on the selected row.
  - Reveal inline controls on pointer hover while retaining context-menu,
    keyboard, and VoiceOver access.
  - Keep trailing timestamps and shortcuts geometrically stable so selection
    changes do not make row text jump or truncate unnecessarily.
- [ ] Reduce persistent chrome in the history popover.
  - Remove the repeated accent-colored pin rail when the Pinned section already
    communicates state, or render passive pin state more quietly.
  - Keep only the most useful keyboard hints in the footer, such as Return to
    copy and Space to preview; move advanced shortcuts to menus or help.
  - Verify the 400-point popover in English and Simplified Chinese with item
    counts and an active paste stack.

## Next — Settings Polish

- [ ] Simplify settings hierarchy.
  - Reduce nested full-width rounded backgrounds, especially where a settings
    group already provides containment.
  - Preserve clear grouping with native spacing, dividers, `GroupBox`, or form
    conventions rather than adding another card for every subsection.
- [ ] Consolidate local plugin management controls.
  - Keep Import as the primary action and move folder, reload, example, and
    schema utilities into a compact management menu or row toolbar.
  - Ensure long Simplified Chinese labels do not create a two-row button wall.
- [ ] Use a conventional selection control for ignored applications.
  - Replace the orange eye/eye-slash state with a checkbox, switch, or checkmark
    whose selected meaning is unambiguous.
  - Keep whole-row activation, keyboard navigation, and VoiceOver state clear.
- [ ] Stabilize settings window geometry.
  - Use a fixed height or a narrower resizing range so switching between short
    and scrollable panes does not move the window dramatically.
  - Preserve scroll position where appropriate and verify every pane at the
    minimum supported display size.

## UI Verification

- [ ] Exercise the menu-bar popover, preview, sheets, About, welcome flow, and
  every settings pane in light, dark, and system appearances.
- [ ] Verify normal, hover, keyboard-selected, disabled, destructive, empty,
  loading, protected, and sensitive-content states.
- [ ] Run the focused UI/state tests, `make test`, `make app`, and
  `git diff --check` before marking this pass complete.

## Completed Baseline

PastePilot already includes high-fidelity clipboard replay, SQLite/FTS history,
metadata and saved searches, ordered pinned items, OCR and barcode analysis,
encrypted protected history, backup/restore, paste stack, App Intents, CLI
automation, export, safe custom actions, and declarative local action plugins.
See `CHANGELOG.md` for versioned milestones.
