// TEMPORARY: dumps generated tests to a scratch folder for review. Deleted before the final report.
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_layer_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/api_test_generator.dart';
import 'package:postpilot/features/dart_codegen/domain/services/dart_model_generator.dart';
import 'shop_api_fixture.dart';

void main() {
  test('dump', () {
    const out = r'C:\Users\MDMANZ~1\AppData\Local\Temp\claude\C--Users-Md-Manzurul-Islam-OneDrive-Desktop-claude\859be760-07c7-49d1-9bbb-061fc2736d9e\scratchpad\w42_dump';
    final dir = Directory(out);
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    for (final style in [DartModelStyle.plain, DartModelStyle.freezed]) {
      final r = const ApiTestGenerator().generate(
        'Shop API',
        shopApiRequests(),
        options: ApiTestOptions(layer: ApiLayerOptions(packageName: 'shop_app', modelStyle: style, allNullable: style == DartModelStyle.freezed)),
      );
      for (final f in r.files) {
        final file = File('$out/${style.name}/${f.path}')..createSync(recursive: true);
        file.writeAsStringSync(f.content);
      }
      File('$out/${style.name}/NOTES.txt').writeAsStringSync('${r.notes.join('\n')}\n---\n${r.devDependencies}\n${r.addCommand}\n');
      final layer = const ApiLayerGenerator().generate('Shop API', shopApiRequests(), options: ApiLayerOptions(packageName: 'shop_app', modelStyle: style, allNullable: style == DartModelStyle.freezed));
      for (final f in layer.files) {
        File('$out/${style.name}/${f.path}')
          ..createSync(recursive: true)
          ..writeAsStringSync(f.content);
      }
    }
  });
}
