import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/core/platform/platform_support.dart';
import 'package:postpilot/features/command_palette/domain/entities/palette_item.dart';

void main() {
  group('PlatformFeature', () {
    test('every feature works outside the browser and says nothing there', () {
      for (final feature in PlatformFeature.values) {
        expect(feature.isSupported(web: false), isTrue, reason: feature.name);
        expect(feature.reason(web: false), isNull, reason: feature.name);
      }
    });

    test('in the browser every feature is unavailable and the reason starts the same way', () {
      for (final feature in PlatformFeature.values) {
        expect(feature.isSupported(web: true), isFalse, reason: feature.name);
        expect(feature.reason(web: true), startsWith('Needs the desktop app: browsers '), reason: feature.name);
      }
    });

    test('the server features give the wording the dialogs show', () {
      expect(PlatformFeature.mockServer.reason(web: true), 'Needs the desktop app: browsers cannot open server sockets');
      expect(PlatformFeature.trafficRecorder.reason(web: true), 'Needs the desktop app: browsers cannot open server sockets');
    });
  });

  group('PaletteItem.unavailableReason', () {
    PaletteItem item({PlatformFeature? requires}) =>
        PaletteItem(id: 'x', title: 'X', run: (_) {}, requires: requires);

    test('an entry with no requirement is always available', () {
      expect(item().unavailableReason(web: true), isNull);
      expect(item().unavailableReason(web: false), isNull);
    });

    test('an entry that needs a local server is unavailable in the browser only', () {
      final mock = item(requires: PlatformFeature.mockServer);
      expect(mock.unavailableReason(web: true), 'Needs the desktop app: browsers cannot open server sockets');
      expect(mock.unavailableReason(web: false), isNull);
    });
  });
}
