import '../services/collection_order.dart';

/// A move that cannot be done as asked; [message] says why and is safe to show as is.
final class MoveRefusedException implements Exception {
  final String message;
  const MoveRefusedException(this.message);

  @override
  String toString() => message;
}

/// What a move changed: the placements it replaced. Handing it back to
/// `CollectionOrderRepository.undo` puts every one of them back.
final class MoveReceipt {
  final List<Placement> replaced;

  /// The item moved to another collection, so the variables and auth it inherits are another collection's now.
  final bool changedCollection;

  const MoveReceipt({required this.replaced, this.changedCollection = false});

  /// A move onto the spot the item already had: nothing was written and there is nothing to undo.
  bool get isNoop => replaced.isEmpty;
}
