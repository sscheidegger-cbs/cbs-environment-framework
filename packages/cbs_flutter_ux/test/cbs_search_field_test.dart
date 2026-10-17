import 'dart:ui' show SemanticsAction, Tristate;

import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/cbs_a11y_support.dart';
import 'support/cbs_test_matrix.dart';

const double _epsilon = 0.001;

const String _hint = 'Search';
const String _semanticLabel = 'Search the catalog';
const String _prefilled = 'Jazz concert';

const String _longHint =
    'Search for events, venues, artists, categories and everything else that '
    'is described in this catalog, whatever the length of this hint';

/// Controller of the tests that counts what the field does to it.
///
/// A controller provided by the application must never be disposed by the
/// field and must not keep a listener of the field once it is gone.
class _SpyController extends TextEditingController {
  _SpyController({super.text});

  /// Listeners added and not removed yet.
  int listeners = 0;

  /// Number of calls to [dispose].
  int disposeCalls = 0;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    listeners++;
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    listeners--;
  }

  @override
  void dispose() {
    disposeCalls++;
    super.dispose();
  }
}

CbsSearchField _field({
  Key? key,
  TextEditingController? controller,
  String? hintText = _hint,
  bool enabled = true,
  bool autofocus = false,
  ValueChanged<String>? onChanged,
  ValueChanged<String>? onSubmitted,
  VoidCallback? onClear,
  String? semanticLabel,
}) {
  return CbsSearchField(
    key: key,
    controller: controller,
    hintText: hintText,
    enabled: enabled,
    autofocus: autofocus,
    onChanged: onChanged,
    onSubmitted: onSubmitted,
    onClear: onClear,
    semanticLabel: semanticLabel,
  );
}

Finder get _fieldFinder => find.byType(CbsSearchField);
Finder get _textField => find.byType(TextField);
Finder get _editable => find.byType(EditableText);
Finder get _clearButton => find.widgetWithIcon(IconButton, Icons.clear);
Finder get _searchIcon => find.byIcon(Icons.search);

TextField _nativeField(WidgetTester tester) =>
    tester.widget<TextField>(_textField);

/// Controller the native text field really uses.
TextEditingController _controllerInUse(WidgetTester tester) =>
    _nativeField(tester).controller!;

FocusNode _focusNodeInUse(WidgetTester tester) =>
    _nativeField(tester).focusNode!;

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(_textField, text);
  await tester.pump();
}

Future<void> _tapClear(WidgetTester tester) async {
  await tester.tap(_clearButton);
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

/// Whether the primary focus is the text input of the field.
bool _inputHasFocus(WidgetTester tester) =>
    hasPrimaryFocusWithin(tester, _editable);

/// Whether the primary focus is the clear action.
bool _clearHasFocus(WidgetTester tester) =>
    hasPrimaryFocusWithin(tester, _clearButton);

/// Color that the icons of the decoration of the active theme get.
Color? _iconColor(WidgetTester tester, Finder icon) =>
    IconTheme.of(tester.element(icon)).color;

/// Style of the hint drawn by the field.
TextStyle? _hintStyle(WidgetTester tester) =>
    tester.widget<Text>(find.text(_hint)).style;

/// The same native text field, without anything added by CBS but its shape.
Widget _referenceField() {
  return TextField(
    decoration: InputDecoration(
      hintText: _hint,
      prefixIcon: const Icon(Icons.search),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(CbsRadius.pill),
      ),
    ),
  );
}

