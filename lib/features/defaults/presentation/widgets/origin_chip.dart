import 'package:flutter/material.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../domain/entities/defaults_origin.dart';

/// Where an inherited value was set: `folder "Auth"` or `collection "Shop"`.
class OriginChip extends StatelessWidget {
  final DefaultsOrigin origin;
  const OriginChip({super.key, required this.origin});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Set in the ${origin.label}',
        child: StatusChip(
          label: origin.fromLabel,
          icon: origin.isFolder ? Icons.folder_outlined : Icons.collections_bookmark_outlined,
        ),
      );
}
