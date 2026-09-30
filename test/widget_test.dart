// Smoke test for a widget that needs no database/DI setup. A full app-level
// test needs an in-memory AppDatabase and mocked path_provider — worth adding
// once persistence tests are a priority, not part of this scaffold.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/http_method.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/method_dropdown.dart';

void main() {
  testWidgets('MethodDropdown shows the selected method and reports changes', (tester) async {
    HttpMethod? changedTo;

    // MethodDropdown reads AppColors/AppTextStyles off the Theme, so the
    // test needs the real app theme, not MaterialApp's bare default.
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Scaffold(
        body: MethodDropdown(value: HttpMethod.get, onChanged: (m) => changedTo = m),
      ),
    ));

    expect(find.text('GET'), findsOneWidget);

    await tester.tap(find.text('GET'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('POST').last);
    await tester.pumpAndSettle();

    expect(changedTo, HttpMethod.post);
  });
}
