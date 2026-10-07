import '../../../../core/enums/http_method.dart';
import '../../../import_export/domain/entities/imported_collection.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../entities/recorded_exchange.dart';
import 'noise_filter.dart';
import 'path_normalizer.dart';
import 'recorded_request_mapper.dart';
import 'recorder_headers.dart';
import 'traffic_masking.dart';

/// What "Create collection from recording" does with the calls.
final class RecordingOptions {
  final String collectionName;
  final bool skipAssets;
  final bool skipAnalytics;
  final bool skipPreflights;

  /// One request per method and normalised path: the first call is the request, later ones become saved examples. Off:
  /// every call is its own request and keeps the ids it had.
  final bool mergeDuplicates;

  /// One folder per first path segment.
  final bool groupIntoFolders;

  /// Adds a "Status equals" check with the status the call got.
  final bool addStatusAssertions;

  const RecordingOptions({
    this.collectionName = 'Recorded traffic',
    this.skipAssets = true,
    this.skipAnalytics = true,
    this.skipPreflights = true,
    this.mergeDuplicates = true,
    this.groupIntoFolders = true,
    this.addStatusAssertions = false,
  });

  RecordingOptions copyWith({
    String? collectionName,
    bool? skipAssets,
    bool? skipAnalytics,
    bool? skipPreflights,
    bool? mergeDuplicates,
    bool? groupIntoFolders,
    bool? addStatusAssertions,
  }) =>
      RecordingOptions(
        collectionName: collectionName ?? this.collectionName,
        skipAssets: skipAssets ?? this.skipAssets,
        skipAnalytics: skipAnalytics ?? this.skipAnalytics,
        skipPreflights: skipPreflights ?? this.skipPreflights,
        mergeDuplicates: mergeDuplicates ?? this.mergeDuplicates,
        groupIntoFolders: groupIntoFolders ?? this.groupIntoFolders,
        addStatusAssertions: addStatusAssertions ?? this.addStatusAssertions,
      );
}

/// An answer kept as a saved example of a request. Credentials in it are masked.
final class PlannedExample {
  final String name;
  final int status;
  final Map<String, String> headers;
  final String body;

  /// The recorder cut the body at its size limit.
  final bool truncated;

  const PlannedExample({
    required this.name,
    required this.status,
    required this.headers,
    required this.body,
    this.truncated = false,
  });
}

/// A request of the plan with what belongs to it besides the request itself.
final class PlannedRequest {
  final ImportedRequest request;
  final List<PlannedExample> examples;

  /// The status the "Status equals" check expects; null when no check is added.
  final int? assertedStatus;

  /// How many recorded calls this request stands for.
  final int calls;

  const PlannedRequest({required this.request, required this.examples, required this.assertedStatus, required this.calls});
}

final class PlannedVariable {
  final String key;
  final String value;
  final bool secret;
  const PlannedVariable(this.key, this.value, {this.secret = false});
}

/// The numbers the preview shows before anything is created.
final class RecordingCounts {
  final int selected;
  final int requests;
  final int folders;
  final int examples;

  /// Calls that became a later example of a request instead of a request of their own.
  final int merged;
  final Map<NoiseReason, int> skipped;
  final Map<BodyOmitted, int> bodiesOmitted;

  /// Answers that could not be kept as an example (not text, compressed in a way that cannot be read).
  final int examplesSkipped;

  const RecordingCounts({
    required this.selected,
    required this.requests,
    required this.folders,
    required this.examples,
    required this.merged,
    required this.skipped,
    required this.bodiesOmitted,
    required this.examplesSkipped,
  });

  int get skippedTotal => skipped.values.fold(0, (a, b) => a + b);
}

/// What would be created: the collection tree, the examples and checks that go with its requests, and the variables.
final class RecordingPlan {
  final ImportedCollection collection;
  final List<PlannedRequest> requests;

  /// The environment that holds `baseUrl` and the empty secret variables; its name is the collection's.
  final String environmentName;
  final List<PlannedVariable> environmentVariables;
  final RecordingCounts counts;

  /// One sentence per thing that was left out or changed, for the dialog to list.
  final List<String> notes;

