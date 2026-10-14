# CBS Flutter UX/UI — Visual catalog

## Purpose

Independent visual catalog of the reusable `cbs_flutter_ux` package.

The catalog displays the six public CBS widgets in one place and lets
a developer or a reviewer switch between 32 rendering scenarios
(design, appearance, width and simulated text scale x1 or x2). A
Device text scale, which follows the device settings, is also offered
and is not part of those 32 scenarios. It is the qualification
aid of the Visual Parts and presentation-state patterns of the package.

Independence from AMH-USR was verified by inspection of imports and dependencies; no dedicated automated non-coupling test exists.

The catalog belongs to `cbs-environment-framework`, not to AMH-USR. It
depends only on Flutter and on `cbs_flutter_ux` (`path: ../`): no
authentication, no backend and no AMH-USR service.

Everything in this directory is owned by the example. The package
`lib/` contains no catalog code, no demonstration text and no
demonstration callback.

## Architecture

- Framework: `packages/cbs_flutter_ux/`
- Catalog: `packages/cbs_flutter_ux/example/`
- Dependency: `cbs_flutter_ux` via `path: ../`
- Platform: Android only (`android/`); no Linux, Web or iOS project.

Application and catalog files (all under `lib/`):

- `main.dart` — `CbsUxShowcase`: the application. It builds the
  `MaterialApp` with the theme of the active scenario, the page scroll,
  the controls, the scenario summary and the preview. The active
  `CatalogScenario` is local state of this `StatefulWidget`: no state
  management dependency.
- `catalog/catalog_scenario.dart` — `CatalogScenario` and its four
  enums: `CatalogDesign`, `CatalogAppearance`, `CatalogWidth`,
  `CatalogTextScale`. `CatalogScenario.all` enumerates the 32
  combinations; `buildTheme()` builds the CBS `ThemeData`.
- `catalog/catalog_controls.dart` — `CatalogControls`: the four
  selection groups (wrapping `ChoiceChip`s). They are rendered outside
  the simulated viewport and keep the real device width and text scale.
- `catalog/catalog_preview_frame.dart` — `CatalogPreviewFrame`: the
  simulated viewport. It gives its child a tight width equal to the
  scenario width and a `MediaQuery` with the matching size and text
  scaler. When the frame is wider than the screen it scrolls
  horizontally.
- `catalog/catalog_entry.dart` — `CatalogEntry` (identifier, title,
  builder) and `CatalogSection` (the titled section that renders one
  entry).
- `catalog/catalog_entries.dart` — `catalogEntries`: the explicit,
  ordered list of the sections. There is no registry, composition
  engine or dynamic configuration.
- `catalog/catalog_demo.dart` — `CatalogDemo`: a labelled
  demonstration inside a section, identified by a stable `Key`; and
  `catalogDemoGap`, the vertical gap between demonstrations.
- `catalog/catalog_keys.dart` — `CatalogKeys`: the stable keys shared
  with the tests.
- `catalog/sections/` — one file per section (`buttons_section.dart`,
  `loading_section.dart`, `feedback_section.dart`,
  `state_panel_section.dart`, `retry_message_section.dart`,
  `section_heading_section.dart`, `application_states_section.dart`),
  `retry_demo.dart`, the retry demonstration shared by two sections,
  and, added in D03c-A.2, `dynamic_feedback_demo.dart` (shown by
  `feedback_section.dart`) and `dynamic_progress_demo.dart` (shown by
  `loading_section.dart`).

Tests (under `test/`): `showcase_test.dart` (the demonstration that
existed before the catalog, adapted), `catalog_scenario_test.dart`,
`catalog_preview_frame_test.dart`, `catalog_effective_theme_test.dart`,
`catalog_content_test.dart`, `catalog_qualification_demos_test.dart`
(dynamic feedback, loading without label, dynamic progress, Device text
scale; D03c-A.2) and the shared helpers `catalog_test_helpers.dart`.

## The six components

Each component has its own section and labelled demonstrations
(`CatalogDemo` identifiers in parentheses).

- `CbsButton` — enabled and disabled (`buttons-states`), long label
  (`buttons-long-label`), functional interaction with a visible press
  counter (`buttons-interaction`). The disabled button is wired to a
  counter that must stay at 0.
