import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import '../catalog_demo.dart';
import '../catalog_keys.dart';

/// Demonstration of [CbsSearchField].
///
/// The public API exposes an optional `controller`, a `hintText`, the
/// `enabled` and `autofocus` flags, the `onChanged`, `onSubmitted` and
/// `onClear` callbacks and a `semanticLabel`. The field runs no search and
/// calls no backend: every demonstration below is a small parent that owns
/// its own state, as an application would, and shows what the field reported
/// in a readout under it. The Essentials and Branded designs, the light and
/// dark appearances, the widths and the text scales of the catalog controls
/// apply to every demonstration. Every text drawn here belongs to the example
/// and is CBS demonstration data: it does not come from any application.
class SearchFieldSection extends StatelessWidget {
  const SearchFieldSection({super.key});

  /// Hint of the plain demonstrations.
  static const String hint = 'Search';

  /// Semantic label of `search-empty`.
  static const String emptySemanticLabel = 'Search the catalog';

  /// Text of the prefilled demonstrations.
  static const String prefilledText = 'Jazz concert';

  /// Text that `search-prefilled` sets from outside the field.
  static const String replacementText = 'Opera night';

  /// Label of the button of `search-prefilled`.
  static const String replaceButtonLabel = 'Set text from outside';

  /// Hint wider than a 320 px screen, of `search-long`.
  static const String longHint =
      'Search for events, venues, artists, categories and everything else '
      'that is described in this catalog, whatever its length';

  /// Text of `search-long-text`, wider than a 320 px screen.
  static const String longText =
      'A search text that is intentionally long, to check that the field '
      'keeps its height and scrolls its text instead of overflowing';

  /// Readout of `search-interactive`.
  static String changesText(int changes, String text) =>
      'Changes: $changes · Text: "$text"';

  /// Readout of `search-prefilled`: the text of the external controller.
  static String controllerText(String text) => 'Controller text: "$text"';

  /// Readout of `search-submit`.
  static String submittedText(String? submitted) =>
      'Submitted: ${submitted ?? 'none'}';

  /// Readout of `search-clear`.
  static String clearText(int clears, int changes, String text) =>
      'Clears: $clears · Changes: $changes · Text: "$text"';

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CatalogDemo(
          id: 'search-empty',
          label: 'Empty field: hint, search icon, no clear action',
          child: _SearchDemo(
            id: 'search-empty',
            hintText: hint,
            semanticLabel: emptySemanticLabel,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-interactive',
          label: 'Interactive typing: the clear action follows the text',
          child: _SearchDemo(
            id: 'search-interactive',
            hintText: hint,
            readout: _Readout.changes,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-prefilled',
          label: 'Prefilled text from an external controller',
          child: _SearchDemo(
            id: 'search-prefilled',
            hintText: hint,
            initialText: prefilledText,
            readout: _Readout.controller,
            canReplaceText: true,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-clear',
          label: 'Clear action: empties the text, reports it, then onClear',
          child: _SearchDemo(
            id: 'search-clear',
            hintText: hint,
            initialText: prefilledText,
            readout: _Readout.clear,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-disabled',
          label: 'Disabled field: text kept, no input, inert clear action',
          child: _SearchDemo(
            id: 'search-disabled',
            hintText: hint,
            initialText: prefilledText,
            enabled: false,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-submit',
          label: 'Submission from the keyboard (search action)',
          child: _SearchDemo(
            id: 'search-submit',
            hintText: hint,
            readout: _Readout.submit,
          ),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-long',
          label: 'Long hint: one line, the height of the field is unchanged',
          child: _SearchDemo(id: 'search-long', hintText: longHint),
        ),
        catalogDemoGap,
        CatalogDemo(
          id: 'search-long-text',
          label: 'Long text: one line, scrolled inside the field',
          child: _SearchDemo(
            id: 'search-long-text',
            hintText: hint,
            initialText: longText,
          ),
        ),
      ],
    );
  }
}

/// What a demonstration shows under its field.
enum _Readout {
  /// Nothing.
  none,

  /// Number of `onChanged` calls and the last text they reported.
  changes,

  /// Text of the external controller.
  controller,

  /// Last text reported by `onSubmitted`.
  submit,

  /// Number of `onClear` calls, of `onChanged` calls and the last text.
  clear,
}

/// Search field owned by a parent that records what the field reports.
///
/// The example (the consumer) owns the controller of the demonstrations that
/// have an [initialText]: it creates it and disposes it. The other
/// demonstrations give no controller and let the field manage its own.
class _SearchDemo extends StatefulWidget {
  const _SearchDemo({
    required this.id,
    this.hintText,
    this.semanticLabel,
    this.initialText,
    this.enabled = true,
    this.readout = _Readout.none,
    this.canReplaceText = false,
  });

  final String id;
  final String? hintText;
  final String? semanticLabel;
  final String? initialText;
  final bool enabled;
  final _Readout readout;
  final bool canReplaceText;

  @override
  State<_SearchDemo> createState() => _SearchDemoState();
}

class _SearchDemoState extends State<_SearchDemo> {
  TextEditingController? _controller;
  String _text = '';
  int _changes = 0;
  int _clears = 0;
  String? _submitted;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialText;
    if (initial != null) {
      _controller = TextEditingController(text: initial);
      _text = initial;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CbsSearchField(
          controller: _controller,
          hintText: widget.hintText,
          semanticLabel: widget.semanticLabel,
          enabled: widget.enabled,
          onChanged: (text) => setState(() {
            _text = text;
            _changes++;
          }),
          onSubmitted: (text) => setState(() => _submitted = text),
          onClear: () => setState(() => _clears++),
        ),
        if (widget.readout != _Readout.none) ...[
          const SizedBox(height: CbsSpacing.sm),
          _readout(),
        ],
        if (widget.canReplaceText) ...[
          const SizedBox(height: CbsSpacing.sm),
          CbsButton(
            label: SearchFieldSection.replaceButtonLabel,
            onPressed: () =>
                _controller!.text = SearchFieldSection.replacementText,
          ),
        ],
      ],
    );
  }

  Widget _readout() {
    final key = CatalogKeys.counter(widget.id);
    return switch (widget.readout) {
      _Readout.none => const SizedBox.shrink(),
      _Readout.controller => ListenableBuilder(
        listenable: _controller!,
        builder: (_, _) => Text(
          SearchFieldSection.controllerText(_controller!.text),
          key: key,
        ),
      ),
      _Readout.changes => Text(
        SearchFieldSection.changesText(_changes, _text),
        key: key,
      ),
      _Readout.submit => Text(
        SearchFieldSection.submittedText(_submitted),
        key: key,
      ),
      _Readout.clear => Text(
        SearchFieldSection.clearText(_clears, _changes, _text),
        key: key,
      ),
    };
  }
}
