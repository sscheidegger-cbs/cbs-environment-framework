import 'package:flutter/rendering.dart';

import 'dart:math' as math;
import 'dart:ui' show SemanticsAction, Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';
import 'support/cbs_test_matrix.dart';

const double _epsilon = 0.001;

const CbsCategoryOption<String> _musique = CbsCategoryOption<String>(
  value: 'musique',
  label: 'Musique',
);
const CbsCategoryOption<String> _sport = CbsCategoryOption<String>(
  value: 'sport',
  label: 'Sport',
);
const CbsCategoryOption<String> _cinema = CbsCategoryOption<String>(
  value: 'cinema',
  label: 'Cinéma',
);
const CbsCategoryOption<String> _theatre = CbsCategoryOption<String>(
  value: 'theatre',
  label: 'Théâtre',
);

const List<CbsCategoryOption<String>> _options = [
  _musique,
  _sport,
  _cinema,
  _theatre,
];

const String _longLabel =
    'Une catégorie au libellé volontairement très long qui dépasse largement '
    'la largeur d’un petit écran et doit rester entièrement lisible';

/// Eight categories, one of them with a very long label: wider than every
/// tested viewport width.
const List<CbsCategoryOption<String>> _manyOptions = [
  _musique,
  _sport,
  _cinema,
  _theatre,
  CbsCategoryOption<String>(value: 'danse', label: 'Danse'),
  CbsCategoryOption<String>(value: 'long', label: _longLabel),
  CbsCategoryOption<String>(value: 'expositions', label: 'Expositions'),
  CbsCategoryOption<String>(value: 'gastronomie', label: 'Gastronomie'),
];

/// Same categories as [_options], the second one being disabled.
const List<CbsCategoryOption<String>> _optionsWithDisabled = [
  _musique,
  CbsCategoryOption<String>(value: 'sport', label: 'Sport', enabled: false),
  _cinema,
];

enum _Kind { first, second, third }

/// Parent of the selector: owns the selection, as an application would, and
/// records every selection reported by the selector.
class _Host extends StatefulWidget {
  const _Host({
    required this.options,
    this.initial = const {},
    this.mode = CbsCategorySelectionMode.single,
    this.reported,
  });

  final List<CbsCategoryOption<String>> options;
  final Set<String> initial;
  final CbsCategorySelectionMode mode;
  final List<Set<String>>? reported;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  late Set<String> selected = widget.initial;

  @override
  Widget build(BuildContext context) {
    return CbsCategorySelector<String>(
      options: widget.options,
      selectedValues: selected,
      mode: widget.mode,
      onSelectionChanged: (value) {
        widget.reported?.add(value);
        setState(() => selected = value);
      },
    );
  }
}

/// Selector without a parent state: the selection never changes by itself.
Widget _selector({
  required ValueChanged<Set<String>>? onChanged,
  List<CbsCategoryOption<String>> options = _options,
  Set<String> selected = const {},
  CbsCategorySelectionMode mode = CbsCategorySelectionMode.single,
}) {
  return CbsCategorySelector<String>(
    options: options,
    selectedValues: selected,
    onSelectionChanged: onChanged,
    mode: mode,
  );
}

Finder get _anyChip => find.byWidgetPredicate(
  (widget) => widget is ChoiceChip || widget is FilterChip,
);

/// The chip (a [ChoiceChip] or a [FilterChip]) showing [label].
Finder _chip(String label) =>
    find.ancestor(of: find.text(label), matching: _anyChip);

Finder get _selectorFinder => find.byType(CbsCategorySelector<String>);

Finder get _scrollable =>
    find.descendant(of: _selectorFinder, matching: find.byType(Scrollable));

bool _isSelected(WidgetTester tester, String label) {
  final chip = tester.widget(_chip(label));
  return chip is ChoiceChip ? chip.selected : (chip as FilterChip).selected;
}

ValueChanged<bool>? _onSelectedOf(WidgetTester tester, String label) {
  final chip = tester.widget(_chip(label));
  return chip is ChoiceChip ? chip.onSelected : (chip as FilterChip).onSelected;
}

Future<void> _tap(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await tester.pump();
}

Future<void> _tab(WidgetTester tester, {bool shift = false}) async {
  if (shift) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (shift) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.pump();
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pump();
}

/// Whether the primary focus is inside the chip showing [label].
bool _hasFocus(WidgetTester tester, String label) =>
    hasPrimaryFocusWithin(tester, _chip(label));

/// Style of the text drawn by the chip showing [label].
TextStyle? _labelStyle(WidgetTester tester, String label) {
  final paragraph = tester.widget<RichText>(
    find.descendant(of: _chip(label), matching: find.byType(RichText)).first,
  );
  return paragraph.text.style;
}

double _maxScrollExtent(WidgetTester tester) =>
    tester.state<ScrollableState>(_scrollable).position.maxScrollExtent;

double _scrollOffset(WidgetTester tester) =>
    tester.state<ScrollableState>(_scrollable).position.pixels;

/// Labels of the buttons, in the order of the simulated accessibility
/// traversal.
List<String> _buttonLabels(WidgetTester tester) => [
  for (final node in tester.semantics.simulatedAccessibilityTraversal())
    if (node.flagsCollection.isButton) node.label,
];

