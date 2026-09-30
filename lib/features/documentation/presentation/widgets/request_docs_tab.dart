import 'package:flutter/material.dart';
import '../../domain/entities/entity_kind.dart';
import 'entity_docs_form.dart';

/// The "Docs" tab of the request builder: description and tags of one request,
/// saved automatically. Designed to sit inside the page's scroll view.
class RequestDocsTab extends StatelessWidget {
  final int requestId;
  const RequestDocsTab({super.key, required this.requestId});

  @override
  Widget build(BuildContext context) => EntityDocsForm(kind: EntityKind.request, localId: requestId);
}