- `CbsLoadingIndicator` — indeterminate and determinate 60 %
  (`loading-states`), determinate bounds 0 % and 100 %
  (`loading-range`). Semantic labels are provided. For the manual
  Android / TalkBack qualification (D03c-A.2), two demonstrations are
  added: an indicator **without** `semanticLabel`, with no replacement
  label (`loading-no-label`), and a determinate indicator whose
  progress is set to 0, 25, 50, 75 or 100 % by buttons
  (`loading-progress`). The progress indicator keeps a constant
  `semanticLabel` ('Progress'); only its value changes.
- `CbsFeedbackMessage` — four types (`feedback-types`), `expand`
  false and true (`feedback-expand`), long message (`feedback-long`),
  semantic label (`feedback-semantic`). For the manual qualification,
  a message shown and hidden by two buttons (`feedback-dynamic`) lets a
  reviewer observe whether a screen reader announces its appearance.
- `CbsStatePanel` — representative content at full width
  (`state-panel-content`), parent limited to 200 px
  (`state-panel-constrained`).
- `CbsRetryMessage` — short message with a semantic label
  (`retry-short`), long message and long label (`retry-long`). The
  retry action is functional: the example counts the retry requests
  and shows the count below the message. Nothing is loaded.
- `CbsSectionHeading` — short title (`heading-short`), long title
  (`heading-long`), typographic hierarchy (`heading-hierarchy`). The
  gap below a heading is a `SizedBox` placed by the example, as a
  consumer would.

## The four application states

The section `application-states` shows the four presentation states
Loading, Empty, Error and Ready (`state-loading`, `state-empty`,
`state-error`, `state-ready`).

These states are compositions written by the example, as a consumer
would write them. They are not neutral Flutter content only: they use
CBS widgets.

- Loading: `CbsStatePanel` with `CbsLoadingIndicator` and a `Text`.
- Empty: `CbsStatePanel` with `CbsSectionHeading` and a `Text`.
- Error: `CbsRetryMessage` through the shared retry demonstration
  (functional retry, with a counter).
- Ready: `CbsSectionHeading`, `Text` items and a `CbsButton`.

The package provides no state controller, no state model and no widget
that switches between these four states. The texts, the spacing
between title and content and the retry callback belong to the example.

## The controls

Four controls select the active scenario. The catalog starts on
Essentials, Light, 320 px, text x1.

- Design: Essentials (`CbsTheme.essentials`, indigo) or Branded
  (`CbsTheme.branded`, teal, `buttonRadius: CbsRadius.lg`).
- Appearance: Light or Dark.
- Width: 320, 600, 840 or 1280 px (simulated width, logical pixels).
- Text scale: x1 or x2 (simulated, see Known limits), or Device. With
  Device the preview uses the `TextScaler` provided by `MediaQuery`,
  unchanged, so the font size chosen in the Android settings is
  applied. The line under the summary shows how a 14 sp font is
  rendered by the device and by the preview.

2 designs x 2 appearances x 4 widths x 2 simulated text scales (x1,
x2) = 32 scenarios (`CatalogScenario.all`). Device is not part of that
matrix because its result depends on the device settings; its 16
combinations are `CatalogScenario.allDeviceTextScale`.
The line under the controls (`CatalogScenario.summary`) shows the active
combination, for example `Essentials · Light · 320 px · Text x1`.

## Commands

Use the CBS Flutter toolchain 3.47.6. `flutter` is not assumed to be
on the `PATH`; the commands below use the absolute path of the CBS
toolchain. Run them from `packages/cbs_flutter_ux/example`.

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter pub get
    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze
    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

The package itself is qualified separately, from
`packages/cbs_flutter_ux`:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter analyze
    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter test

To run the catalog, an Android device or emulator is required. No
emulator is assumed to be available or running. List what Flutter can
see, then run on an Android device identifier:

    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter devices
    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter emulators
    ~/.cbs/toolchains/flutter/3.47.6/bin/flutter run -d <device-id> -t lib/main.dart

`flutter emulators --launch <emulator-id>` starts an existing Android
virtual device. `flutter devices` may also list a desktop device of the
host (for example Linux): this directory has no `linux/` or `web/`
project, so only an Android device is a valid target.

The tests are headless widget tests: they need no device and no
emulator.

## Add a section

