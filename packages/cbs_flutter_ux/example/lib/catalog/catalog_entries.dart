import 'catalog_entry.dart';
import 'sections/buttons_section.dart';
import 'sections/feedback_section.dart';
import 'sections/loading_section.dart';

/// Ordered list of the catalog sections.
///
/// To add a section: create its widget under `sections/`, then append
/// one [CatalogEntry] here.
final List<CatalogEntry> catalogEntries = <CatalogEntry>[
  CatalogEntry(
    id: 'buttons',
    title: 'Buttons',
    builder: (_) => const ButtonsSection(),
  ),
  CatalogEntry(
    id: 'loading',
    title: 'Loading indicators',
    builder: (_) => const LoadingSection(),
  ),
  CatalogEntry(
    id: 'feedback',
    title: 'Feedback messages',
    builder: (_) => const FeedbackSection(),
  ),
];