  const RecordingPlan({
    required this.collection,
    required this.requests,
    required this.environmentName,
    required this.environmentVariables,
    required this.counts,
    required this.notes,
  });

  bool get isEmpty => requests.isEmpty;

  /// The secret variables the requests use (created empty).
  List<String> get secretVariables => [
        for (final v in environmentVariables)
          if (v.secret) v.key,
      ];
}

/// Builds a clean collection out of recorded calls: noise out, repeated calls merged, paths made variables, credentials
/// made secret variables, folders by the first path segment, responses as examples.
abstract final class RecordingCollectionBuilder {
  /// How many different answers of one request are kept as examples.
  static const maxExamplesPerRequest = 5;

  static final _generic = RegExp(r'^(api|rest|v\d+(\.\d+)*)$', caseSensitive: false);

  /// [baseUrl] is the upstream's base address (`https://api.example.com`), which becomes the `baseUrl` variable.
  static RecordingPlan build(List<RecordedExchange> exchanges, {required String baseUrl, required RecordingOptions options}) {
    final sorted = List<RecordedExchange>.of(exchanges)
      ..sort((a, b) {
        final byTime = a.startedAt.compareTo(b.startedAt);
        return byTime != 0 ? byTime : a.id.compareTo(b.id);
      });
    final skipped = <NoiseReason, int>{};
    final groups = <String, _Group>{};
    var kept = 0;
    for (final e in sorted) {
      final reason = NoiseFilter.reasonFor(
        e,
        skipAssets: options.skipAssets,
        skipAnalytics: options.skipAnalytics,
        skipPreflights: options.skipPreflights,
      );
      if (reason != null) {
        skipped.update(reason, (n) => n + 1, ifAbsent: () => 1);
        continue;
      }
      if (!HttpMethod.values.any((m) => m.label == e.method)) {
        skipped.update(NoiseReason.unsupportedMethod, (n) => n + 1, ifAbsent: () => 1);
        continue;
      }
      kept++;
      final draft = RecordedRequestMapper.map(e, baseUrl: baseUrl, templatePath: options.mergeDuplicates);
      final key = options.mergeDuplicates ? draft.name : '#${groups.length}';
      groups.putIfAbsent(key, () => _Group(draft)).exchanges.add(e);
    }

    final topLevel = <ImportedItem>[];
    final folders = <String, List<ImportedItem>>{};
    final planned = <PlannedRequest>[];
    final secrets = <String>{};
    final pathValues = <String, String>{};
    final bodiesOmitted = <BodyOmitted, int>{};
    var examplesSkipped = 0;
    for (final group in groups.values) {
      final draft = group.draft;
      final first = group.exchanges.first;
      final request = ImportedRequest(
        draft.name,
        method: draft.method,
        url: draft.url,
        headers: draft.headers,
        body: draft.body,
      );
      final folder = options.groupIntoFolders ? folderOf(first.path) : null;
      if (folder == null) {
        topLevel.add(request);
      } else {
        folders.putIfAbsent(folder, () {
          final children = <ImportedItem>[];
          topLevel.add(ImportedFolder(folder, children));
          return children;
        }).add(request);
      }
      secrets.addAll(draft.secretVariables);
      for (final v in draft.pathVariables) {
        pathValues.putIfAbsent(v.name, () => v.value);
      }
      if (draft.bodyOmitted != null) bodiesOmitted.update(draft.bodyOmitted!, (n) => n + 1, ifAbsent: () => 1);
      final examples = _examplesOf(group.exchanges);
      examplesSkipped += examples.skipped;
      planned.add(PlannedRequest(
        request: request,
        examples: examples.kept,
        assertedStatus: options.addStatusAssertions ? first.status : null,
        calls: group.exchanges.length,
      ));
    }

    final collection = ImportedCollection(
      options.collectionName,
      topLevel,
      variables: [
        KeyValueItem(key: baseUrlVariable, value: baseUrl),
        for (final v in pathValues.entries) KeyValueItem(key: v.key, value: v.value),
      ],
    );
    final counts = RecordingCounts(
      selected: exchanges.length,
      requests: planned.length,
      folders: collection.folderCount,
      examples: planned.fold(0, (sum, p) => sum + p.examples.length),
      merged: kept - planned.length,
      skipped: skipped,
      bodiesOmitted: bodiesOmitted,
      examplesSkipped: examplesSkipped,
    );
    return RecordingPlan(
      collection: collection,
      requests: planned,
      environmentName: options.collectionName,
      environmentVariables: [
        PlannedVariable(baseUrlVariable, baseUrl),
        for (final name in secrets) PlannedVariable(name, '', secret: true),
      ],
      counts: counts,
      notes: _notesOf(counts),
    );
  }

