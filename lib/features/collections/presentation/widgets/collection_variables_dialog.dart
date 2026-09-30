import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../domain/entities/collection_variable_entity.dart';
import '../../domain/repositories/collection_variable_repository.dart';

/// Lists, adds, edits and deletes the `{{variables}}` scoped to one
/// collection — overridden by the active environment, but ahead of globals,
/// when a request is sent.
class CollectionVariablesDialog extends StatefulWidget {
  final int collectionId;
  final String collectionName;
  const CollectionVariablesDialog({super.key, required this.collectionId, required this.collectionName});

  static Future<void> show(BuildContext context, {required int collectionId, required String collectionName}) =>
      showDialog(
        context: context,
        builder: (_) => CollectionVariablesDialog(collectionId: collectionId, collectionName: collectionName),
      );

  @override
  State<CollectionVariablesDialog> createState() => _CollectionVariablesDialogState();
}

class _CollectionVariablesDialogState extends State<CollectionVariablesDialog> {
  late final _CollectionVariablesViewModel _viewModel;

  @override
  void initState() {
    super.initState();
    _viewModel = _CollectionVariablesViewModel(locator<CollectionVariableRepository>(), widget.collectionId);
  }

  @override
  void dispose() {
    _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<_CollectionVariablesViewModel>.value(
      value: _viewModel,
      child: Consumer<_CollectionVariablesViewModel>(
        builder: (context, vm, _) => Dialog(
          child: SizedBox(
            width: 560,
            height: 420,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text('Variables · ${widget.collectionName}',
                            style: context.textStyles.heading, overflow: TextOverflow.ellipsis),
                      ),
                      IconButton(icon: const Icon(Icons.close), tooltip: 'Close', onPressed: () => Navigator.pop(context)),
                    ],
                  ),
                  Text(
                    'Override globals for every request in this collection; the active environment overrides these.',
                    style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
                  ),
                  const Divider(),
                  Expanded(
                    child: vm.variables.isEmpty
                        ? Center(
                            child: Text('No variables yet',
                                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
                          )
                        : ListView(
                            children: [
                              for (final v in vm.variables) _CollectionVariableRow(key: ValueKey(v.id), vm: vm, variable: v),
                            ],
                          ),
                  ),
                  TextButton.icon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add variable'),
                    onPressed: () => vm.upsert(CollectionVariableEntity(
                      id: 0,
                      collectionId: widget.collectionId,
                      key: '',
                      value: '',
                      enabled: true,
                    )),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

final class _CollectionVariablesViewModel with ChangeNotifier {
  final CollectionVariableRepository _repository;

  _CollectionVariablesViewModel(this._repository, int collectionId) {
    _variablesSub = _repository.watchByCollection(collectionId).listen((value) {
      variables = value;
      notifyListeners();
    });
  }

  List<CollectionVariableEntity> variables = [];
  late final StreamSubscription<List<CollectionVariableEntity>> _variablesSub;

  Future<void> upsert(CollectionVariableEntity variable) => _repository.upsert(variable);
  Future<void> delete(int id) => _repository.delete(id);

  @override
  void dispose() {
    _variablesSub.cancel();
    super.dispose();
  }
}

/// Stateful for the same reason as the environments manager's variable row:
/// [vm.upsert] round-trips through the DB before [variable] reflects an
/// edit, so one local, synchronously-updated copy is the base for every
/// edit, keeping a fast key-edit and value-edit from clobbering each other.
class _CollectionVariableRow extends StatefulWidget {
  final _CollectionVariablesViewModel vm;
  final CollectionVariableEntity variable;
  const _CollectionVariableRow({super.key, required this.vm, required this.variable});

  @override
  State<_CollectionVariableRow> createState() => _CollectionVariableRowState();
}

class _CollectionVariableRowState extends State<_CollectionVariableRow> {
  late CollectionVariableEntity _local = widget.variable;

  void _apply({String? key, String? value, bool? enabled}) {
    _local = CollectionVariableEntity(
      id: _local.id,
      collectionId: _local.collectionId,
      key: key ?? _local.key,
      value: value ?? _local.value,
      enabled: enabled ?? _local.enabled,
    );
    widget.vm.upsert(_local);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(value: _local.enabled, onChanged: (v) => setState(() => _apply(enabled: v))),
          Expanded(
            child: TextFormField(
              initialValue: _local.key,
              decoration: const InputDecoration(hintText: 'Key', isDense: true),
              onChanged: (v) => _apply(key: v),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              initialValue: _local.value,
              decoration: const InputDecoration(hintText: 'Value', isDense: true),
              onChanged: (v) => _apply(value: v),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 16),
            tooltip: 'Delete variable',
            onPressed: () async {
              final confirmed =
                  await showConfirmDialog(context, title: 'Delete variable', message: 'Delete "${_local.key}"?');
              if (confirmed) await widget.vm.delete(_local.id);
            },
          ),
        ],
      ),
    );
  }
}
