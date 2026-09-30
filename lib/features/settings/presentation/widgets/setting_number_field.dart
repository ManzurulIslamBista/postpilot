import 'package:flutter/material.dart';
import 'synced_text_field.dart';

/// A whole-number field. Clearing it changes nothing; the stored value comes
/// back into the field once it loses focus.
class SettingNumberField extends StatelessWidget {
  final int value;
  final ValueChanged<int> onChanged;
  final String? labelText;
  final String? suffixText;
  final double width;
  final bool enabled;

  const SettingNumberField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.suffixText,
    this.width = 120,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: SyncedTextField(
        value: '$value',
        digitsOnly: true,
        enabled: enabled,
        labelText: labelText,
        suffixText: suffixText,
        onChanged: (text) {
          final number = int.tryParse(text);
          if (number != null) onChanged(number);
        },
      ),
    );
  }
}
