import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/entity_kind.dart';
import '../view_models/all_tags_view_model.dart';
import '../view_models/entity_docs_view_model.dart';
import '../view_models/tags_view_model.dart';
import 'markdown_editor.dart';
import 'tags_editor.dart';

/// The description editor and the tags of one collection, folder or request.
/// Both save on their own; a plain column, meant to sit inside a scroll view.
class EntityDocsForm extends StatefulWidget {
  final EntityKind kind;
  final int localId;

  /// Keyed by what it edits, so showing another entity starts from scratch.
  EntityDocsForm({required this.kind, required this.localId}) : super(key: ValueKey((kind, localId)));

  @override
  State<EntityDocsForm> createState() => _EntityDocsFormState();
}

class _EntityDocsFormState extends State<EntityDocsForm> with WidgetsBindingObserver {
  late final EntityDocsViewModel _docs;
  late final TagsViewModel _tags;
  late final AllTagsViewModel _allTags;

  @override
  void initState() {
    super.initState();
    _docs = locator<EntityDocsViewModel>(param1: widget.kind, param2: widget.localId);
    _tags = locator<TagsViewModel>(param1: widget.kind, param2: widget.localId);
    _allTags = locator<AllTagsViewModel>();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _docs.dispose();
    _tags.dispose();
    _allTags.dispose();
    super.dispose();
  }

  /// A page that is being closed or a window that is going away gets no
  /// dispose, so text still waiting for its save is written as the app leaves.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) unawaited(_docs.flush());
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<EntityDocsViewModel>.value(value: _docs),
        ChangeNotifierProvider<TagsViewModel>.value(value: _tags),
        ChangeNotifierProvider<AllTagsViewModel>.value(value: _allTags),
      ],
      child: const _EntityDocsFormBody(),
    );
  }
}

class _EntityDocsFormBody extends StatelessWidget {
  const _EntityDocsFormBody();

  @override
  Widget build(BuildContext context) {
    final docs = context.watch<EntityDocsViewModel>();
    final tags = context.watch<TagsViewModel>();
    final allTags = context.watch<AllTagsViewModel>();
    final caption = context.textStyles.caption.copyWith(color: context.colors.secondaryText);
    final error = context.textStyles.caption.copyWith(color: context.colors.statusError);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Description', style: context.textStyles.heading),
        Text('Markdown is supported. Changes are saved automatically.', style: caption),
        const SizedBox(height: 8),
        if (docs.isLoading)
          const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))
        else
          MarkdownEditor(initialValue: docs.markdown, onChanged: docs.update),
        if (docs.saveError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(docs.saveError!, style: error)),
        const SizedBox(height: 24),
        Text('Tags', style: context.textStyles.heading),
        Text('Group APIs by tags such as v2 or v3, then filter the sidebar by them.', style: caption),
        const SizedBox(height: 8),
        TagsEditor(tags: tags.tags, suggestions: allTags.tags, onAdd: tags.add, onRemove: tags.remove),
        if (tags.saveError != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(tags.saveError!, style: error)),
      ],
    );
  }
}