The catalog is a plain list of sections. A new component or a new
demonstration does not need a new catalog engine, registry or
configuration mechanism.

1. Create `lib/catalog/sections/<name>_section.dart` with a widget
   (`StatelessWidget`, or `StatefulWidget` if a visible counter is
   needed). Build it from `CatalogDemo` blocks with stable identifiers,
   separated by `catalogDemoGap`.
2. Keep the texts, the labels, the demonstration content and the
   callbacks in the example. Never add them to
   `packages/cbs_flutter_ux/lib/`.
3. Append one `CatalogEntry(id:, title:, builder:)` to `catalogEntries`
   in `lib/catalog/catalog_entries.dart`. Existing identifiers and
   order stay unchanged.
4. If the section needs a new stable key, add it to `CatalogKeys`.
5. Update the tests:
   - the expected identifier list in the `catalog entries` group of
     `test/catalog_scenario_test.dart`;
   - the `_demoIds` list and a group for the new demonstrations in
     `test/catalog_content_test.dart`.
   Target a demonstration by `Key` (`inDemo`, `inSection`) rather than
   by global widget counts, and do not use `pumpAndSettle`: the
   indeterminate loading indicators animate forever. The 32-scenario
   matrix tests render every entry of `catalogEntries`, so the new
   section is checked for exceptions and overflow in all scenarios.
6. Run `flutter analyze` and `flutter test` in the example, then in
   the package.

Only add to the catalog the public widgets of `cbs_flutter_ux`. Business
workflows stay in the consuming applications.

## Known limits

Covered by D03b-C: standalone catalog; six components; four application
states; 32 scenarios; headless widget tests (no exception, no overflow
including 320 px with text x2, simulated width consistent with the
layout constraints, button and retry interactions, effective theme);
no dependency on AMH-USR services.

Not covered:

- MediaQuery is simulated partially (M3). Only `size` (the simulated
  width with the real device height) and `textScaler` are replaced.
  `padding` and `viewInsets` come from the real device and are not
  simulated for the chosen width. `orientation` is derived by Flutter
  from the simulated size and cannot be set independently.


- The x1 and x2 text scales are absolute (M5, CURRENT, unchanged).
  They are simulation values (`TextScaler.linear(1)` and
  `TextScaler.linear(2)`) that replace the text scaler of the preview.
  They do not combine with, and do not necessarily reflect, the system
  font size configured on the device. The Device mode (D03c-A.2) is the
  one that follows the system font size. The controls above the
  preview keep the real device text scale.
- The dynamic feedback, the indicator without label and the dynamic
  progress are observation aids. They add no `liveRegion` on purpose,
  and the indicator without label receives no replacement label: the
  CURRENT behaviour of the widgets is observed, not corrected. They do
  carry visible text of their own, which a screen reader reads as
  separate nodes and which a reviewer must take into account: a
  display counter (dynamic feedback), an explanatory sentence (no
  label) and, for the dynamic progress, a constant `semanticLabel`
  'Progress' and a "Progress: n %" readout. The headless tests read the Flutter
  semantics tree; what TalkBack announces and whether the Android font
  size changes the catalog on a device stay `NOT_VERIFIED` until
  observed on a device.
- The tests are headless widget tests: they are not proof of a real
  Android rendering.
- No Golden test exists, and none is generated.
- No TalkBack or VoiceOver validation has been performed.
- Only Android is generated; Linux and Web are not.
- No Android runtime run of the catalog is recorded by this
  documentation. Whether an emulator can be started is not a
  qualification.
- The color palette (`ColorScheme`) and the tokens have no dedicated
  visualization.
- A 2 x 2 side-by-side comparison of scenarios is not provided.

Deferred:

- To D03c: Golden tests, TalkBack and VoiceOver on devices,
  multi-device runtime. An Android run of the catalog is to be
  qualified separately.
- Until after E09: `CbsCard`. It is not published by the package and not
  shown in the catalog.

## Scope boundaries

- No AMH-USR business functionality.
- No IAM or backend integration.
- No modification of the AMH-USR application.
- No proof of independent-repository portability. Portability to
  another consuming repository was referred to historically as E07b-F
  and is not re-verified here.

## Evolution

Extend this catalog alongside reusable CBS UX/UI components.
Keep business-specific workflows in consuming applications.
