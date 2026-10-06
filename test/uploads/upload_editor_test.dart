import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/enums/body_type.dart';
import 'package:postpilot/core/network/upload_body.dart';
import 'package:postpilot/core/network/upload_file_source.dart';
import 'package:postpilot/core/theme/app_theme.dart';
import 'package:postpilot/features/request_builder/domain/entities/key_value_item.dart';
import 'package:postpilot/features/request_builder/domain/entities/request_body.dart';
import 'package:postpilot/features/request_builder/presentation/file_picker_service.dart';
import 'package:postpilot/features/request_builder/presentation/widgets/body_editor.dart';

/// Answers the file dialog without opening one.
final class _FakePicker implements FilePickerService {
  PickedFile? next;
  Object? error;
  int calls = 0;

  @override
  Future<PickedFile?> pick() async {
    calls++;
    if (error != null) throw error!;
    return next;
  }
}

KeyValueItem _file(String key, String path, {String fileName = '', String contentType = ''}) =>
    KeyValueItem(key: key, value: path, kind: FormFieldKind.file, fileName: fileName, contentType: contentType);

void main() {
  late Directory dir;
  late File photo;
  late RequestBody body;
  late List<RequestBody> emitted;
  late _FakePicker picker;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('pp_editor_test_');
    photo = File('${dir.path}${Platform.pathSeparator}cat.png')..writeAsBytesSync(List.filled(2048, 1));
    picker = _FakePicker();
  });

  tearDown(() => dir.deleteSync(recursive: true));

  /// The file is looked at with real IO, which fake async does not run, and in two steps (what is there, then its
  /// size), each of which only starts when the step before it has been pumped: give it real time and a frame, a few times.
  Future<void> settle(WidgetTester tester) async {
    for (var round = 0; round < 4; round++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
      await tester.pump();
    }
  }

  Future<void> pumpBody(
    WidgetTester tester,
    RequestBody initial, {
    required Brightness brightness,
    required double width,
    UploadFileSource? source,
  }) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    body = initial;
    emitted = [];
    await tester.pumpWidget(
      MaterialApp(
        theme: brightness == Brightness.light ? AppTheme.light : AppTheme.dark,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: StatefulBuilder(
              builder: (context, setState) => BodyEditor(
                body: body,
                picker: picker,
                uploadSource: source,
                onChanged: (next) => setState(() {
                  body = next;
                  emitted.add(next);
                }),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapAndSettle(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.tap(finder);
    await tester.pump();
    await settle(tester);
  }

  String textOf(Key key) => (find.byKey(key).evaluate().single.widget as Text).data!;

  for (final brightness in Brightness.values) {
    for (final width in [1200.0, 420.0]) {
      group('the body editor, ${brightness.name} theme at ${width.toInt()} px', () {
        testWidgets('a file row shows its name and size, and Remove clears it', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Cat'), _file('photo', photo.path)]),
            brightness: brightness,
            width: width,
          );

          expect(tester.takeException(), isNull, reason: 'no overflow');
          expect(textOf(const ValueKey('file-summary')), 'cat.png · 2.0 KB');
          expect(find.byKey(const ValueKey('file-remove')), findsOneWidget);

          await tapAndSettle(tester, find.byKey(const ValueKey('file-remove')));

          final row = emitted.last.formFields[1];
          expect((row.key, row.value, row.isFile), ('photo', '', true));
          expect(find.text('No file chosen'), findsOneWidget);
          expect(find.byKey(const ValueKey('file-remove')), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('Choose file opens the dialog and puts the chosen path in the row', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('photo', '')]),
            brightness: brightness,
            width: width,
          );
          picker.next = PickedFile(path: photo.path, name: 'cat.png', size: 2048, sessionOnly: false);

          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));

          expect(picker.calls, 1);
          expect(emitted.last.formFields.single.value, photo.path);
          expect(textOf(const ValueKey('file-summary')), 'cat.png · 2.0 KB');
          expect(find.text('Change…'), findsOneWidget, reason: 'the button now says what it does');
          expect(tester.takeException(), isNull);
        });

        testWidgets('closing the dialog without a choice changes nothing; a refused or failed pick says why', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('photo', '')]),
            brightness: brightness,
            width: width,
          );

          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));
          expect(emitted, isEmpty);

          picker.error = const FilePickRefused('"big.iso" is 2.0 GB: use the desktop app for a larger one.');
          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));
          expect(find.text('"big.iso" is 2.0 GB: use the desktop app for a larger one.'), findsOneWidget);

          picker.error = StateError('plugin crashed');
          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));
          expect(find.text('The file could not be opened. Choose it again, or type its path.'), findsOneWidget);
          expect(find.textContaining('plugin crashed'), findsNothing, reason: 'the cause stays out of the message');
          expect(emitted, isEmpty);
        });

        testWidgets('a path with a {{variable}} is accepted as typed and says it is found when the request is sent', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('avatar', '')]),
            brightness: brightness,
            width: width,
          );

          await tester.enterText(
            find.descendant(of: find.byKey(const ValueKey('row-file-value')), matching: find.byType(TextField)).first,
            '{{uploadDir}}/avatar.png',
          );
          await settle(tester);

          expect(emitted.last.formFields.single.value, '{{uploadDir}}/avatar.png');
          expect(find.text('Found when the request is sent: the path uses a variable'), findsOneWidget);
        });

        testWidgets('a path that is not there says so, and so does a folder', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('a', '${dir.path}${Platform.pathSeparator}missing.png')]),
            brightness: brightness,
            width: width,
          );
          expect(textOf(const ValueKey('file-problem')), 'File not found');

          await pumpBody(tester, RequestBody(type: BodyType.formData, formFields: [_file('a', dir.path)]), brightness: brightness, width: width);
          expect(textOf(const ValueKey('file-problem')), 'This is a folder, not a file');
        });

        testWidgets('the Text / File switch keeps what was typed in each, and a file row stores no text', (tester) async {
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Cat')]),
            brightness: brightness,
            width: width,
          );

          await tapAndSettle(tester, find.text('File'));
          expect(emitted.last.formFields.single.isFile, isTrue);
          expect(emitted.last.formFields.single.value, isEmpty);
          expect(find.byKey(const ValueKey('file-choose')), findsOneWidget);

          await tapAndSettle(tester, find.text('Text'));
          expect(emitted.last.formFields.single.isFile, isFalse);
          expect(emitted.last.formFields.single.value, 'Cat', reason: 'the text typed before the switch is back');
          expect(find.byKey(const ValueKey('file-choose')), findsNothing);
          expect(tester.takeException(), isNull);
        });

        testWidgets('a file row keeps its stable identity while edited, and the name and type options are saved on the row', (tester) async {
          final row = _file('doc', photo.path);
          await pumpBody(tester, RequestBody(type: BodyType.formData, formFields: [row]), brightness: brightness, width: width);

          await tapAndSettle(tester, find.byKey(const ValueKey('file-options')));
          await tester.enterText(find.byKey(const ValueKey('file-name-0')), 'Q3.pdf');
          await tester.enterText(find.byKey(const ValueKey('file-content-type-0')), 'application/pdf');
          await settle(tester);

          final saved = emitted.last.formFields.single;
          expect((saved.id, saved.fileName, saved.contentType, saved.value), (row.id, 'Q3.pdf', 'application/pdf', photo.path));
          expect(textOf(const ValueKey('file-summary')), 'Q3.pdf · 2.0 KB', reason: 'the name that will be sent is the one shown');
        });

        testWidgets('Bulk edit works on the text rows and keeps the file rows as they are', (tester) async {
          final file = _file('photo', photo.path, contentType: 'image/png');
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [KeyValueItem(key: 'title', value: 'Cat'), file]),
            brightness: brightness,
            width: width,
          );

          await tapAndSettle(tester, find.text('Bulk edit'));

          final field = tester.widget<TextField>(find.byType(TextField));
          expect(field.controller!.text, 'title:Cat');
          expect(find.text('File rows are kept as they are.'), findsOneWidget);

          await tester.enterText(find.byType(TextField), 'title:Dog\nnote:hi');

          expect(emitted.last.formFields.map((f) => (f.key, f.value, f.isFile)), [('title', 'Dog', false), ('note', 'hi', false), ('photo', photo.path, true)]);
          expect(emitted.last.formFields.last.contentType, 'image/png');
        });

        testWidgets('the binary body: choose a file, give it a type, remove it; the dropdown offers Binary', (tester) async {
          await pumpBody(tester, RequestBody.empty, brightness: brightness, width: width);

          await tester.tap(find.byType(DropdownButton<BodyType>));
          await tester.pumpAndSettle();
          await tester.tap(find.text('Binary').last);
          await tester.pumpAndSettle();
          expect(emitted.last.type, BodyType.binary);
          expect(find.byKey(const ValueKey('binary-file')), findsOneWidget);
          expect(find.byKey(const ValueKey('file-name-0')), findsNothing, reason: 'a body has no file name of its own');

          picker.next = PickedFile(path: photo.path, name: 'cat.png', size: 2048, sessionOnly: false);
          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));
          expect(emitted.last.binaryFile!.value, photo.path);
          expect(textOf(const ValueKey('file-summary')), 'cat.png · 2.0 KB');

          await tapAndSettle(tester, find.byKey(const ValueKey('file-options')));
          await tester.enterText(find.byKey(const ValueKey('file-content-type-0')), 'image/png');
          await settle(tester);
          expect(emitted.last.binaryFile!.contentType, 'image/png');

          await tapAndSettle(tester, find.byKey(const ValueKey('file-remove')));
          expect(emitted.last.binaryFile, isNull);
          expect(emitted.last.formFields, isEmpty, reason: 'removing the file removes its row');
          expect(tester.takeException(), isNull);
        });

        testWidgets('in a browser the file is for this session only, and after a reload the editor asks for it again', (tester) async {
          final files = SessionFiles();
          final source = MemoryUploadFileSource(files);
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('photo', '')]),
            brightness: brightness,
            width: width,
            source: source,
          );
          final reference = files.add(name: 'cat.png', bytes: Uint8List(2048));
          picker.next = PickedFile(path: reference, name: 'cat.png', size: 2048, sessionOnly: true);

          await tapAndSettle(tester, find.byKey(const ValueKey('file-choose')));

          expect(emitted.last.formFields.single.value, reference);
          expect(textOf(const ValueKey('file-summary')), 'cat.png · 2.0 KB');
          expect(textOf(const ValueKey('file-session-note')), 'selected in this session only: after a reload, choose the file again');
          expect(find.byKey(const ValueKey('file-path-0')), findsNothing, reason: 'there is no path to type or show');

          // A reload: the reference was saved with the request, the bytes were not.
          await pumpBody(
            tester,
            RequestBody(type: BodyType.formData, formFields: [_file('photo', reference)]),
            brightness: brightness,
            width: width,
            source: MemoryUploadFileSource(SessionFiles()),
          );

          expect(textOf(const ValueKey('file-problem')), 'Chosen in an earlier browser session: a browser cannot reopen it, choose the file again');
          expect(find.byKey(const ValueKey('file-summary')), findsNothing);
          expect(find.text('cat.png'), findsOneWidget, reason: 'the name picked then is still shown');
          expect(tester.takeException(), isNull);
        });
      });
    }
  }
}
