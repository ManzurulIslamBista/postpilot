import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text field that follows [value] whenever it is not being edited, so a
/// change made elsewhere (a reset, a number clamped to its range) reaches the
/// field without ever rewriting what the user is in the middle of typing.
class SyncedTextField extends StatefulWidget {
  final String value;
  final ValueChanged<String> onChanged;
  final String? labelText;
  final String? hintText;
  final String? suffixText;
  final Widget? suffixIcon;
  final bool obscureText;
  final bool digitsOnly;
  final bool enabled;

  const SyncedTextField({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelText,
    this.hintText,
    this.suffixText,
    this.suffixIcon,
    this.obscureText = false,
    this.digitsOnly = false,
    this.enabled = true,
  });

  @override
  State<SyncedTextField> createState() => _SyncedTextFieldState();
}

class _SyncedTextFieldState extends State<SyncedTextField> {
  late final TextEditingController _controller = TextEditingController(text: widget.value);
  late final FocusNode _focusNode = FocusNode()..addListener(_onFocusChanged);

  @override
  void didUpdateWidget(covariant SyncedTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_focusNode.hasFocus) _adopt(widget.value);
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) _adopt(widget.value);
  }

  void _adopt(String value) {
    if (_controller.text != value) _controller.text = value;
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      obscureText: widget.obscureText,
      keyboardType: widget.digitsOnly ? TextInputType.number : null,
      inputFormatters: widget.digitsOnly
          ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(7)]
          : null,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        suffixText: widget.suffixText,
        suffixIcon: widget.suffixIcon,
      ),
      onChanged: widget.onChanged,
    );
  }
}
