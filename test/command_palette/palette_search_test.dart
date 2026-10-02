import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:postpilot/features/command_palette/domain/entities/palette_item.dart';
import 'package:postpilot/features/command_palette/domain/services/fuzzy_matcher.dart';
import 'package:postpilot/features/command_palette/domain/services/palette_search.dart';

PaletteItem _item(String id, String title, {String subtitle = '', List<String> keywords = const [], String hidden = '', PaletteCategory category = PaletteCategory.tools}) =>
    PaletteItem(id: id, title: title, subtitle: subtitle, keywords: keywords, hiddenText: hidden, category: category, icon: Icons.bolt, run: (_) {});

void main() {
  group('FuzzyMatcher', () {
    test('matches subsequences and reports positions', () {
      final m = FuzzyMatcher.match('dsm', 'Dart Studio: models')!;
      expect(m.positions, [0, 5, 13]);
      expect(FuzzyMatcher.match('xyz', 'Dart Studio'), isNull);
      expect(FuzzyMatcher.match('', 'anything')!.score, 0);
    });

    test('a substring beats a scattered match, and a word start beats mid-word', () {
      final substring = FuzzyMatcher.match('stu', 'Dart Studio')!.score;
      final scattered = FuzzyMatcher.match('dsu', 'Dart Studio')!.score;
      expect(substring, greaterThan(scattered));
      final wordStart = FuzzyMatcher.match('stu', 'Dart Studio')!.score;
      final midWord = FuzzyMatcher.match('tud', 'Dart Studio')!.score;
      expect(wordStart, greaterThan(midWord));
    });

    test('is case and whitespace insensitive and handles longer queries than text', () {
      expect(FuzzyMatcher.match('DART studio', 'dart studio'), isNotNull);
      expect(FuzzyMatcher.match('a very long query', 'short'), isNull);
    });
  });

  group('PaletteSearch', () {
    final items = [
      _item('a', 'Dart Studio: JSON to models', keywords: ['flutter', 'dto']),
      _item('b', 'Odoo Studio: domain builder', keywords: ['odoo', 'filter']),
      _item('c', 'Get users', subtitle: 'Users API · https://api.test/users', category: PaletteCategory.requests, hidden: '{"query":"invoice"}'),
      _item('d', 'Settings', category: PaletteCategory.app),
    ];

    test('empty query keeps the given order', () {
      expect(PaletteSearch.search(items, '').map((h) => h.item.id), ['a', 'b', 'c', 'd']);
    });

    test('ranks title matches first and finds keywords and subtitles', () {
      expect(PaletteSearch.search(items, 'odoo').first.item.id, 'b');
      expect(PaletteSearch.search(items, 'flutter').map((h) => h.item.id), contains('a'));
      expect(PaletteSearch.search(items, 'api.test').map((h) => h.item.id), contains('c'));
    });

    test('hidden text (a request body) matches only literally', () {
      expect(PaletteSearch.search(items, 'invoice').map((h) => h.item.id), ['c']);
      expect(PaletteSearch.search(items, 'ivc').map((h) => h.item.id), isEmpty);
      expect(PaletteSearch.search(items, 'q'), isEmpty, reason: 'one letter is too vague for hidden text');
    });

    test('title hits carry highlight positions', () {
      final hit = PaletteSearch.search(items, 'sett').first;
      expect(hit.item.id, 'd');
      expect(hit.titlePositions, [0, 1, 2, 3]);
    });

    test('respects the limit', () {
      final many = [for (var i = 0; i < 100; i++) _item('$i', 'Item $i')];
      expect(PaletteSearch.search(many, 'item', limit: 10), hasLength(10));
    });
  });
}
