import 'package:flutter/material.dart';

import '../../foundation/tokens/cbs_radius.dart';

/// Generic search field: a native Material [TextField] with a search icon
/// and a clear action.
///
/// Presentation only: it knows no business model, runs no search, offers no
/// suggestion or filter, calls no API and performs no navigation. The
/// consuming application reacts to [onChanged] and [onSubmitted] and decides
/// what a search means. It wraps Flutter primitives ([TextField],
/// [InputDecoration], [IconButton], [Icon]) and adds only the clear action.
///
/// Controller: when [controller] is provided, it is the source of truth of
/// the text and is only listened to: the field never disposes it, whatever
/// happens to the field. When it is null, the field creates and owns an
/// internal controller, which it disposes with itself. Providing, replacing
/// or removing [controller] between two builds is supported: the owner of a
/// controller is always the one that created it.
///
/// Text: [onChanged] is called by the native text input at each edit made by
/// the user (typing, deleting, pasting, cutting, autofill). Like
/// [TextField.onChanged] it is not called when the application changes the
/// text of [controller] itself. [onSubmitted] is called with the current text
/// when the user submits it from the keyboard; the keyboard action is
/// [TextInputAction.search].
///
/// Clear action: an [IconButton] is shown at the end of the field while the
/// text is not empty, including when the text was set through [controller].
/// Activating it empties the text, gives the focus back to the field so that
/// typing can go on, calls [onChanged] with an empty string, then calls
/// [onClear] when it is provided. When the text is empty the action is not
/// drawn, but the space it uses is kept: the field does not change its layout
/// while the user types.
///
/// Disabled: when [enabled] is false the field does not take the focus, does
/// not accept input or selection, and the clear action, still drawn when the
/// text is not empty, is not interactive. Both use the disabled style of the
/// active [ThemeData].
///
/// Theme and layout: colors, text style, cursor, icons and focus indicator
/// come from the active [ThemeData] (Essentials or Branded, light or dark);
/// the field overrides none of them. Only its pill shape comes from
/// [CbsRadius.pill]. The field takes the full width allowed by its parent and
/// the height of a native [TextField], which follows the text scale of the
/// device. Like every Material text field, it needs a [Material] ancestor,
/// which a [Scaffold] provides.
///
/// Direction: the search icon is at the start edge and the clear action at
/// the end edge, in left-to-right and right-to-left contexts alike. The text
/// follows the [Directionality] of the context.
///
/// Accessibility: the field keeps the semantics of a native text field. When
/// [semanticLabel] is provided it is added to them as the label of the field;
/// without it, the field exposes the label that [TextField] derives from
/// [hintText]. The search icon is decorative. The clear action is a button
/// whose tooltip, "Clear text" in the language of the application, comes from
/// [MaterialLocalizations]. Focus traversal, selection, text editing
/// shortcuts and context menu are those of [TextField].
///
/// [CbsSearchField] is a [StatelessWidget]. The state it needs (the internal
/// controller and the focus node) lives in a private widget it builds; it is
/// not part of the public contract.
class CbsSearchField extends StatelessWidget {
  const CbsSearchField({
    super.key,
    this.controller,
    this.hintText,
    this.enabled = true,
    this.autofocus = false,
    this.onChanged,
    this.onSubmitted,
    this.onClear,
    this.semanticLabel,
  });

  /// Controller of the text, provided and owned by the consuming application.
  /// When it is null, the field uses an internal controller that it disposes
  /// itself. A provided controller is never disposed by the field.
  final TextEditingController? controller;

  /// Text shown while the field is empty, in the language of the consuming
  /// application. Nothing is shown when it is null.
  final String? hintText;

  /// Whether the field accepts input and interactions. Defaults to true.
  final bool enabled;

  /// Whether the field takes the focus when it is first built. Defaults to
  /// false.
  final bool autofocus;

  /// Called with the new text at each edit made by the user, and with an
  /// empty string when the clear action empties the text.
  final ValueChanged<String>? onChanged;

  /// Called with the current text when the user submits it from the keyboard.
  final ValueChanged<String>? onSubmitted;

  /// Called after the clear action emptied the text and after [onChanged]
  /// was called with an empty string.
  final VoidCallback? onClear;

  /// Label of the field announced by assistive technologies, added to the
  /// semantics of the native text field.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    return _SearchFieldResources(controller: controller, builder: _buildField);
  }

  Widget _buildField(
    BuildContext context,
    TextEditingController effectiveController,
    FocusNode focusNode,
  ) {
    final field = TextField(
      controller: effectiveController,
      focusNode: focusNode,
      enabled: enabled,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hintText,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(CbsRadius.pill),
        ),
        prefixIcon: const Icon(Icons.search),
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: effectiveController,
          builder: (context, value, _) {
            if (value.text.isEmpty) return const SizedBox.shrink();
            return IconButton(
              icon: const Icon(Icons.clear),
              tooltip: MaterialLocalizations.of(context).clearButtonTooltip,
              onPressed: enabled
                  ? () => _clear(effectiveController, focusNode)
                  : null,
            );
          },
        ),
      ),
    );

    final label = semanticLabel;
    if (label == null) return field;
    return Semantics(label: label, child: field);
  }

  /// Empties [textController], gives the focus back to the field, then
  /// notifies the application.
  ///
  /// `TextEditingController.clear` does not go through the text input, so
  /// [TextField.onChanged] is not called: the empty text is reported here.
  void _clear(TextEditingController textController, FocusNode focusNode) {
    textController.clear();
    focusNode.requestFocus();
    onChanged?.call('');
    onClear?.call();
  }
}

/// Builds the content of a [CbsSearchField] from the controller to use and
/// the focus node of the field.
typedef _SearchFieldBuilder = Widget Function(
  BuildContext context,
  TextEditingController controller,
  FocusNode focusNode,
);

/// Private composition owning what a [CbsSearchField] creates itself.
///
/// - The [FocusNode] of the field is always created here and disposed here.
/// - The [TextEditingController] is created here only while no controller is
///   provided, and disposed here as soon as one is provided, or with this
///   widget. A provided controller is never disposed.
class _SearchFieldResources extends StatefulWidget {
  const _SearchFieldResources({
    required this.controller,
    required this.builder,
  });

  final TextEditingController? controller;
  final _SearchFieldBuilder builder;

  @override
  State<_SearchFieldResources> createState() => _SearchFieldResourcesState();
}

class _SearchFieldResourcesState extends State<_SearchFieldResources> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'CbsSearchField');

  /// Internal controller: not null exactly while no controller is provided.
  TextEditingController? _ownedController;

  @override
  void initState() {
    super.initState();
    if (widget.controller == null) {
      _ownedController = TextEditingController();
    }
  }

  @override
  void didUpdateWidget(_SearchFieldResources oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller == null) {
      // The application withdrew its controller: keep the text the user sees
      // in a controller owned from now on by this state.
      _ownedController ??= TextEditingController.fromValue(
        oldWidget.controller?.value,
      );
    } else if (_ownedController != null) {
      // The application now provides a controller: the internal one is no
      // longer used. Only this state ever owned it.
      _ownedController!.dispose();
      _ownedController = null;
    }
  }

  @override
  void dispose() {
    // Never the controller provided by the application.
    _ownedController?.dispose();
    _ownedController = null;
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      widget.controller ?? _ownedController!,
      _focusNode,
    );
  }
}
