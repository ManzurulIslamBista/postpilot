import 'package:flutter/material.dart';
import '../../../core/di/injector.dart';
import '../../command_palette/domain/entities/palette_item.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'suggest_tests_launcher.dart';
import 'widgets/openapi_tests_dialog.dart';
import 'widgets/suggest_tests_tab.dart';

/// The command palette's entries for test suggestions, baselines and the OpenAPI test generator. The ones about a
/// response are listed only while the open request has one in memory.
List<PaletteItem> testIntelligencePaletteItems() {
  final open = locator.isRegistered<ShellViewModel>() ? locator<ShellViewModel>().selectedRequestId : null;
  final withResponse = open != null && hasResponseToSuggestFrom(open) ? open : null;
  return [
    if (withResponse != null) ...[
      PaletteItem(
        id: 'tests.suggest',
        title: 'Suggest tests from this response',
        subtitle: 'Status, content type, JSON Schema, required fields, formats: tick what to add to the Tests tab',
        icon: Icons.checklist,
        keywords: const ['assertion', 'test', 'tests', 'suggest', 'generate', 'schema', 'contract', 'response'],
        run: (c) => openSuggestTests(c, requestId: withResponse),
      ),
      PaletteItem(
        id: 'tests.baseline',
        title: 'Baseline and drift of this response',
        subtitle: 'Record what a good answer looks like and see when the API drifts from it',
        icon: Icons.fact_check_outlined,
        keywords: const ['baseline', 'drift', 'regression', 'snapshot', 'contract', 'breaking', 'response'],
        run: (c) => openSuggestTests(c, requestId: withResponse, section: TestsSection.baseline),
      ),
    ],
    PaletteItem(
      id: 'openapi.tests',
      title: 'Generate tests from OpenAPI…',
      subtitle: 'Contract, negative, boundary and auth requests with assertions, from a spec',
      icon: Icons.fact_check_outlined,
      keywords: const ['openapi', 'swagger', 'spec', 'test', 'tests', 'generate', 'contract', 'negative', 'boundary', 'auth'],
      run: (c) => OpenApiTestsDialog.show(c),
    ),
  ];
}
