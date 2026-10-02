import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/theme/app_colors.dart';
import 'package:postpilot/features/collections/domain/entities/collection_variable_entity.dart';
import 'package:postpilot/features/environments/domain/entities/environment_entity.dart';
import 'package:postpilot/features/request_builder/domain/usecases/list_variables_usecase.dart';
import 'package:postpilot/features/request_builder/presentation/view_models/variable_scope.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/variables/variable_hover_card.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/variables/variable_text_controller.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/variables/variable_text_form_field.dart';
import 'package:provider/provider.dart';

import 'documentation/support/pump_app.dart';
import 'support/in_memory_import_export_fakes.dart';

void main() {
  late InMemoryDb db;
  late VariableScope scope;

  setUp(() {
    db = InMemoryDb();
    final envId = db.nextId();
    db.environments.add(EnvironmentEntity(id: envId, name: 'Testing', isActive: true));
    db.environmentVariables
      ..add(
        EnvironmentVariableEntity(
          id: db.nextId(),
          environmentId: envId,
          key: 'baseUrl',
          value: 'https://api.test',
          isSecret: false,
          enabled: true,
        ),
      )
      ..add(
        EnvironmentVariableEntity(
          id: db.nextId(),
          environmentId: envId,
          key: 'token',
          value: 'sup3r-s3cret-value',
          isSecret: true,
          enabled: true,
        ),
      );
    db.variables.add(
      CollectionVariableEntity(id: db.nextId(), collectionId: 1, key: 'page', value: '2', enabled: true),
    );
    scope = VariableScope(
      ListVariablesUseCase(db.collectionVariableRepository, db.environmentRepository, db.globalVariableRepository),
    );
    addTearDown(scope.dispose);
  });

  Future<void> loadScope(WidgetTester tester) async {
    await tester.runAsync(() async {
      scope.bindCollection(1);
      await scope.refresh();
    });
  }

  group('colouring', () {
    Future<List<TextSpan>> spansOf(WidgetTester tester, String text) async {
      await tester.pumpWidget(themedApp(const SizedBox()));
      final controller = VariableTextEditingController(text: text)..scope = scope;
      addTearDown(controller.dispose);
      final span = controller.buildTextSpan(context: tester.element(find.byType(SizedBox)), withComposing: false);
      expect(span.toPlainText(), text, reason: 'colouring never changes the text');
      return span.children!.cast<TextSpan>();
    }

    Color? colourOf(List<TextSpan> spans, String token) => spans.firstWhere((s) => s.text == token).style?.color;

    testWidgets('defined tokens take the accent, undefined ones the error colour, dynamic ones count as defined', (
      tester,
    ) async {
      await loadScope(tester);
      final spans = await spansOf(tester, r'{{baseUrl}}/{{missing}}/{{$guid}}');

      expect(colourOf(spans, '{{baseUrl}}'), AppColors.light.mainAccent);
      expect(colourOf(spans, '{{missing}}'), AppColors.light.statusError);
      expect(colourOf(spans, r'{{$guid}}'), AppColors.light.mainAccent);
    });

    testWidgets('nothing is flagged as undefined until the first load finishes', (tester) async {
      final spans = await spansOf(tester, '{{baseUrl}}/{{missing}}');

      expect(colourOf(spans, '{{missing}}'), AppColors.light.mainAccent);
    });

    testWidgets('plain text is left alone', (tester) async {
      await loadScope(tester);
      await tester.pumpWidget(themedApp(const SizedBox()));
      final controller = VariableTextEditingController(text: 'no tokens here')..scope = scope;
      addTearDown(controller.dispose);

      final span = controller.buildTextSpan(context: tester.element(find.byType(SizedBox)), withComposing: false);

      expect(span.children, isNull);
      expect(span.text, 'no tokens here');
    });
  });

  group('hover', () {
    // The field's text starts after the theme's 12px left padding; in tests every
    // glyph is a square of the font size, so a position inside the first
    // `{{baseUrl}}` (11 characters) is easy to pick.
    const textInset = 12.0;

    Future<TestGesture> mouse(WidgetTester tester) async {
      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: const Offset(1, 1));
      addTearDown(gesture.removePointer);
      return gesture;
    }

    Future<void> pumpField(WidgetTester tester, String text, {bool withScope = true, bool obscure = false}) async {
      Widget field = SizedBox(
        width: 520,
        child: VariableTextFormField(initialValue: text, obscureText: obscure),
      );
      if (withScope) field = ChangeNotifierProvider<VariableScope>.value(value: scope, child: field);
      await tester.pumpWidget(themedApp(Center(child: field)));
    }

    Future<void> hoverAt(WidgetTester tester, TestGesture gesture, double dx) async {
      final rect = tester.getRect(find.byType(TextField));
      await gesture.moveTo(Offset(rect.left + textInset + dx, rect.center.dy));
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump();
      await tester.pump();
    }

    testWidgets('hovering {{baseUrl}} shows its value and the environment it comes from', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{baseUrl}}/users');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 40);

      expect(find.byType(VariableHoverCard), findsOneWidget);
      expect(find.text('{{baseUrl}}'), findsOneWidget);
      expect(find.text('https://api.test'), findsOneWidget);
      expect(find.text('Environment · Testing'), findsOneWidget);
    });

    testWidgets('the card goes away when the pointer leaves the token', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{baseUrl}}/users');
      final gesture = await mouse(tester);
      await hoverAt(tester, gesture, 40);
      expect(find.byType(VariableHoverCard), findsOneWidget);

      // 11 characters of token, then the plain text "/users".
      await hoverAt(tester, gesture, 14.0 * 11 + 30);

      expect(find.byType(VariableHoverCard), findsNothing);
    });

    testWidgets('plain text never shows a card', (tester) async {
      await loadScope(tester);
      await pumpField(tester, 'just plain text');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 40);

      expect(find.byType(VariableHoverCard), findsNothing);
    });

    testWidgets('a collection variable names its scope', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{page}}');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.text('Collection'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('a secret is never put on screen', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{token}}');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.byType(VariableHoverCard), findsOneWidget);
      expect(find.text('sup3r-s3cret-value'), findsNothing);
      expect(find.text('Secret, hidden'), findsOneWidget);
    });

    testWidgets('an undefined variable says so', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{nope}}');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.text('Undefined'), findsOneWidget);
      expect(find.textContaining('Not defined'), findsOneWidget);
    });

    testWidgets('a dynamic variable is flagged as an example', (tester) async {
      await loadScope(tester);
      await pumpField(tester, r'{{$guid}}');
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.text('Dynamic'), findsOneWidget);
      expect(find.textContaining('new value is generated'), findsOneWidget);
    });

    testWidgets('a masked field shows no card even over a token', (tester) async {
      await loadScope(tester);
      await pumpField(tester, '{{baseUrl}}', obscure: true);
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.byType(VariableHoverCard), findsNothing);
    });

    testWidgets('outside a request (no VariableScope) it is a plain text field', (tester) async {
      await pumpField(tester, '{{baseUrl}}', withScope: false);
      final gesture = await mouse(tester);

      await hoverAt(tester, gesture, 20);

      expect(find.byType(VariableHoverCard), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('typing keeps working and reports the raw text', (tester) async {
      await loadScope(tester);
      String? last;
      await tester.pumpWidget(
        themedApp(
          ChangeNotifierProvider<VariableScope>.value(
            value: scope,
            child: VariableTextFormField(initialValue: '', onChanged: (v) => last = v),
          ),
        ),
      );

      await tester.enterText(find.byType(TextField), '{{baseUrl}}/x');

      expect(last, '{{baseUrl}}/x');
    });
  });
}
