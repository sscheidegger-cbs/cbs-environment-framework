import 'catalog_entry.dart';
import 'sections/adaptive_collection_section.dart';
import 'sections/application_states_section.dart';
import 'sections/buttons_section.dart';
import 'sections/content_card_section.dart';
import 'sections/content_section_section.dart';
import 'sections/feedback_section.dart';
import 'sections/loading_section.dart';
import 'sections/media_frame_section.dart';
import 'sections/retry_message_section.dart';
import 'sections/section_heading_section.dart';
import 'sections/state_panel_section.dart';

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
  CatalogEntry(
    id: 'state-panel',
    title: 'State panel',
    builder: (_) => const StatePanelSection(),
  ),
  CatalogEntry(
    id: 'retry-message',
    title: 'Retry message',
    builder: (_) => const RetryMessageSection(),
  ),
  CatalogEntry(
    id: 'section-heading',
    title: 'Section heading',
    builder: (_) => const SectionHeadingSection(),
  ),
  CatalogEntry(
    id: 'application-states',
    title: 'Application states',
    builder: (_) => const ApplicationStatesSection(),
  ),
  CatalogEntry(
    id: 'content-card',
    title: 'Content card',
    builder: (_) => const ContentCardSection(),
  ),
  CatalogEntry(
    id: 'media-frame',
    title: 'Media frame',
    builder: (_) => const MediaFrameSection(),
  ),
  CatalogEntry(
    id: 'adaptive-collection',
    title: 'Adaptive collection',
    builder: (_) => const AdaptiveCollectionSection(),
  ),
  CatalogEntry(
    id: 'content-section',
    title: 'Content section',
    builder: (_) => const ContentSectionSection(),
  ),
];
