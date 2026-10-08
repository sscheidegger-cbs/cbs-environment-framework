import 'package:flutter/material.dart';

/// Reusable primary action button for CBS Flutter applications.
///
/// Visual styling is inherited from the application's Material theme.
class CbsButton extends StatelessWidget {
  const CbsButton({required this.label, required this.onPressed, super.key});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return FilledButton(onPressed: onPressed, child: Text(label));
  }
}
