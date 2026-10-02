import 'package:flutter/material.dart';

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
  });
}
