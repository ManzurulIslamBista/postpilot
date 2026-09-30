import 'package:flutter/material.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/theme/context_theme_extensions.dart';

class MethodDropdown extends StatelessWidget {
  final HttpMethod value;
  final ValueChanged<HttpMethod> onChanged;

  const MethodDropdown({super.key, required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return DropdownButtonHideUnderline(
      child: DropdownButton<HttpMethod>(
        value: value,
        onChanged: (m) => m == null ? null : onChanged(m),
        items: [
          for (final method in HttpMethod.values)
            DropdownMenuItem(
              value: method,
              child: Text(
                method.label,
                style: context.textStyles.body.copyWith(
                  color: context.colors.forMethod(method.label),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
