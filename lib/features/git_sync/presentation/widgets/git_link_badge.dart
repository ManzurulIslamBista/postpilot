import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../view_models/linked_collections_view_model.dart';

class GitLinkBadge extends StatelessWidget {
  final int collectionId;
  const GitLinkBadge(this.collectionId, {super.key});

  @override
  Widget build(BuildContext context) {
    // Nullable on purpose: without a provider (tests, or before app.dart provides it) the badge just stays hidden.
    final linked = context.select<LinkedCollectionsViewModel?, bool>((vm) => vm?.isLinked(collectionId) ?? false);
    if (!linked) return const SizedBox.shrink();
    return Tooltip(
      message: 'Synced with Git',
      child: Icon(Icons.merge_type, size: 16, color: context.colors.mainAccent),
    );
  }
}
