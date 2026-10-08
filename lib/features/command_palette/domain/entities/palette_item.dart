import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../../core/platform/platform_support.dart';

enum PaletteCategory {
  tools('Developer tools'),
  requests('Requests'),
  environments('Environments'),
  app('App');

  const PaletteCategory(this.label);
  final String label;
}

/// One thing the palette can do or open.
final class PaletteItem {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final PaletteCategory category;

  /// Extra words the search should match (`dart flutter model json`).
  final List<String> keywords;

  /// Text searched with low weight (a request's URL or body), never shown.
  final String hiddenText;

  /// A method badge shown instead of the icon (requests).
  final String? badge;
  final String? shortcut;

  /// What the entry needs from the platform (the desktop app, for a local server). Where that is missing the palette still
  /// lists it, greyed out and saying why, instead of opening a dialog that cannot work.
  final PlatformFeature? requires;

  /// Called with the context of the screen the palette was opened from, after the palette closed.
  final void Function(BuildContext context) run;

  const PaletteItem({
    required this.id,
    required this.title,
    required this.run,
    this.subtitle = '',
    this.icon = Icons.bolt,
    this.category = PaletteCategory.tools,
    this.keywords = const [],
    this.hiddenText = '',
    this.badge,
    this.shortcut,
    this.requires,
  });

  /// Why this entry cannot be used here, or null when it can. [web] is only passed in tests.
  String? unavailableReason({bool web = kIsWeb}) => requires?.reason(web: web);
}
