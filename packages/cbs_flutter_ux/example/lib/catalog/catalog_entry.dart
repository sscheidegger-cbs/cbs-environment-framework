import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'package:flutter/material.dart';

import 'catalog_keys.dart';

/// Explicit entry of the catalog: an identifier, a title and a builder.
///
/// The catalog is a plain list of entries (see `catalogEntries`);
/// there is deliberately no registry, composition engine or dynamic
/// configuration.
@immutable
class CatalogEntry {
  const CatalogEntry({
    required this.id,
    required this.title,
    required this.builder,
  });

  /// Stable identifier, used to build the section [Key].
  final String id;

  /// Section title displayed above the demonstrations.
  final String title;

  /// Builds the demonstrations of this entry.
  final WidgetBuilder builder;
}

/// Titled section rendering one [CatalogEntry].
class CatalogSection extends StatelessWidget {
  const CatalogSection({required this.entry, super.key});

  final CatalogEntry entry;

  @override
  Widget build(BuildContext context) {
    return Column(
      key: CatalogKeys.section(entry.id),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(entry.title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: CbsSpacing.md),
        entry.builder(context),
      ],
    );
  }
}