void main() {
  group('public API', () {
    test('requires the options, the selection and the callback', () {
      const selector = CbsCategorySelector<String>(
        options: [],
        selectedValues: {},
        onSelectionChanged: null,
      );

      expect(selector.options, isEmpty);
      expect(selector.selectedValues, isEmpty);
      expect(selector.onSelectionChanged, isNull);
      expect(selector.key, isNull);
      expect(selector, isA<StatelessWidget>());
    });

    test('defaults to the single selection mode', () {
      const selector = CbsCategorySelector<String>(
        options: [_musique],
        selectedValues: {'musique'},
        onSelectionChanged: null,
      );

      expect(selector.mode, CbsCategorySelectionMode.single);
    });

    test('accepts a key and a mode', () {
      final calls = <Set<String>>[];
      final selector = CbsCategorySelector<String>(
        key: const ValueKey('selector'),
        options: _options,
        selectedValues: const {'sport'},
        onSelectionChanged: calls.add,
        mode: CbsCategorySelectionMode.multiple,
      );

      expect(selector.key, const ValueKey('selector'));
      expect(selector.options, _options);
      expect(selector.selectedValues, {'sport'});
      expect(selector.mode, CbsCategorySelectionMode.multiple);
      selector.onSelectionChanged!({'musique'});
      expect(calls, [
        {'musique'},
      ]);
    });

    test('lists the selection modes in order', () {
      expect(CbsCategorySelectionMode.values, [
        CbsCategorySelectionMode.single,
        CbsCategorySelectionMode.multiple,
      ]);
    });

    test('an option requires a value and a label and defaults the rest', () {
      const option = CbsCategoryOption<int>(value: 1, label: 'Un');

      expect(option.value, 1);
      expect(option.label, 'Un');
      expect(option.enabled, isTrue);
      expect(option.semanticLabel, isNull);
    });

    test('an option accepts enabled and semanticLabel', () {
      const option = CbsCategoryOption<String>(
        value: 'a',
        label: 'A',
        enabled: false,
        semanticLabel: 'Catégorie A',
      );

      expect(option.enabled, isFalse);
      expect(option.semanticLabel, 'Catégorie A');
    });

    testWidgets('works with any value type: an enum', (tester) async {
      final reported = <Set<_Kind>>[];
      await pumpCbs(
        tester,
        child: CbsCategorySelector<_Kind>(
          options: const [
            CbsCategoryOption<_Kind>(value: _Kind.first, label: 'Premier'),
            CbsCategoryOption<_Kind>(value: _Kind.second, label: 'Deuxième'),
            CbsCategoryOption<_Kind>(value: _Kind.third, label: 'Troisième'),
          ],
          selectedValues: const {_Kind.first},
          onSelectionChanged: reported.add,
          mode: CbsCategorySelectionMode.multiple,
        ),
      );

      await _tap(tester, 'Deuxième');

      expect(reported, [
        {_Kind.first, _Kind.second},
      ]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('works with any value type: an int', (tester) async {
      final reported = <Set<int>>[];
      await pumpCbs(
        tester,
        child: CbsCategorySelector<int>(
          options: const [
            CbsCategoryOption<int>(value: 1, label: 'Un'),
            CbsCategoryOption<int>(value: 2, label: 'Deux'),
          ],
          selectedValues: const {1},
          onSelectionChanged: reported.add,
        ),
      );

      await _tap(tester, 'Deux');

      expect(reported, [
        {2},
      ]);
    });
  });

  group('native Flutter widgets', () {
    testWidgets('the single mode builds one ChoiceChip per option', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: _selector(onChanged: (_) {}, selected: const {'sport'}),
      );

      expect(find.byType(ChoiceChip), findsNWidgets(_options.length));
      expect(find.byType(FilterChip), findsNothing);
      expect(find.byType(InputChip), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('the multiple mode builds one FilterChip per option', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: _selector(
          onChanged: (_) {},
          selected: const {'sport'},
          mode: CbsCategorySelectionMode.multiple,
        ),
      );

      expect(find.byType(FilterChip), findsNWidgets(_options.length));
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(InputChip), findsNothing);
      expect(find.byType(ActionChip), findsNothing);
    });

    testWidgets('the chips show the labels of the options, as texts', (
      tester,
    ) async {
      await pumpCbs(tester, child: _selector(onChanged: (_) {}));

      for (final option in _options) {
        expect(find.text(option.label), findsOneWidget, reason: option.label);
      }
    });

    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('overrides no visual property of the chips: ${mode.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            selected: const {'sport'},
            mode: mode,
          ),
        );

        for (final option in _options) {
          // ChoiceChip and FilterChip declare the same properties.
          final dynamic chip = tester.widget(_chip(option.label));
          final overrides = <String, Object?>{
            'labelStyle': chip.labelStyle,
            'labelPadding': chip.labelPadding,
            'shape': chip.shape,
            'side': chip.side,
            'color': chip.color,
            'backgroundColor': chip.backgroundColor,
            'padding': chip.padding,
            'visualDensity': chip.visualDensity,
            'materialTapTargetSize': chip.materialTapTargetSize,
            'elevation': chip.elevation,
            'shadowColor': chip.shadowColor,
            'surfaceTintColor': chip.surfaceTintColor,
            'selectedColor': chip.selectedColor,
            'disabledColor': chip.disabledColor,
            'pressElevation': chip.pressElevation,
            'showCheckmark': chip.showCheckmark,
            'checkmarkColor': chip.checkmarkColor,
          };

          expect(
            [
              for (final entry in overrides.entries)
                if (entry.value != null) entry.key,
            ],
            isEmpty,
            reason: '${mode.name} ${option.label}',
          );
        }
      });
    }
  });

  group('single selection', () {
    testWidgets('selects a category from an empty selection', (tester) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(options: _options, reported: reported),
      );

      await _tap(tester, 'Sport');

      expect(reported, [
        {'sport'},
      ]);
      expect(_isSelected(tester, 'Sport'), isTrue);
      for (final label in ['Musique', 'Cinéma', 'Théâtre']) {
        expect(_isSelected(tester, label), isFalse, reason: label);
      }
    });

    testWidgets('selecting another category replaces the previous one', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(
          options: _options,
          initial: const {'musique'},
          reported: reported,
        ),
      );
      expect(_isSelected(tester, 'Musique'), isTrue);

      await _tap(tester, 'Cinéma');

      expect(reported, [
        {'cinema'},
      ]);
      expect(_isSelected(tester, 'Musique'), isFalse);
      expect(_isSelected(tester, 'Cinéma'), isTrue);
      expect(
        [
          for (final option in _options)
            if (_isSelected(tester, option.label)) option.label,
        ],
        ['Cinéma'],
      );
    });

    testWidgets('a selected category stays selected when activated again', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(
          options: _options,
          initial: const {'sport'},
          reported: reported,
        ),
      );

      await _tap(tester, 'Sport');
      await _tap(tester, 'Sport');

      expect(_isSelected(tester, 'Sport'), isTrue);
      // Nothing changed: nothing is reported.
      expect(reported, isEmpty);
    });

    testWidgets('a chain of selections always keeps exactly one category', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(options: _options, reported: reported),
      );

      await _tap(tester, 'Musique');
      await _tap(tester, 'Théâtre');
      await _tap(tester, 'Théâtre');
      await _tap(tester, 'Sport');

      expect(reported, [
        {'musique'},
        {'theatre'},
        {'sport'},
      ]);
      expect(_isSelected(tester, 'Sport'), isTrue);
    });

    testWidgets('an inconsistent selection is shown, then normalized', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(
          options: _options,
          initial: const {'musique', 'sport'},
          reported: reported,
        ),
      );

      // The parent is the source of truth: both are shown as selected.
      expect(_isSelected(tester, 'Musique'), isTrue);
      expect(_isSelected(tester, 'Sport'), isTrue);

      await _tap(tester, 'Sport');

      expect(reported, [
        {'sport'},
      ]);
      expect(_isSelected(tester, 'Musique'), isFalse);
      expect(_isSelected(tester, 'Sport'), isTrue);
    });
  });

  group('multiple selection', () {
    const mode = CbsCategorySelectionMode.multiple;

    testWidgets('adds categories to the selection', (tester) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(options: _options, mode: mode, reported: reported),
      );

      await _tap(tester, 'Sport');
      await _tap(tester, 'Théâtre');

      expect(reported, [
        {'sport'},
        {'sport', 'theatre'},
      ]);
      expect(_isSelected(tester, 'Sport'), isTrue);
      expect(_isSelected(tester, 'Théâtre'), isTrue);
      expect(_isSelected(tester, 'Musique'), isFalse);
      expect(_isSelected(tester, 'Cinéma'), isFalse);
    });

    testWidgets('removes categories, down to an empty selection', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(
          options: _options,
          mode: mode,
          initial: const {'musique', 'sport'},
          reported: reported,
        ),
      );

      await _tap(tester, 'Musique');
      await _tap(tester, 'Sport');

      expect(reported, [
        {'sport'},
        <String>{},
      ]);
      for (final option in _options) {
        expect(_isSelected(tester, option.label), isFalse);
      }
    });

    testWidgets('toggles a category on and off', (tester) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(options: _options, mode: mode, reported: reported),
      );

      await _tap(tester, 'Cinéma');
      expect(_isSelected(tester, 'Cinéma'), isTrue);
      await _tap(tester, 'Cinéma');
      expect(_isSelected(tester, 'Cinéma'), isFalse);

      expect(reported, [
        {'cinema'},
        <String>{},
      ]);
    });

    testWidgets('keeps the values that match no option', (tester) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _Host(
          options: _options,
          mode: mode,
          initial: const {'inconnue', 'sport'},
          reported: reported,
        ),
      );

      await _tap(tester, 'Musique');

      expect(reported, [
        {'inconnue', 'sport', 'musique'},
      ]);
    });

    testWidgets('reports a new set and never mutates selectedValues', (
      tester,
    ) async {
      const current = {'sport'};
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        child: _selector(
          onChanged: reported.add,
          selected: current,
          mode: mode,
        ),
      );

      await _tap(tester, 'Musique');
      await _tap(tester, 'Sport');

      // `current` is a constant set: mutating it would throw.
      expect(tester.takeException(), isNull);
      expect(current, {'sport'});
      expect(reported, [
        {'sport', 'musique'},
        <String>{},
      ]);
      expect(reported.first, isNot(same(current)));
    });
  });

  group('controlled by the parent', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('shows only what selectedValues says: ${mode.name}', (
        tester,
      ) async {
        final reported = <Set<String>>[];
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: reported.add,
            selected: const {'musique'},
            mode: mode,
          ),
        );

        await _tap(tester, 'Cinéma');

        // The callback receives the new selection...
        expect(reported, hasLength(1));
        expect(reported.single, contains('cinema'));
        // ...but the parent did not apply it: the display is unchanged.
        expect(_isSelected(tester, 'Cinéma'), isFalse);
        expect(_isSelected(tester, 'Musique'), isTrue);

        // The same activation reports the same selection again.
        await _tap(tester, 'Cinéma');
        expect(reported, hasLength(2));
        expect(reported.last, reported.first);
      });

      testWidgets('follows a new selectedValues: ${mode.name}', (tester) async {
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            selected: const {'musique'},
            mode: mode,
          ),
        );
        expect(_isSelected(tester, 'Musique'), isTrue);
        expect(_isSelected(tester, 'Cinéma'), isFalse);

        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            selected: const {'cinema'},
            mode: mode,
          ),
        );

        expect(_isSelected(tester, 'Musique'), isFalse);
        expect(_isSelected(tester, 'Cinéma'), isTrue);
      });

      testWidgets('shows a preexisting selection: ${mode.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            selected: const {'sport'},
            mode: mode,
          ),
        );

        expect(_isSelected(tester, 'Sport'), isTrue);
        expect(_isSelected(tester, 'Musique'), isFalse);
      });

      testWidgets('shows an empty selection: ${mode.name}', (tester) async {
        await pumpCbs(
          tester,
          child: _selector(onChanged: (_) {}, mode: mode),
        );

        for (final option in _options) {
          expect(_isSelected(tester, option.label), isFalse);
        }
      });
    }
  });

  group('disabled interactions', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('a disabled category stays visible and inert: ${mode.name}', (
        tester,
      ) async {
        final reported = <Set<String>>[];
        await pumpCbs(
          tester,
          child: _Host(
            options: _optionsWithDisabled,
            mode: mode,
            reported: reported,
          ),
        );

        expect(find.text('Sport'), findsOneWidget);
        expect(_onSelectedOf(tester, 'Sport'), isNull);
        expect(_onSelectedOf(tester, 'Musique'), isNotNull);
        expect(_onSelectedOf(tester, 'Cinéma'), isNotNull);

        await _tap(tester, 'Sport');

        expect(reported, isEmpty);
        expect(_isSelected(tester, 'Sport'), isFalse);
        expect(tester.takeException(), isNull);
      });

      testWidgets('a disabled selected category keeps its selection: '
          '${mode.name}', (tester) async {
        final reported = <Set<String>>[];
        await pumpCbs(
          tester,
          child: _Host(
            options: _optionsWithDisabled,
            mode: mode,
            initial: const {'sport'},
            reported: reported,
          ),
        );
        expect(_isSelected(tester, 'Sport'), isTrue);

        await _tap(tester, 'Sport');
        expect(reported, isEmpty);
        expect(_isSelected(tester, 'Sport'), isTrue);

        // The other categories remain usable.
        await _tap(tester, 'Musique');
        expect(reported, hasLength(1));
        expect(reported.single, contains('musique'));
        if (mode == CbsCategorySelectionMode.multiple) {
          // The disabled selected category is part of the new selection.
          expect(reported.single, {'sport', 'musique'});
          expect(_isSelected(tester, 'Sport'), isTrue);
        } else {
          // A single selection is replaced as a whole.
          expect(reported.single, {'musique'});
          expect(_isSelected(tester, 'Sport'), isFalse);
        }
      });

      testWidgets('a null callback disables every category: ${mode.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: null,
            selected: const {'sport'},
            mode: mode,
          ),
        );

        for (final option in _options) {
          expect(find.text(option.label), findsOneWidget);
          expect(
            _onSelectedOf(tester, option.label),
            isNull,
            reason: option.label,
          );
        }
        // The selection is still displayed.
        expect(_isSelected(tester, 'Sport'), isTrue);
        expect(_isSelected(tester, 'Musique'), isFalse);

        for (final option in _options) {
          await _tap(tester, option.label);
        }

        expect(_isSelected(tester, 'Sport'), isTrue);
        expect(_isSelected(tester, 'Musique'), isFalse);
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('a disabled category is exposed as disabled', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(tester, child: const _Host(options: _optionsWithDisabled));

      final disabled = tester.getSemantics(_chip('Sport'));
      expect(disabled.flagsCollection.isButton, isTrue);
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      expect(
        disabled.getSemanticsData().hasAction(SemanticsAction.tap),
        isFalse,
      );
      expect(disabled.label, 'Sport');

      for (final label in ['Musique', 'Cinéma']) {
        final enabled = tester.getSemantics(_chip(label));
        expect(enabled.flagsCollection.isEnabled, Tristate.isTrue);
        expect(
          enabled.getSemanticsData().hasAction(SemanticsAction.tap),
          isTrue,
        );
      }

      semantics.dispose();
    });

    testWidgets('a null callback exposes every category as disabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(tester, child: _selector(onChanged: null));

      for (final option in _options) {
        final node = tester.getSemantics(_chip(option.label));
        expect(node.flagsCollection.isButton, isTrue, reason: option.label);
        expect(
          node.flagsCollection.isEnabled,
          Tristate.isFalse,
          reason: option.label,
        );
        expect(
          node.getSemanticsData().hasAction(SemanticsAction.tap),
          isFalse,
          reason: option.label,
        );
      }

      semantics.dispose();
    });
  });

  group('empty list', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('builds nothing and takes no space: ${mode.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          child: _selector(onChanged: (_) {}, options: const [], mode: mode),
        );

        expect(tester.takeException(), isNull);
        expect(_selectorFinder, findsOneWidget);
        expect(_anyChip, findsNothing);
        expect(_scrollable, findsNothing);
        expect(tester.getSize(_selectorFinder), Size.zero);
      });

      testWidgets('does not fail with a selection or without callback: '
          '${mode.name}', (tester) async {
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: null,
            options: const [],
            selected: const {'inconnue'},
            mode: mode,
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(_selectorFinder), Size.zero);
      });
    }

    testWidgets('shows the chips once options are provided', (tester) async {
      await pumpCbs(
        tester,
        child: _selector(onChanged: (_) {}, options: const []),
      );
      expect(_anyChip, findsNothing);

      await pumpCbs(tester, child: _selector(onChanged: (_) {}));

      expect(_anyChip, findsNWidgets(_options.length));
      expect(tester.takeException(), isNull);
    });
  });

  group('visual and semantic order, spacing', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('lays the categories out on one row, in the order given, '
          'separated by CbsSpacing.sm: ${mode.name}', (tester) async {
        await pumpCbs(
          tester,
          width: 1280,
          child: _selector(onChanged: (_) {}, mode: mode),
        );

        final rects = [
          for (final option in _options) tester.getRect(_chip(option.label)),
        ];

        expect(rects.first.left, 0);
        for (var i = 1; i < rects.length; i++) {
          expect(
            rects[i].left - rects[i - 1].right,
            closeTo(CbsSpacing.sm, _epsilon),
            reason: 'gap before ${_options[i].label}',
          );
          expect(rects[i].top, closeTo(rects.first.top, _epsilon));
          expect(rects[i].height, closeTo(rects.first.height, _epsilon));
        }
      });

      testWidgets('adds no external margin or padding: ${mode.name}', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: 1280,
          child: _selector(onChanged: (_) {}, mode: mode),
        );

        final selector = tester.getRect(_selectorFinder);
        final first = tester.getRect(_chip(_options.first.label));
        final last = tester.getRect(_chip(_options.last.label));

        expect(selector.topLeft, Offset.zero);
        expect(first.left, selector.left);
        expect(last.right, closeTo(selector.right, _epsilon));
        expect(selector.height, closeTo(first.height, _epsilon));
      });

      testWidgets('the semantic order is the order of the options: '
          '${mode.name}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCbs(
          tester,
          width: 1280,
          child: _selector(onChanged: (_) {}, mode: mode),
        );

        expect(_buttonLabels(tester), [
          for (final option in _options) option.label,
        ]);

        semantics.dispose();
      });

      testWidgets('the order follows the list, not the labels: ${mode.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final reversed = _options.reversed.toList();
        await pumpCbs(
          tester,
          width: 1280,
          child: _selector(onChanged: (_) {}, options: reversed, mode: mode),
        );

        final lefts = [
          for (final option in reversed)
            tester.getRect(_chip(option.label)).left,
        ];
        expect(lefts, [...lefts]..sort());
        expect(_buttonLabels(tester), [
          for (final option in reversed) option.label,
        ]);

        semantics.dispose();
      });
    }

    testWidgets('starts at the end edge in a right-to-left context', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        width: 1280,
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: _selector(onChanged: (_) {}),
        ),
      );

      final rects = [
        for (final option in _options) tester.getRect(_chip(option.label)),
      ];
      for (var i = 1; i < rects.length; i++) {
        expect(rects[i].right, lessThan(rects[i - 1].left + _epsilon));
        expect(
          rects[i - 1].left - rects[i].right,
          closeTo(CbsSpacing.sm, _epsilon),
        );
      }
      expect(tester.takeException(), isNull);

      semantics.dispose();
    });
  });

  group('horizontal scrolling', () {
    testWidgets('uses a native horizontal SingleChildScrollView', (
      tester,
    ) async {
      await pumpCbs(tester, child: _selector(onChanged: (_) {}));

      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: _selectorFinder,
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(scroll.scrollDirection, Axis.horizontal);
      expect(scroll.controller, isNull);
      expect(scroll.physics, isNull);
      expect(
        tester.state<ScrollableState>(_scrollable).axisDirection,
        AxisDirection.right,
      );
      for (final type in [Wrap, ListView, GridView, PageView]) {
        expect(
          find.descendant(
            of: _selectorFinder,
            matching: find.byElementPredicate(
              (element) => element.widget.runtimeType == type,
            ),
          ),
          findsNothing,
          reason: '$type must not be part of the selector',
        );
      }
    });

    testWidgets('never wraps onto several rows', (tester) async {
      await pumpCbs(
        tester,
        width: 320,
        child: _selector(onChanged: (_) {}, options: _manyOptions),
      );

      final tops = {
        for (final option in _manyOptions)
          tester.getRect(_chip(option.label)).top.toStringAsFixed(2),
      };
      expect(tops, hasLength(1));
    });

    testWidgets('scrolls when the chips are wider than the width', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 320,
        child: _selector(onChanged: (_) {}, options: _manyOptions),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_selectorFinder).width, 320);
      expect(_maxScrollExtent(tester), greaterThan(0));
      expect(_scrollOffset(tester), 0);

      final before = tester.getRect(_chip('Musique')).left;
      await tester.drag(_scrollable, const Offset(-200, 0));
      await tester.pump();

      expect(_scrollOffset(tester), greaterThan(0));
      expect(tester.getRect(_chip('Musique')).left, lessThan(before));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a category out of view can be brought into view', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 320,
        child: _selector(onChanged: (_) {}, options: _manyOptions),
      );
      expect(tester.getRect(_chip('Gastronomie')).left, greaterThan(320));

      await tester.ensureVisible(find.text('Gastronomie'));
      await tester.pump();

      final rect = tester.getRect(_chip('Gastronomie'));
      expect(rect.left, greaterThanOrEqualTo(0));
      expect(rect.right, lessThanOrEqualTo(320 + _epsilon));
      expect(_scrollOffset(tester), greaterThan(0));
    });

    testWidgets('a category reached by scrolling can be selected', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpCbs(
        tester,
        width: 320,
        child: _Host(options: _manyOptions, reported: reported),
      );

      await tester.ensureVisible(find.text('Gastronomie'));
      await tester.pump();
      await _tap(tester, 'Gastronomie');

      expect(reported, [
        {'gastronomie'},
      ]);
      expect(_isSelected(tester, 'Gastronomie'), isTrue);
    });

    testWidgets('does not scroll when the chips fit', (tester) async {
      await pumpCbs(tester, width: 1280, child: _selector(onChanged: (_) {}));

      expect(_maxScrollExtent(tester), 0);

      await tester.drag(_scrollable, const Offset(-200, 0));
      await tester.pump();

      expect(_scrollOffset(tester), 0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('keeps a very long label on one line and reachable', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 320,
        child: _selector(
          onChanged: (_) {},
          options: const [
            CbsCategoryOption<String>(value: 'long', label: _longLabel),
            _sport,
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      // The label is neither wrapped nor shrunk to the viewport.
      expect(tester.getSize(find.text(_longLabel)).width, greaterThan(320));
      expect(tester.getRect(_chip(_longLabel)).width, greaterThan(320));
      expect(tester.getSize(_selectorFinder).width, 320);
      expect(_maxScrollExtent(tester), greaterThan(0));

      final paragraph = tester.renderObject<RenderParagraph>(
        find
            .descendant(of: _chip(_longLabel), matching: find.byType(RichText))
            .first,
      );
      expect(paragraph.didExceedMaxLines, isFalse);

      await tester.ensureVisible(find.text('Sport'));
      await tester.pump();
      expect(
        tester.getRect(_chip('Sport')).right,
        lessThanOrEqualTo(320 + _epsilon),
      );
    });
  });

  group('widths, text scales and themes', () {
    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        for (final variant in cbsTestThemes) {
          testWidgets('no overflow, one row, native scroll: width '
              '${width.round()}, text x$scale, ${variant.name}', (
            tester,
          ) async {
            for (final mode in CbsCategorySelectionMode.values) {
              await pumpCbs(
                tester,
                theme: variant.theme,
                width: width,
                textScale: scale,
                child: _selector(
                  onChanged: (_) {},
                  options: _manyOptions,
                  selected: const {'sport'},
                  mode: mode,
                ),
              );

              final reason = mode.name;
              expect(tester.takeException(), isNull, reason: reason);
              expect(_anyChip, findsNWidgets(_manyOptions.length));

              final selector = tester.getRect(_selectorFinder);
              expect(selector.left, 0, reason: reason);
              expect(selector.width, lessThanOrEqualTo(width), reason: reason);

              final rects = [
                for (final option in _manyOptions)
                  tester.getRect(_chip(option.label)),
              ];
              for (final rect in rects) {
                expect(rect.top, closeTo(rects.first.top, _epsilon));
                expect(rect.height, closeTo(rects.first.height, _epsilon));
              }

              // The extent to scroll is exactly what does not fit.
              final content = rects.last.right - rects.first.left;
              expect(
                _maxScrollExtent(tester),
                closeTo(math.max(0, content - selector.width), 0.01),
                reason: reason,
              );
              // The long label alone is wider than every tested width.
              expect(content, greaterThan(width), reason: reason);
              expect(_maxScrollExtent(tester), greaterThan(0), reason: reason);
            }
          });
        }
      }
    }

    for (final width in cbsTestWidths) {
      testWidgets('short categories fit and do not scroll when there is '
          'room: width ${width.round()}', (tester) async {
        await pumpCbs(
          tester,
          width: width,
          child: _selector(
            onChanged: (_) {},
            options: const [_musique, _sport],
          ),
        );

        expect(tester.takeException(), isNull);
        expect(_maxScrollExtent(tester), 0);
        expect(tester.getSize(_selectorFinder).width, lessThanOrEqualTo(width));
      });
    }

    testWidgets('the chips follow the text scale', (tester) async {
      Future<Size> chipSize(double scale) async {
        await pumpCbs(
          tester,
          width: 1280,
          textScale: scale,
          child: _selector(onChanged: (_) {}),
        );
        return tester.getSize(_chip('Musique'));
      }

      final x1 = await chipSize(1);
      final x2 = await chipSize(2);

      expect(x2.width, greaterThan(x1.width));
      expect(x2.height, greaterThan(x1.height));
      expect(tester.takeException(), isNull);
    });

    testWidgets('the selector is as tall as its tallest chip at text x2', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        width: 320,
        textScale: 2,
        child: _selector(onChanged: (_) {}, options: _manyOptions),
      );

      final selector = tester.getSize(_selectorFinder);
      final chip = tester.getSize(_chip('Musique'));
      expect(selector.height, closeTo(chip.height, _epsilon));
      expect(tester.takeException(), isNull);
    });

    for (final variant in cbsTestThemes) {
      testWidgets('single mode takes its colors from the theme: '
          '${variant.name}', (tester) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: _selector(onChanged: (_) {}, selected: const {'sport'}),
        );
        final scheme = variant.theme.colorScheme;

        expect(
          _labelStyle(tester, 'Sport')!.color,
          scheme.onSecondaryContainer,
        );
        expect(_labelStyle(tester, 'Musique')!.color, scheme.onSurfaceVariant);
      });

      testWidgets('multiple mode takes its colors from the theme: '
          '${variant.name}', (tester) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: _selector(
            onChanged: (_) {},
            selected: const {'sport'},
            mode: CbsCategorySelectionMode.multiple,
          ),
        );
        final scheme = variant.theme.colorScheme;

        expect(
          _labelStyle(tester, 'Sport')!.color,
          scheme.onSecondaryContainer,
        );
        expect(_labelStyle(tester, 'Musique')!.color, scheme.onSurfaceVariant);
      });
    }

    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('follows the ChipThemeData of the theme: ${mode.name}', (
        tester,
      ) async {
        final theme = CbsTheme.essentials().copyWith(
          chipTheme: const ChipThemeData(
            labelStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w800),
          ),
        );

        await pumpCbs(
          tester,
          theme: theme,
          child: _selector(
            onChanged: (_) {},
            selected: const {'sport'},
            mode: mode,
          ),
        );

        for (final label in ['Sport', 'Musique']) {
          final style = _labelStyle(tester, label)!;
          expect(style.fontSize, 21, reason: label);
          expect(style.fontWeight, FontWeight.w800, reason: label);
        }
      });

      testWidgets('follows the Branded typography: ${mode.name}', (
        tester,
      ) async {
        final theme = CbsTheme.branded(
          primaryColor: Colors.green,
          textTheme: const TextTheme(
            labelLarge: TextStyle(fontFamily: 'BrandFont', fontSize: 18),
          ),
        );

        await pumpCbs(
          tester,
          theme: theme,
          child: _selector(onChanged: (_) {}, mode: mode),
        );

        final style = _labelStyle(tester, 'Musique')!;
        expect(style.fontFamily, 'BrandFont');
        expect(style.fontSize, 18);
      });
    }
  });

  group('keyboard navigation', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('Tab visits the categories in order, Shift+Tab goes back: '
          '${mode.name}', (tester) async {
        await pumpA11y(
          tester,
          child: _Host(options: _options, mode: mode),
        );
        for (final option in _options) {
          expect(_hasFocus(tester, option.label), isFalse);
        }

        for (final option in _options) {
          await _tab(tester);
          expect(_hasFocus(tester, option.label), isTrue, reason: option.label);
        }

        await _tab(tester, shift: true);
        expect(_hasFocus(tester, 'Cinéma'), isTrue);
        expect(_hasFocus(tester, 'Théâtre'), isFalse);
      });

      testWidgets('Tab skips a disabled category: ${mode.name}', (
        tester,
      ) async {
        await pumpA11y(
          tester,
          child: _Host(options: _optionsWithDisabled, mode: mode),
        );

        await _tab(tester);
        expect(_hasFocus(tester, 'Musique'), isTrue);

        await _tab(tester);
        expect(_hasFocus(tester, 'Sport'), isFalse);
        expect(_hasFocus(tester, 'Cinéma'), isTrue);
      });

      testWidgets('a null callback gives no focus to any category: '
          '${mode.name}', (tester) async {
        await pumpA11y(tester, child: _selector(onChanged: null, mode: mode));

        await _tab(tester);
        await _tab(tester);

        for (final option in _options) {
          expect(_hasFocus(tester, option.label), isFalse);
        }
      });

      testWidgets('Enter and Space activate the focused category: '
          '${mode.name}', (tester) async {
        final reported = <Set<String>>[];
        await pumpA11y(
          tester,
          child: _Host(options: _options, mode: mode, reported: reported),
        );

        await _tab(tester);
        await _tab(tester);
        expect(_hasFocus(tester, 'Sport'), isTrue);
        await _press(tester, LogicalKeyboardKey.enter);

        expect(reported, [
          {'sport'},
        ]);
        expect(_isSelected(tester, 'Sport'), isTrue);

        await _tab(tester);
        expect(_hasFocus(tester, 'Cinéma'), isTrue);
        await _press(tester, LogicalKeyboardKey.space);

        expect(reported.length, 2);
        expect(
          reported.last,
          mode == CbsCategorySelectionMode.multiple
              ? {'sport', 'cinema'}
              : {'cinema'},
        );
        expect(_isSelected(tester, 'Cinéma'), isTrue);
      });

      testWidgets('keys do nothing before a category has focus: '
          '${mode.name}', (tester) async {
        final reported = <Set<String>>[];
        await pumpA11y(
          tester,
          child: _Host(options: _options, mode: mode, reported: reported),
        );

        await _press(tester, LogicalKeyboardKey.enter);
        await _press(tester, LogicalKeyboardKey.space);

        expect(reported, isEmpty);
      });

      testWidgets('keys never change a disabled selection: ${mode.name}', (
        tester,
      ) async {
        final reported = <Set<String>>[];
        await pumpA11y(
          tester,
          child: _selector(
            onChanged: reported.add,
            options: _optionsWithDisabled,
            selected: const {'sport'},
            mode: mode,
          ),
        );

        // Musique, then Cinéma: Sport is never reached.
        await _tab(tester);
        await _tab(tester);
        await _press(tester, LogicalKeyboardKey.enter);

        expect(_hasFocus(tester, 'Sport'), isFalse);
        expect(reported, hasLength(1));
        expect(reported.single, contains('cinema'));
      });
    }

    testWidgets('Space and Enter toggle a category of the multiple mode', (
      tester,
    ) async {
      final reported = <Set<String>>[];
      await pumpA11y(
        tester,
        child: _Host(
          options: _options,
          mode: CbsCategorySelectionMode.multiple,
          reported: reported,
        ),
      );

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.space);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(reported, [
        {'musique'},
        <String>{},
      ]);
      expect(_isSelected(tester, 'Musique'), isFalse);
    });

    testWidgets('the focus stays on the category after it is activated', (
      tester,
    ) async {
      await pumpA11y(tester, child: const _Host(options: _options));

      await _tab(tester);
      await _press(tester, LogicalKeyboardKey.enter);

      expect(_hasFocus(tester, 'Musique'), isTrue);
    });

    testWidgets('Tab brings an out-of-view category into view', (tester) async {
      await pumpA11y(
        tester,
        width: 320,
        child: const _Host(options: _manyOptions),
      );
      expect(_scrollOffset(tester), 0);

      for (var i = 0; i < _manyOptions.length; i++) {
        await _tab(tester);
      }

      expect(_hasFocus(tester, 'Gastronomie'), isTrue);
      expect(_scrollOffset(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    });
  });

  group('accessibility', () {
    for (final mode in CbsCategorySelectionMode.values) {
      testWidgets('each category is a button exposing label, selected and '
          'enabled states: ${mode.name}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            selected: const {'sport'},
            mode: mode,
          ),
        );

        for (final option in _options) {
          final node = tester.getSemantics(_chip(option.label));
          final isSelected = option.value == 'sport';
          expect(node.flagsCollection.isButton, isTrue, reason: option.label);
          expect(node.label, option.label);
          expect(
            node.flagsCollection.isEnabled,
            Tristate.isTrue,
            reason: option.label,
          );
          expect(
            node.flagsCollection.isSelected,
            isSelected ? Tristate.isTrue : Tristate.isFalse,
            reason: option.label,
          );
          expect(
            node.getSemanticsData().hasAction(SemanticsAction.tap),
            isTrue,
            reason: option.label,
          );
        }

        semantics.dispose();
      });

      testWidgets('the semantic state follows the selection: ${mode.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpCbs(
          tester,
          child: _Host(options: _options, mode: mode),
        );
        expect(
          tester.getSemantics(_chip('Sport')).flagsCollection.isSelected,
          Tristate.isFalse,
        );

        await _tap(tester, 'Sport');

        expect(
          tester.getSemantics(_chip('Sport')).flagsCollection.isSelected,
          Tristate.isTrue,
        );

        semantics.dispose();
      });

      testWidgets('the semantic label replaces the text but keeps the role '
          'and the states: ${mode.name}', (tester) async {
        final semantics = tester.ensureSemantics();
        await pumpCbs(
          tester,
          child: _selector(
            onChanged: (_) {},
            options: const [
              CbsCategoryOption<String>(
                value: 'musique',
                label: 'Musique',
                semanticLabel: 'Catégorie musique',
              ),
              _sport,
            ],
            selected: const {'musique'},
            mode: mode,
          ),
        );

        final node = tester.getSemantics(_chip('Musique'));
        expect(node.label, 'Catégorie musique');
        expect(node.flagsCollection.isButton, isTrue);
        expect(node.flagsCollection.isSelected, Tristate.isTrue);
        expect(node.flagsCollection.isEnabled, Tristate.isTrue);
        expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
        expect(find.bySemanticsLabel('Catégorie musique'), findsWidgets);
        // The visible text is unchanged and the other category is not
        // affected.
        expect(find.text('Musique'), findsOneWidget);
        expect(tester.getSemantics(_chip('Sport')).label, 'Sport');

        semantics.dispose();
      });

      testWidgets('a category with a semantic label still activates: '
          '${mode.name}', (tester) async {
        final reported = <Set<String>>[];
        await pumpCbs(
          tester,
          child: _Host(
            options: const [
              CbsCategoryOption<String>(
                value: 'musique',
                label: 'Musique',
                semanticLabel: 'Catégorie musique',
              ),
            ],
            mode: mode,
            reported: reported,
          ),
        );

        await _tap(tester, 'Musique');

        expect(reported, [
          {'musique'},
        ]);
      });

      testWidgets('semantic activation selects the category: ${mode.name}', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        final reported = <Set<String>>[];
        await pumpCbs(
          tester,
          child: _Host(options: _options, mode: mode, reported: reported),
        );

        tester.semantics.tap(find.semantics.byLabel('Cinéma'));
        await tester.pump();

        expect(reported, [
          {'cinema'},
        ]);

        semantics.dispose();
      });

      for (final scale in cbsTestTextScales) {
        testWidgets('meets the tap target and label guidelines: ${mode.name}, '
            'text x$scale', (tester) async {
          final semantics = tester.ensureSemantics();
          await pumpA11y(
            tester,
            width: 1280,
            textScale: scale,
            child: _Host(options: _options, mode: mode),
          );

          expectTapTargetEvaluated(tester, _chip('Sport'));
          await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
          await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

          semantics.dispose();
        });
      }
    }

    testWidgets('a chip is at least 48 x 48 logical pixels', (tester) async {
      await pumpCbs(tester, child: _selector(onChanged: (_) {}));

      for (final option in _options) {
        final size = tester.getSize(_chip(option.label));
        expect(size.width, greaterThanOrEqualTo(48), reason: option.label);
        expect(size.height, greaterThanOrEqualTo(48), reason: option.label);
      }
    });
  });

  group('composition and non-regression of VP-01 to VP-04', () {
    testWidgets('lives in a CbsContentSection under the section spacing', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(
          title: 'Catégories',
          child: _selector(onChanged: (_) {}),
        ),
      );

      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.byType(CbsSectionHeading));
      final selector = tester.getRect(_selectorFinder);
      expect(selector.top - heading.bottom, closeTo(CbsSpacing.sm, _epsilon));
      expect(selector.width, 600);
      expect(tester.getRect(_chip('Musique')).left, 0);
    });

    testWidgets('lives in the content of a CbsContentCard', (tester) async {
      await pumpCbs(
        tester,
        child: CbsContentCard(content: _selector(onChanged: (_) {})),
      );

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(_selectorFinder).width,
        closeTo(600 - 2 * CbsSpacing.md, _epsilon),
      );
    });

    testWidgets('sits above a CbsAdaptiveCollection of cards with media', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CbsSectionHeading(title: 'Catégories'),
            SizedBox(height: CbsSpacing.sm),
            _Host(options: _options, mode: CbsCategorySelectionMode.multiple),
            SizedBox(height: CbsSpacing.md),
            CbsAdaptiveCollection(
              layout: CbsCollectionLayout.grid,
              children: [
                CbsContentCard(
                  media: CbsMediaFrame(child: ColoredBox(color: Colors.grey)),
                  content: Text('Premier contenu'),
                ),
                CbsContentCard(
                  media: CbsMediaFrame(child: ColoredBox(color: Colors.grey)),
                  content: Text('Second contenu'),
                ),
              ],
            ),
          ],
        ),
      );

      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.byType(CbsSectionHeading));
      final selector = tester.getRect(_selectorFinder);
      final collection = tester.getRect(find.byType(CbsAdaptiveCollection));
      expect(selector.top, closeTo(heading.bottom + CbsSpacing.sm, _epsilon));
      expect(
        collection.top,
        closeTo(selector.bottom + CbsSpacing.md, _epsilon),
      );

      // The selector stays usable next to the other parts.
      await _tap(tester, 'Sport');
      expect(_isSelected(tester, 'Sport'), isTrue);
    });

    testWidgets('the VP-01 to VP-04 resources keep their defaults', (
      tester,
    ) async {
      expect(CbsContentCardLayout.values, [
        CbsContentCardLayout.vertical,
        CbsContentCardLayout.horizontal,
      ]);
      expect(CbsCollectionLayout.values, [
        CbsCollectionLayout.list,
        CbsCollectionLayout.grid,
      ]);
      expect(const CbsMediaFrame(child: SizedBox()).aspectRatio, 16 / 9);
      expect(
        const CbsAdaptiveCollection(children: []).layout,
        CbsCollectionLayout.list,
      );
      expect(
        const CbsContentSection(title: 'Titre', child: SizedBox()).subtitle,
        isNull,
      );
      expect(const CbsSectionHeading(title: 'Titre').title, 'Titre');
    });
  });
}