  static const baseUrlVariable = 'baseUrl';

  /// The folder a request with this path goes in: the first segment that is not `api` or a version (`/api/v2/users/7` ->
  /// `users`); null for the root and for a path that starts with an id.
  static String? folderOf(String pathWithQuery) {
    final path = pathWithQuery.split('?').first;
    final segments = [
      for (final s in path.split('/'))
        if (s.isNotEmpty) s,
    ];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      if (_generic.hasMatch(segment) && i < segments.length - 1) continue;
      final normalized = PathNormalizer.normalize('/$segment');
      return normalized.variables.isNotEmpty || _generic.hasMatch(segment) ? null : segment;
    }
    return null;
  }

  static ({List<PlannedExample> kept, int skipped}) _examplesOf(List<RecordedExchange> exchanges) {
    final kept = <PlannedExample>[];
    final seen = <String>{};
    final names = <String>{};
    var skipped = 0;
    for (final e in exchanges) {
      if (kept.length >= maxExamplesPerRequest) break;
      final unreadable = e.responseUndecoded || (e.hasResponseBody && e.responseText == null);
      if (unreadable) {
        skipped++;
        continue;
      }
      final body = TrafficMasking.body(e.responseText ?? '');
      if (!seen.add('${e.status}|$body')) continue;
      final base = '${e.status} ${e.statusMessage}'.trim();
      var name = base;
      for (var n = 2; !names.add(name); n++) {
        name = '$base ($n)';
      }
      kept.add(PlannedExample(
        name: name,
        status: e.status,
        headers: _exampleHeaders(e),
        body: body,
        truncated: e.responseBodyTruncated,
      ));
    }
    return (kept: kept, skipped: skipped);
  }

  /// The answer's headers as an example keeps them: the body is stored decoded and without its framing, so the headers that
  /// describe the wire format go; cookies would be masked to nothing, so they go too.
  static Map<String, String> _exampleHeaders(RecordedExchange e) {
    const dropped = {'content-length', 'content-encoding', 'date', 'set-cookie', 'set-cookie2'};
    final merged = <String, List<String>>{};
    for (final h in e.responseHeaders) {
      final lower = h.name.toLowerCase();
      if (RecorderHeaders.hopByHop.contains(lower) || dropped.contains(lower)) continue;
      (merged[lower] ??= []).add(TrafficMasking.headerValue(h.name, h.value));
    }
    return {for (final entry in merged.entries) entry.key: entry.value.join(', ')};
  }

  static List<String> _notesOf(RecordingCounts counts) {
    String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
    return [
      if (counts.bodiesOmitted[BodyOmitted.multipart] case final n?)
        '${plural(n, 'request')} sent a multipart form: the body was left out (the files and the boundary belong to that one send).',
      if (counts.bodiesOmitted[BodyOmitted.binary] case final n?)
        '${plural(n, 'request')} sent a body that is not text (an upload, protobuf): it was left out.',
      if (counts.bodiesOmitted[BodyOmitted.tooLarge] case final n?)
        '${plural(n, 'request')} sent a body larger than the recorder keeps: it was left out instead of saved half.',
      if (counts.examplesSkipped > 0)
        '${plural(counts.examplesSkipped, 'answer')} could not be kept as an example (not text, or compressed with brotli).',
    ];
  }
}

final class _Group {
  final RequestDraft draft;
  final List<RecordedExchange> exchanges = [];
  _Group(this.draft);
}