void main() {
  group('public API', () {
    test('every parameter is optional and has its documented default', () {
      const field = CbsSearchField();

      expect(field.key, isNull);
      expect(field.controller, isNull);
      expect(field.hintText, isNull);
      expect(field.enabled, isTrue);
      expect(field.autofocus, isFalse);
      expect(field.onChanged, isNull);
      expect(field.onSubmitted, isNull);
      expect(field.onClear, isNull);
      expect(field.semanticLabel, isNull);
    });

    test('is a StatelessWidget, not a StatefulWidget', () {
      const field = CbsSearchField();

      expect(field, isA<StatelessWidget>());
      expect(field, isNot(isA<StatefulWidget>()));
    });

    test('keeps every parameter it is given', () {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final events = <String>[];
      final field = CbsSearchField(
        key: const ValueKey('search'),
        controller: controller,
        hintText: _hint,
        enabled: false,
        autofocus: true,
        onChanged: (text) => events.add('changed:$text'),
        onSubmitted: (text) => events.add('submitted:$text'),
        onClear: () => events.add('clear'),
        semanticLabel: _semanticLabel,
      );

      expect(field.key, const ValueKey('search'));
      expect(field.controller, same(controller));
      expect(field.hintText, _hint);
      expect(field.enabled, isFalse);
      expect(field.autofocus, isTrue);
      expect(field.semanticLabel, _semanticLabel);
      field.onChanged!('a');
      field.onSubmitted!('b');
      field.onClear!();
      expect(events, ['changed:a', 'submitted:b', 'clear']);
    });

    testWidgets('builds without any parameter', (tester) async {
      await pumpCbs(tester, child: const CbsSearchField());

      expect(tester.takeException(), isNull);
      expect(_fieldFinder, findsOneWidget);
      expect(_textField, findsOneWidget);
    });

    testWidgets('builds with every parameter', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: _field(
          key: const ValueKey('search'),
          controller: controller,
          autofocus: true,
          onChanged: (_) {},
          onSubmitted: (_) {},
          onClear: () {},
          semanticLabel: _semanticLabel,
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('search')), findsOneWidget);
    });
  });

  group('native Flutter widgets', () {
    testWidgets('wraps one TextField and builds no other search widget', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());

      expect(_textField, findsOneWidget);
      expect(_editable, findsOneWidget);
      expect(find.byType(SearchBar), findsNothing);
      expect(find.byType(SearchAnchor), findsNothing);
      expect(find.byType(TextFormField), findsNothing);
    });

    testWidgets('shows the native search icon, which is decorative', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());

      final icon = find.descendant(of: _textField, matching: _searchIcon);
      expect(icon, findsOneWidget);
      expect(tester.widget<Icon>(icon).semanticLabel, isNull);
    });

    testWidgets('shows the hint while the field is empty', (tester) async {
      await pumpCbs(tester, child: _field());

      expect(find.text(_hint), findsOneWidget);
      expect(_nativeField(tester).decoration!.hintText, _hint);
    });

    testWidgets('shows no hint when none is given', (tester) async {
      await pumpCbs(tester, child: _field(hintText: null));

      expect(_nativeField(tester).decoration!.hintText, isNull);
      expect(find.text(_hint), findsNothing);
    });

    testWidgets('uses the search keyboard action', (tester) async {
      await pumpCbs(tester, child: _field());

      expect(_nativeField(tester).textInputAction, TextInputAction.search);
    });

    testWidgets('takes its shape from CbsRadius.pill and nothing else', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());

      final border = _nativeField(tester).decoration!.border;
      expect(border, isA<OutlineInputBorder>());
      expect(
        (border! as OutlineInputBorder).borderRadius,
        BorderRadius.circular(CbsRadius.pill),
      );
    });

    testWidgets('overrides no color, style or metric of the theme', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());

      final field = _nativeField(tester);
      final decoration = field.decoration!;
      final overrides = <String, Object?>{
        'style': field.style,
        'cursorColor': field.cursorColor,
        'cursorWidth': field.cursorWidth == 2.0 ? null : field.cursorWidth,
        'keyboardAppearance': field.keyboardAppearance,
        'filled': decoration.filled,
        'fillColor': decoration.fillColor,
        'focusColor': decoration.focusColor,
        'hoverColor': decoration.hoverColor,
        'hintStyle': decoration.hintStyle,
        'labelStyle': decoration.labelStyle,
        'iconColor': decoration.iconColor,
        'prefixIconColor': decoration.prefixIconColor,
        'suffixIconColor': decoration.suffixIconColor,
        'contentPadding': decoration.contentPadding,
        'isDense': decoration.isDense,
        'enabledBorder': decoration.enabledBorder,
        'focusedBorder': decoration.focusedBorder,
        'disabledBorder': decoration.disabledBorder,
      };

      expect([
        for (final entry in overrides.entries)
          if (entry.value != null) entry.key,
      ], isEmpty);
    });

    testWidgets('the clear action is a native IconButton with a tooltip', (
      tester,
    ) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      expect(_clearButton, findsOneWidget);
      expect(find.byTooltip('Clear text'), findsOneWidget);
      expect(
        find.descendant(of: _textField, matching: find.byType(IconButton)),
        findsOneWidget,
      );
    });
  });

  group('controller', () {
    testWidgets('works without a controller', (tester) async {
      final changes = <String>[];
      await pumpCbs(tester, child: _field(onChanged: changes.add));

      expect(tester.takeException(), isNull);
      expect(_controllerInUse(tester).text, isEmpty);

      await _type(tester, 'jazz');

      expect(_controllerInUse(tester).text, 'jazz');
      expect(changes, ['jazz']);
      expect(_clearButton, findsOneWidget);
    });

    testWidgets('keeps the same internal controller across rebuilds', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());
      final internal = _controllerInUse(tester);
      await _type(tester, 'jazz');

      await pumpCbs(tester, child: _field(hintText: 'Find'));
      await pumpCbs(tester, child: _field(hintText: 'Look up', enabled: true));

      expect(_controllerInUse(tester), same(internal));
      expect(internal.text, 'jazz');
      expect(find.text('jazz'), findsOneWidget);
    });

    testWidgets('uses the controller it is given', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      expect(_controllerInUse(tester), same(controller));
      expect(_nativeField(tester).controller, same(controller));
    });

    testWidgets('shows the text of the controller it is given', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      expect(find.text(_prefilled), findsOneWidget);
      expect(_clearButton, findsOneWidget);
    });

    testWidgets('typing updates the controller it is given', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      await _type(tester, 'opera');

      expect(controller.text, 'opera');
      expect(find.text('opera'), findsOneWidget);
    });

    testWidgets('follows a text changed from outside, without onChanged', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      final changes = <String>[];
      await pumpCbs(
        tester,
        child: _field(controller: controller, onChanged: changes.add),
      );
      expect(_clearButton, findsNothing);

      controller.text = 'set from outside';
      await tester.pump();

      expect(find.text('set from outside'), findsOneWidget);
      expect(_clearButton, findsOneWidget);
      // Like TextField.onChanged: only the edits of the user are reported.
      expect(changes, isEmpty);

      controller.clear();
      await tester.pump();

      expect(_clearButton, findsNothing);
      expect(changes, isEmpty);
    });

    testWidgets('keeps the selection of the controller across rebuilds', (
      tester,
    ) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));
      controller.selection = const TextSelection(
        baseOffset: 1,
        extentOffset: 4,
      );
      await tester.pump();

      await pumpCbs(
        tester,
        child: _field(controller: controller, hintText: 'x'),
      );

      expect(
        controller.selection,
        const TextSelection(baseOffset: 1, extentOffset: 4),
      );
      expect(controller.text, _prefilled);
    });

    testWidgets('a field with a controller and a field without are '
        'independent', (tester) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: Column(
          children: [
            _field(key: const ValueKey('first'), controller: controller),
            _field(key: const ValueKey('second')),
          ],
        ),
      );

      await tester.enterText(
        find.descendant(
          of: find.byKey(const ValueKey('second')),
          matching: _textField,
        ),
        'only the second',
      );
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(find.text('only the second'), findsOneWidget);
    });
  });

  group('resources and lifecycle', () {
    testWidgets('never disposes the controller it is given', (tester) async {
      final controller = _SpyController(text: _prefilled);
      await pumpCbs(tester, child: _field(controller: controller));
      expect(controller.listeners, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
      expect(controller.disposeCalls, 0);
      // Still usable by its owner.
      controller.text = 'still alive';
      expect(controller.text, 'still alive');
      // The owner disposes it once: a second dispose by the field would
      // have made this one fail.
      expect(controller.dispose, returnsNormally);
      expect(controller.disposeCalls, 1);
    });

    testWidgets('leaves no listener on the controller it is given', (
      tester,
    ) async {
      final controller = _SpyController();
      await pumpCbs(tester, child: _field(controller: controller));
      expect(controller.listeners, greaterThan(0));

      await tester.pumpWidget(const SizedBox.shrink());

      expect(controller.listeners, 0);
      controller.dispose();
    });

    testWidgets('does not accumulate listeners across rebuilds and typing', (
      tester,
    ) async {
      final controller = _SpyController();
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));
      final mounted = controller.listeners;

      for (var i = 0; i < 5; i++) {
        await pumpCbs(
          tester,
          child: _field(controller: controller, hintText: 'Hint $i'),
        );
        await _type(tester, 'text $i');
      }

      expect(controller.listeners, mounted);
    });

    testWidgets('disposes the internal controller and the focus node with '
        'the field', (tester) async {
      await pumpCbs(tester, child: _field());
      final internal = _controllerInUse(tester);
      final focusNode = _focusNodeInUse(tester);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(tester.takeException(), isNull);
      // A disposed ChangeNotifier refuses new listeners.
      expect(() => internal.addListener(() {}), throwsFlutterError);
      expect(() => focusNode.addListener(() {}), throwsFlutterError);
    });

    testWidgets('disposes the focus node of a field that has a controller', (
      tester,
    ) async {
      final controller = TextEditingController();
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));
      final focusNode = _focusNodeInUse(tester);

      await tester.pumpWidget(const SizedBox.shrink());

      expect(() => focusNode.addListener(() {}), throwsFlutterError);
      expect(tester.takeException(), isNull);
    });

    testWidgets('disposes the internal controller when a controller is '
        'provided', (tester) async {
      await pumpCbs(tester, child: _field());
      final internal = _controllerInUse(tester);
      final controller = _SpyController(text: 'provided');

      await pumpCbs(tester, child: _field(controller: controller));

      expect(tester.takeException(), isNull);
      expect(_controllerInUse(tester), same(controller));
      expect(() => internal.addListener(() {}), throwsFlutterError);
      expect(controller.disposeCalls, 0);
      expect(find.text('provided'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.disposeCalls, 0);
      expect(controller.listeners, 0);
      controller.dispose();
    });

    testWidgets('keeps the text and releases the controller that is '
        'withdrawn', (tester) async {
      final controller = _SpyController(text: _prefilled);
      await pumpCbs(tester, child: _field(controller: controller));

      await pumpCbs(tester, child: _field());

      expect(tester.takeException(), isNull);
      final internal = _controllerInUse(tester);
      expect(internal, isNot(same(controller)));
      expect(internal.text, _prefilled);
      expect(find.text(_prefilled), findsOneWidget);
      expect(controller.listeners, 0);
      expect(controller.disposeCalls, 0);

      // Editing the internal controller does not touch the old one.
      await _type(tester, 'other');
      expect(controller.text, _prefilled);

      await tester.pumpWidget(const SizedBox.shrink());
      expect(() => internal.addListener(() {}), throwsFlutterError);
      expect(controller.disposeCalls, 0);
      controller.dispose();
    });

    testWidgets('follows a replaced controller without disposing either', (
      tester,
    ) async {
      final first = _SpyController(text: 'first');
      final second = _SpyController(text: 'second');
      await pumpCbs(tester, child: _field(controller: first));
      expect(find.text('first'), findsOneWidget);

      await pumpCbs(tester, child: _field(controller: second));

      expect(tester.takeException(), isNull);
      expect(_controllerInUse(tester), same(second));
      expect(find.text('second'), findsOneWidget);
      expect(find.text('first'), findsNothing);
      expect(first.listeners, 0);
      expect(second.listeners, greaterThan(0));
      expect(first.disposeCalls, 0);
      expect(second.disposeCalls, 0);

      // The clear action follows the new controller.
      await _tapClear(tester);
      expect(second.text, isEmpty);
      expect(first.text, 'first');

      await tester.pumpWidget(const SizedBox.shrink());
      expect(second.listeners, 0);
      expect(first.disposeCalls, 0);
      expect(second.disposeCalls, 0);
      first.dispose();
      second.dispose();
    });

    testWidgets('the clear action never disposes the controller', (
      tester,
    ) async {
      final controller = _SpyController(text: _prefilled);
      await pumpCbs(tester, child: _field(controller: controller));

      await _tapClear(tester);
      await _type(tester, 'again');
      await _tapClear(tester);

      expect(controller.disposeCalls, 0);
      expect(controller.text, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      expect(controller.dispose, returnsNormally);
    });
  });

  group('onChanged', () {
    testWidgets('is called with the text at each edit', (tester) async {
      final changes = <String>[];
      await pumpCbs(tester, child: _field(onChanged: changes.add));

      await _type(tester, 'j');
      await _type(tester, 'ja');
      await _type(tester, 'jazz');

      expect(changes, ['j', 'ja', 'jazz']);
    });

    testWidgets('is called when the user deletes text', (tester) async {
      final changes = <String>[];
      await pumpCbs(tester, child: _field(onChanged: changes.add));

      await _type(tester, 'jazz');
      await _type(tester, 'jaz');
      await _type(tester, '');

      expect(changes, ['jazz', 'jaz', '']);
    });

    testWidgets('is not called when the field is built or focused', (
      tester,
    ) async {
      final changes = <String>[];
      await pumpCbs(
        tester,
        child: _field(
          controller: TextEditingController(text: _prefilled),
          onChanged: changes.add,
        ),
      );

      await tester.tap(_textField);
      await tester.pump();

      expect(changes, isEmpty);
    });

    testWidgets('can be null', (tester) async {
      await pumpCbs(tester, child: _field());

      await _type(tester, 'jazz');

      expect(tester.takeException(), isNull);
      expect(find.text('jazz'), findsOneWidget);
    });

    testWidgets('follows a new callback', (tester) async {
      final first = <String>[];
      final second = <String>[];
      await pumpCbs(tester, child: _field(onChanged: first.add));
      await _type(tester, 'a');

      await pumpCbs(tester, child: _field(onChanged: second.add));
      await _type(tester, 'ab');

      expect(first, ['a']);
      expect(second, ['ab']);
    });
  });

  group('onSubmitted', () {
    testWidgets('is called with the text when the keyboard submits', (
      tester,
    ) async {
      final submitted = <String>[];
      await pumpCbs(tester, child: _field(onSubmitted: submitted.add));
      await _type(tester, 'jazz');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submitted, ['jazz']);
    });

    testWidgets('does not change the text and does not call onChanged', (
      tester,
    ) async {
      final changes = <String>[];
      final submitted = <String>[];
      await pumpCbs(
        tester,
        child: _field(onChanged: changes.add, onSubmitted: submitted.add),
      );
      await _type(tester, 'jazz');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submitted, ['jazz']);
      expect(changes, ['jazz']);
      expect(_controllerInUse(tester).text, 'jazz');
      expect(_clearButton, findsOneWidget);
    });

    testWidgets('reports the text of an external controller', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      final submitted = <String>[];
      await pumpCbs(
        tester,
        child: _field(controller: controller, onSubmitted: submitted.add),
      );
      await tester.tap(_textField);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submitted, [_prefilled]);
    });

    testWidgets('can submit an empty text', (tester) async {
      final submitted = <String>[];
      await pumpCbs(tester, child: _field(onSubmitted: submitted.add));
      await tester.tap(_textField);
      await tester.pump();

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(submitted, ['']);
    });

    testWidgets('can be null', (tester) async {
      await pumpCbs(tester, child: _field());
      await _type(tester, 'jazz');

      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });

  group('clear action', () {
    testWidgets('is not shown while the text is empty', (tester) async {
      await pumpCbs(tester, child: _field());

      expect(_clearButton, findsNothing);
      expect(find.byTooltip('Clear text'), findsNothing);
    });

    testWidgets('is shown as soon as the text is not empty, and hidden '
        'again when it is emptied', (tester) async {
      await pumpCbs(tester, child: _field());

      await _type(tester, 'j');
      expect(_clearButton, findsOneWidget);

      await _type(tester, '');
      expect(_clearButton, findsNothing);
    });

    testWidgets('is shown for a prefilled text', (tester) async {
      await pumpCbs(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );

      expect(_clearButton, findsOneWidget);
    });

    testWidgets('empties the text of an internal controller', (tester) async {
      await pumpCbs(tester, child: _field());
      await _type(tester, 'jazz');

      await _tapClear(tester);

      expect(_controllerInUse(tester).text, isEmpty);
      expect(_controllerInUse(tester).selection.isCollapsed, isTrue);
      expect(_clearButton, findsNothing);
    });

    testWidgets('empties the text of an external controller', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      await _tapClear(tester);

      expect(controller.text, isEmpty);
      expect(find.text(_prefilled), findsNothing);
      expect(_clearButton, findsNothing);
    });

    testWidgets('notifies onChanged with an empty string, then onClear', (
      tester,
    ) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      final events = <String>[];
      await pumpCbs(
        tester,
        child: _field(
          controller: controller,
          onChanged: (text) => events.add('changed:$text'),
          onClear: () => events.add('clear'),
        ),
      );

      await _tapClear(tester);

      expect(events, ['changed:', 'clear']);
      expect(controller.text, isEmpty);
    });

    testWidgets('calls each callback once per activation', (tester) async {
      final events = <String>[];
      await pumpCbs(
        tester,
        child: _field(
          onChanged: (text) => events.add('changed:$text'),
          onClear: () => events.add('clear'),
        ),
      );

      await _type(tester, 'a');
      await _tapClear(tester);
      await _type(tester, 'b');
      await _tapClear(tester);

      expect(events, [
        'changed:a',
        'changed:',
        'clear',
        'changed:b',
        'changed:',
        'clear',
      ]);
    });

    testWidgets('works without onChanged and without onClear', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(tester, child: _field(controller: controller));

      await _tapClear(tester);

      expect(tester.takeException(), isNull);
      expect(controller.text, isEmpty);
    });

    testWidgets('works with onClear only', (tester) async {
      var cleared = 0;
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: _field(controller: controller, onClear: () => cleared++),
      );

      await _tapClear(tester);

      expect(cleared, 1);
      expect(controller.text, isEmpty);
    });

    testWidgets('does not call onSubmitted', (tester) async {
      final submitted = <String>[];
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: _field(controller: controller, onSubmitted: submitted.add),
      );

      await _tapClear(tester);

      expect(submitted, isEmpty);
    });

    testWidgets('gives the focus back to the text input', (tester) async {
      await pumpCbs(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );
      expect(_focusNodeInUse(tester).hasFocus, isFalse);

      await _tapClear(tester);

      expect(_focusNodeInUse(tester).hasFocus, isTrue);
    });

    testWidgets('lets the user type again after clearing', (tester) async {
      final changes = <String>[];
      await pumpCbs(tester, child: _field(onChanged: changes.add));
      await _type(tester, 'jazz');
      await _tapClear(tester);

      await _type(tester, 'opera');

      expect(_controllerInUse(tester).text, 'opera');
      expect(changes, ['jazz', '', 'opera']);
      expect(_clearButton, findsOneWidget);
    });

    testWidgets('uses the tooltip of the localizations', (tester) async {
      await pumpCbs(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );

      expect(tester.widget<IconButton>(_clearButton).tooltip, 'Clear text');
    });
  });

  group('disabled', () {
    testWidgets('disables the native text field', (tester) async {
      await pumpCbs(tester, child: _field(enabled: false));

      expect(_nativeField(tester).enabled, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('is enabled by default', (tester) async {
      await pumpCbs(tester, child: _field());

      expect(_nativeField(tester).enabled, isTrue);
    });

    testWidgets('does not take the focus when tapped', (tester) async {
      await pumpCbs(tester, child: _field(enabled: false));

      await tester.tap(_textField);
      await tester.pump();

      expect(_focusNodeInUse(tester).hasFocus, isFalse);
      expect(_focusNodeInUse(tester).canRequestFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('keeps its text and shows an inert clear action', (
      tester,
    ) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      final events = <String>[];
      await pumpCbs(
        tester,
        child: _field(
          controller: controller,
          enabled: false,
          onChanged: (text) => events.add('changed:$text'),
          onSubmitted: (text) => events.add('submitted:$text'),
          onClear: () => events.add('clear'),
        ),
      );

      expect(find.text(_prefilled), findsOneWidget);
      expect(_clearButton, findsOneWidget);
      expect(tester.widget<IconButton>(_clearButton).onPressed, isNull);

      await tester.tap(_clearButton, warnIfMissed: false);
      await tester.tap(_textField, warnIfMissed: false);
      await tester.pump();

      expect(controller.text, _prefilled);
      expect(events, isEmpty);
    });

    testWidgets('shows no clear action while empty', (tester) async {
      await pumpCbs(tester, child: _field(enabled: false));

      expect(_clearButton, findsNothing);
    });

    testWidgets('loses the focus when it becomes disabled', (tester) async {
      await pumpCbs(tester, child: _field(autofocus: true));
      await tester.pump();
      expect(_focusNodeInUse(tester).hasFocus, isTrue);

      await pumpCbs(tester, child: _field(autofocus: true, enabled: false));
      await tester.pump();

      expect(_focusNodeInUse(tester).hasFocus, isFalse);
    });

    testWidgets('becomes interactive again when it is enabled', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      var cleared = 0;
      await pumpCbs(
        tester,
        child: _field(
          controller: controller,
          enabled: false,
          onClear: () => cleared++,
        ),
      );

      await pumpCbs(
        tester,
        child: _field(controller: controller, onClear: () => cleared++),
      );
      await _tapClear(tester);

      expect(cleared, 1);
      expect(controller.text, isEmpty);
    });

    testWidgets('is exposed as a disabled text field', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(enabled: false, semanticLabel: _semanticLabel),
      );

      final node = tester.getSemantics(_textField);
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);

      semantics.dispose();
    });

    testWidgets('the focus traversal skips the disabled field and its clear '
        'action', (tester) async {
      await pumpA11y(
        tester,
        child: _field(
          controller: TextEditingController(text: _prefilled),
          enabled: false,
        ),
      );

      await _tab(tester);
      await _tab(tester);

      expect(_inputHasFocus(tester), isFalse);
      expect(_clearHasFocus(tester), isFalse);
    });
  });

  group('autofocus', () {
    testWidgets('takes the focus when it is true', (tester) async {
      await pumpCbs(tester, child: _field(autofocus: true));
      await tester.pump();

      expect(_focusNodeInUse(tester).hasFocus, isTrue);
      expect(_inputHasFocus(tester), isTrue);
      expect(_nativeField(tester).autofocus, isTrue);
    });

    testWidgets('does not take the focus by default', (tester) async {
      await pumpCbs(tester, child: _field());
      await tester.pump();

      expect(_focusNodeInUse(tester).hasFocus, isFalse);
      expect(_nativeField(tester).autofocus, isFalse);
    });

    testWidgets('shows the text input right away when it is true', (
      tester,
    ) async {
      final changes = <String>[];
      await pumpCbs(
        tester,
        child: _field(autofocus: true, onChanged: changes.add),
      );
      await tester.pump();

      expect(tester.testTextInput.isVisible, isTrue);

      await _type(tester, 'jazz');

      expect(changes, ['jazz']);
      expect(_clearButton, findsOneWidget);
    });

    testWidgets('works with an external controller', (tester) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: _field(controller: controller, autofocus: true),
      );
      await tester.pump();

      expect(_focusNodeInUse(tester).hasFocus, isTrue);
    });
  });

  group('accessibility', () {
    testWidgets('exposes a text field with the semantic label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(hintText: null, semanticLabel: _semanticLabel),
      );

      final node = tester.getSemantics(_textField);
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.label, contains(_semanticLabel));
      expect(find.bySemanticsLabel(RegExp(_semanticLabel)), findsWidgets);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      semantics.dispose();
    });

    testWidgets('the semantic label does not hide the text', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(
          controller: TextEditingController(text: _prefilled),
          semanticLabel: _semanticLabel,
        ),
      );

      final node = tester.getSemantics(_textField);
      expect(node.label, contains(_semanticLabel));
      expect(node.value, _prefilled);

      semantics.dispose();
    });

    testWidgets('keeps the label of the hint without a semantic label', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(tester, child: _field());

      // Without a semantic label there is no `Semantics` wrapper above the
      // `TextField`: the semantics node of the native field is owned by a
      // render object below the `TextField` element, and
      // `getSemantics(_textField)` would only walk up to an ancestor node.
      // The editable text sits inside that node, so it is queried instead.
      final node = tester.getSemantics(_editable);
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.label, contains(_hint));
      expect(node.label, isNot(contains(_semanticLabel)));

      semantics.dispose();
    });

    testWidgets('follows a new semantic label', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(hintText: null, semanticLabel: 'First label'),
      );
      await pumpCbs(
        tester,
        child: _field(hintText: null, semanticLabel: 'Second label'),
      );

      final node = tester.getSemantics(_textField);
      expect(node.label, contains('Second label'));
      expect(node.label, isNot(contains('First label')));

      semantics.dispose();
    });

    testWidgets('the typed text is the value of the text field', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(tester, child: _field(semanticLabel: _semanticLabel));

      await _type(tester, 'jazz');

      expect(tester.getSemantics(_textField).value, 'jazz');

      semantics.dispose();
    });

    testWidgets('the clear action is a button that can be tapped', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );

      final node = tester.getSemantics(_clearButton);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isTrue);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

      semantics.dispose();
    });

    testWidgets('the clear action is exposed as disabled when disabled', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpCbs(
        tester,
        child: _field(
          controller: TextEditingController(text: _prefilled),
          enabled: false,
        ),
      );

      final node = tester.getSemantics(_clearButton);
      expect(node.flagsCollection.isButton, isTrue);
      expect(node.flagsCollection.isEnabled, Tristate.isFalse);
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isFalse);

      semantics.dispose();
    });

    testWidgets('the semantic activation of the clear action clears', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      var cleared = 0;
      await pumpCbs(
        tester,
        child: _field(controller: controller, onClear: () => cleared++),
      );

      tester.semantics.tap(
        find.semantics.byPredicate((node) => node.flagsCollection.isButton),
      );
      await tester.pump();

      expect(controller.text, isEmpty);
      expect(cleared, 1);

      semantics.dispose();
    });

    for (final scale in cbsTestTextScales) {
      testWidgets('meets the tap target and label guidelines: text x$scale', (
        tester,
      ) async {
        final semantics = tester.ensureSemantics();
        await pumpA11y(
          tester,
          textScale: scale,
          child: _field(
            controller: TextEditingController(text: _prefilled),
            semanticLabel: _semanticLabel,
          ),
        );

        expectTapTargetEvaluated(tester, _textField);
        await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
        await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));

        semantics.dispose();
      });
    }

    testWidgets('the clear action is at least 48 x 48 logical pixels', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );

      final size = tester.getSize(_clearButton);
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    });
  });

  group('keyboard navigation and native text behavior', () {
    testWidgets('Tab gives the focus to the field', (tester) async {
      await pumpA11y(tester, child: _field());
      expect(_inputHasFocus(tester), isFalse);

      await _tab(tester);

      expect(_inputHasFocus(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('Tab goes from the field to the clear action and back', (
      tester,
    ) async {
      await pumpA11y(
        tester,
        child: _field(controller: TextEditingController(text: _prefilled)),
      );

      await _tab(tester);
      expect(_inputHasFocus(tester), isTrue);
      expect(_clearHasFocus(tester), isFalse);

      await _tab(tester);
      expect(_inputHasFocus(tester), isFalse);
      expect(_clearHasFocus(tester), isTrue);

      await _tab(tester, shift: true);
      expect(_inputHasFocus(tester), isTrue);
      expect(_clearHasFocus(tester), isFalse);
    });

    testWidgets('there is no clear action to reach while the text is empty', (
      tester,
    ) async {
      await pumpA11y(tester, child: _field());

      await _tab(tester);

      expect(_clearButton, findsNothing);
      expect(_inputHasFocus(tester), isTrue);
    });

    testWidgets('Enter and Space activate the focused clear action', (
      tester,
    ) async {
      for (final key in [LogicalKeyboardKey.enter, LogicalKeyboardKey.space]) {
        // A new tree each time: no focus is kept from the previous key.
        await tester.pumpWidget(const SizedBox.shrink());
        final controller = TextEditingController(text: _prefilled);
        addTearDown(controller.dispose);
        final events = <String>[];
        await pumpA11y(
          tester,
          child: _field(
            controller: controller,
            onChanged: (text) => events.add('changed:$text'),
            onClear: () => events.add('clear'),
          ),
        );

        await _tab(tester);
        await _tab(tester);
        expect(_clearHasFocus(tester), isTrue, reason: key.keyLabel);
        await _press(tester, key);

        expect(controller.text, isEmpty, reason: key.keyLabel);
        expect(events, ['changed:', 'clear'], reason: key.keyLabel);
        // The focus goes back to the text input, which stays usable.
        expect(_inputHasFocus(tester), isTrue, reason: key.keyLabel);
      }
    });

    testWidgets('keys do nothing before the clear action has the focus', (
      tester,
    ) async {
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      var cleared = 0;
      await pumpA11y(
        tester,
        child: _field(controller: controller, onClear: () => cleared++),
      );

      await _press(tester, LogicalKeyboardKey.enter);
      await _press(tester, LogicalKeyboardKey.space);

      expect(cleared, 0);
      expect(controller.text, _prefilled);
    });

    testWidgets('a tap gives the focus and shows the text input', (
      tester,
    ) async {
      await pumpCbs(tester, child: _field());

      await tester.tap(_textField);
      await tester.pump();

      expect(_inputHasFocus(tester), isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets(
      'the selection of the user is the selection of the controller',
      (tester) async {
        final controller = TextEditingController(text: _prefilled);
        addTearDown(controller.dispose);
        await pumpCbs(tester, child: _field(controller: controller));
        await tester.tap(_textField);
        await tester.pump();

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: _prefilled,
            selection: TextSelection(baseOffset: 0, extentOffset: 4),
          ),
        );
        await tester.pump();

        expect(
          controller.selection,
          const TextSelection(baseOffset: 0, extentOffset: 4),
        );
        expect(controller.text, _prefilled);
      },
    );

    testWidgets('select all, then typing, replaces the whole text', (
      tester,
    ) async {
      final changes = <String>[];
      final controller = TextEditingController(text: _prefilled);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        child: _field(controller: controller, onChanged: changes.add),
      );
      await tester.tap(_textField);
      await tester.pump();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _prefilled.length,
      );
      await tester.pump();

      tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: 'x',
          selection: TextSelection.collapsed(offset: 1),
        ),
      );
      await tester.pump();

      expect(controller.text, 'x');
      expect(changes, ['x']);
    });
  });

  group('themes', () {
    for (final variant in cbsTestThemes) {
      testWidgets('takes its icon and hint colors from the theme, like a '
          'native field: ${variant.name}', (tester) async {
        await pumpCbs(tester, theme: variant.theme, child: _referenceField());
        final referenceIcon = _iconColor(tester, _searchIcon);
        final referenceHint = _hintStyle(tester);

        await pumpCbs(tester, theme: variant.theme, child: _field());

        expect(referenceIcon, isNotNull);
        expect(_iconColor(tester, _searchIcon), referenceIcon);
        expect(_hintStyle(tester)?.color, referenceHint?.color);
        expect(_hintStyle(tester)?.fontSize, referenceHint?.fontSize);
        expect(tester.takeException(), isNull);
      });

      testWidgets('the disabled style is the one of the theme: '
          '${variant.name}', (tester) async {
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: TextField(
            enabled: false,
            decoration: InputDecoration(
              hintText: _hint,
              prefixIcon: const Icon(Icons.search),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(CbsRadius.pill),
              ),
            ),
          ),
        );
        final referenceIcon = _iconColor(tester, _searchIcon);

        await pumpCbs(
          tester,
          theme: variant.theme,
          child: _field(enabled: false),
        );

        expect(_iconColor(tester, _searchIcon), referenceIcon);
        expect(tester.takeException(), isNull);
      });

      testWidgets('typed text uses the text style of the theme: '
          '${variant.name}', (tester) async {
        await pumpCbs(tester, theme: variant.theme, child: const TextField());
        await tester.enterText(_textField, 'x');
        await tester.pump();
        final reference = tester.widget<EditableText>(_editable).style;

        await pumpCbs(
          tester,
          theme: variant.theme,
          child: _field(controller: TextEditingController(text: 'x')),
        );

        final style = tester.widget<EditableText>(_editable).style;
        expect(style.color, reference.color);
        expect(style.fontSize, reference.fontSize);
        expect(style.fontFamily, reference.fontFamily);
      });
    }

    testWidgets('follows the Branded typography', (tester) async {
      const brand = TextStyle(fontFamily: 'BrandFont', fontSize: 19);
      final theme = CbsTheme.branded(
        primaryColor: Colors.green,
        textTheme: const TextTheme(
          bodyLarge: brand,
          bodyMedium: brand,
          titleMedium: brand,
        ),
      );

      await pumpCbs(
        tester,
        theme: theme,
        child: _field(controller: TextEditingController(text: 'x')),
      );

      final style = tester.widget<EditableText>(_editable).style;
      expect(style.fontFamily, 'BrandFont');
      expect(style.fontSize, 19);
    });

    testWidgets('follows the InputDecorationTheme of the theme', (
      tester,
    ) async {
      final theme = CbsTheme.essentials().copyWith(
        inputDecorationTheme: const InputDecorationThemeData(
          filled: true,
          fillColor: Color(0xFF123456),
        ),
      );

      await pumpCbs(tester, theme: theme, child: _field());

      // The decoration that the native field really draws.
      final decorator = tester.widget<InputDecorator>(
        find.descendant(of: _textField, matching: find.byType(InputDecorator)),
      );
      expect(decorator.decoration.filled, isTrue);
      expect(decorator.decoration.fillColor, const Color(0xFF123456));
      expect(tester.takeException(), isNull);
    });

    for (final variant in cbsTestThemes) {
      testWidgets('shows the same behavior in every theme: ${variant.name}', (
        tester,
      ) async {
        final events = <String>[];
        await pumpCbs(
          tester,
          theme: variant.theme,
          child: _field(
            onChanged: (text) => events.add('changed:$text'),
            onClear: () => events.add('clear'),
          ),
        );

        await _type(tester, 'jazz');
        await _tapClear(tester);

        expect(events, ['changed:jazz', 'changed:', 'clear']);
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('widths and text scales', () {
    for (final width in cbsTestWidths) {
      for (final scale in cbsTestTextScales) {
        for (final variant in cbsTestThemes) {
          testWidgets('no overflow, full width: width ${width.round()}, '
              'text x$scale, ${variant.name}', (tester) async {
            final controller = TextEditingController(text: _prefilled);
            addTearDown(controller.dispose);
            await pumpCbs(
              tester,
              theme: variant.theme,
              width: width,
              textScale: scale,
              child: _field(controller: controller, hintText: _longHint),
            );

            expect(tester.takeException(), isNull);
            final rect = tester.getRect(_fieldFinder);
            expect(rect.left, 0);
            expect(rect.width, closeTo(width, _epsilon));
            expect(tester.getRect(_searchIcon).left, greaterThanOrEqualTo(0));
            expect(
              tester.getRect(_clearButton).right,
              lessThanOrEqualTo(width + _epsilon),
            );

            // The empty field, with a hint wider than the screen.
            controller.clear();
            await tester.pump();

            expect(tester.takeException(), isNull);
            expect(
              tester.getRect(_fieldFinder).width,
              closeTo(width, _epsilon),
            );
          });
        }
      }
    }

    for (final width in cbsTestWidths) {
      testWidgets('keeps the same height empty and filled: width '
          '${width.round()}', (tester) async {
        final controller = TextEditingController();
        addTearDown(controller.dispose);
        await pumpCbs(
          tester,
          width: width,
          child: _field(controller: controller),
        );
        final empty = tester.getSize(_fieldFinder);

        controller.text = _prefilled;
        await tester.pump();

        expect(tester.getSize(_fieldFinder), empty);
      });
    }

    testWidgets('the field follows the text scale', (tester) async {
      Future<Size> size(double scale) async {
        await pumpCbs(
          tester,
          textScale: scale,
          child: _field(controller: TextEditingController(text: _prefilled)),
        );
        return tester.getSize(_fieldFinder);
      }

      final x1 = await size(1);
      final x2 = await size(2);

      expect(x1.height, greaterThanOrEqualTo(kMinInteractiveDimension));
      expect(x2.height, greaterThan(x1.height));
      expect(x2.width, x1.width);
      expect(tester.takeException(), isNull);
    });

    testWidgets('the text scale is applied to the text of the field', (
      tester,
    ) async {
      Future<double> textHeight(double scale) async {
        await pumpCbs(
          tester,
          textScale: scale,
          child: _field(controller: TextEditingController(text: _prefilled)),
        );
        return tester.getSize(_editable).height;
      }

      final x1 = await textHeight(1);
      final x2 = await textHeight(2);

      expect(x2, greaterThan(x1 * 1.5));
    });

    testWidgets('a long text is scrolled inside the field, on one line', (
      tester,
    ) async {
      final controller = TextEditingController(text: _longHint * 3);
      addTearDown(controller.dispose);
      await pumpCbs(
        tester,
        width: 320,
        textScale: 2,
        child: _field(controller: controller),
      );

      expect(tester.takeException(), isNull);
      expect(tester.getSize(_fieldFinder).width, closeTo(320, _epsilon));
      expect(_nativeField(tester).maxLines, 1);
    });
  });

  group('right-to-left and left-to-right', () {
    Widget directed(TextDirection direction, Widget child) =>
        Directionality(textDirection: direction, child: child);

    testWidgets('left-to-right: the search icon is at the left, the clear '
        'action at the right', (tester) async {
      await pumpCbs(
        tester,
        child: directed(
          TextDirection.ltr,
          _field(controller: TextEditingController(text: _prefilled)),
        ),
      );

      final center = tester.getCenter(_textField).dx;
      expect(tester.getCenter(_searchIcon).dx, lessThan(center));
      expect(
        tester.getCenter(find.byIcon(Icons.clear)).dx,
        greaterThan(center),
      );
    });

    testWidgets('right-to-left: the search icon is at the right, the clear '
        'action at the left', (tester) async {
      await pumpCbs(
        tester,
        child: directed(
          TextDirection.rtl,
          _field(controller: TextEditingController(text: _prefilled)),
        ),
      );

      final center = tester.getCenter(_textField).dx;
      expect(tester.getCenter(_searchIcon).dx, greaterThan(center));
      expect(tester.getCenter(find.byIcon(Icons.clear)).dx, lessThan(center));
      expect(tester.takeException(), isNull);
    });

    testWidgets('right-to-left: the text input uses the direction of the '
        'context', (tester) async {
      await pumpCbs(tester, child: directed(TextDirection.rtl, _field()));

      expect(Directionality.of(tester.element(_editable)), TextDirection.rtl);
      expect(tester.widget<EditableText>(_editable).textDirection, isNull);
    });

    testWidgets('right-to-left: typing, clearing and submitting work', (
      tester,
    ) async {
      final events = <String>[];
      await pumpCbs(
        tester,
        child: directed(
          TextDirection.rtl,
          _field(
            onChanged: (text) => events.add('changed:$text'),
            onSubmitted: (text) => events.add('submitted:$text'),
            onClear: () => events.add('clear'),
          ),
        ),
      );

      await _type(tester, 'بحث');
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await tester.pump();
      await _tapClear(tester);

      expect(events, ['changed:بحث', 'submitted:بحث', 'changed:', 'clear']);
      expect(tester.takeException(), isNull);
    });

    for (final width in [cbsTestWidths.first, cbsTestWidths.last]) {
      testWidgets('right-to-left: no overflow at ${width.round()}, text x2', (
        tester,
      ) async {
        await pumpCbs(
          tester,
          width: width,
          textScale: 2,
          child: directed(
            TextDirection.rtl,
            _field(
              controller: TextEditingController(text: _prefilled),
              hintText: _longHint,
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        expect(tester.getSize(_fieldFinder).width, closeTo(width, _epsilon));
      });
    }
  });

  group('composition and non-regression of VP-01 to VP-05', () {
    testWidgets('lives in a CbsContentSection under the section spacing', (
      tester,
    ) async {
      await pumpCbs(
        tester,
        child: CbsContentSection(title: 'Recherche', child: _field()),
      );

      expect(tester.takeException(), isNull);
      final heading = tester.getRect(find.byType(CbsSectionHeading));
      final field = tester.getRect(_fieldFinder);
      expect(field.top - heading.bottom, closeTo(CbsSpacing.sm, _epsilon));
      expect(field.width, 600);
    });

    testWidgets('lives in the content of a CbsContentCard', (tester) async {
      await pumpCbs(tester, child: CbsContentCard(content: _field()));

      expect(tester.takeException(), isNull);
      expect(
        tester.getSize(_fieldFinder).width,
        closeTo(600 - 2 * CbsSpacing.md, _epsilon),
      );
    });

    testWidgets(
      'sits above a CbsCategorySelector and a CbsAdaptiveCollection',
      (tester) async {
        var selected = <String>{};
        await pumpCbs(
          tester,
          child: StatefulBuilder(
            builder: (context, setState) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _field(),
                const SizedBox(height: CbsSpacing.sm),
                CbsCategorySelector<String>(
                  options: const [
                    CbsCategoryOption<String>(value: 'a', label: 'A'),
                    CbsCategoryOption<String>(value: 'b', label: 'B'),
                  ],
                  selectedValues: selected,
                  onSelectionChanged: (values) =>
                      setState(() => selected = values),
                ),
                const SizedBox(height: CbsSpacing.md),
                const CbsAdaptiveCollection(
                  layout: CbsCollectionLayout.grid,
                  children: [
                    CbsContentCard(
                      media: CbsMediaFrame(
                        child: ColoredBox(color: Colors.grey),
                      ),
                      content: Text('Premier contenu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        final field = tester.getRect(_fieldFinder);
        final selector = tester.getRect(
          find.byType(CbsCategorySelector<String>),
        );
        expect(selector.top, closeTo(field.bottom + CbsSpacing.sm, _epsilon));

        // Both stay usable next to each other.
        await _type(tester, 'jazz');
        await tester.tap(find.text('B'));
        await tester.pump();
        expect(find.text('jazz'), findsOneWidget);
        expect(selected, {'b'});
      },
    );

    testWidgets('the VP-01 to VP-05 resources keep their defaults', (
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
      expect(CbsCategorySelectionMode.values, [
        CbsCategorySelectionMode.single,
        CbsCategorySelectionMode.multiple,
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
      expect(
        const CbsCategorySelector<String>(
          options: [],
          selectedValues: {},
          onSelectionChanged: null,
        ).mode,
        CbsCategorySelectionMode.single,
      );
    });
  });
}
