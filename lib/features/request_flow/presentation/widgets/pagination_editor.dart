import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/entities/api_request_entity.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../../settings/presentation/widgets/setting_number_field.dart';
import '../../../settings/presentation/widgets/synced_text_field.dart';
import '../../domain/entities/pagination_settings.dart';
import '../../domain/services/pagination_detector.dart';
import 'flow_section.dart';

/// The settings of "Fetch all pages": how the next page is found, where the items are, and the limits. It can
/// look at the response the request last got and propose the settings (shown for confirmation, then editable).
class PaginationEditor extends StatefulWidget {
  final PaginationSettings settings;
  final ValueChanged<PaginationSettings> onChanged;

  /// Takes a proposal the person confirmed.
  final ValueChanged<PaginationDetection> onUseDetection;

  /// What the request last got, to detect from; null before the first send.
  final ApiRequestEntity? request;
  final ApiResponseEntity? response;

  const PaginationEditor({
    super.key,
    required this.settings,
    required this.onChanged,
    required this.onUseDetection,
    this.request,
    this.response,
  });

  @override
  State<PaginationEditor> createState() => _PaginationEditorState();
}

class _PaginationEditorState extends State<PaginationEditor> {
  PaginationDetection? _detected;
  bool _detectedNothing = false;

  void _detect() {
    final request = widget.request;
    final response = widget.response;
    if (request == null || response == null) return;
    final found = PaginationDetector.detect(request, response);
    setState(() {
      _detected = found;
      _detectedNothing = found == null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final onChanged = widget.onChanged;
    final detected = _detected;
    final problem = settings.problem;
    final canDetect = widget.request != null && widget.response != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const FlowHint(
          'Sends the request again for every page and gives back ONE response: the items of all pages merged under the same JSON '
          'path, the rest from the first page. Tests, variable saves and the response tools work on that merged response.',
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('pagination-detect'),
              onPressed: canDetect ? _detect : null,
              icon: const Icon(Icons.auto_awesome, size: 16),
              label: const Text('Detect from the last response'),
            ),
            if (!canDetect)
              Text(
                'Send the request once first.',
                style: context.textStyles.caption.copyWith(color: context.colors.secondaryText),
              ),
          ],
        ),
        if (detected != null) ...[
          const SizedBox(height: 8),
          InfoBanner(
            key: const ValueKey('pagination-detected'),
            title: 'Found: ${detected.settings.kind.label}',
            message: '${detected.summary}${detected.readOnlyPost ? '\nThis POST only reads, so repeating it is safe.' : ''}',
            trailing: FilledButton(
              key: const ValueKey('pagination-use-detected'),
              onPressed: () {
                widget.onUseDetection(detected);
                setState(() => _detected = null);
              },
              child: const Text('Use this'),
            ),
          ),
        ] else if (_detectedNothing) ...[
          const SizedBox(height: 8),
          const InfoBanner(
            key: ValueKey('pagination-nothing'),
            kind: BannerKind.warning,
            message: 'No sign of more pages in this response: no Link header, no next-page URL, token, page number or '
                'offset. Pick the strategy yourself below.',
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<PaginationKind>(
          key: ValueKey('pagination-kind-${settings.kind.name}'),
          initialValue: settings.kind,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'How the next page is found', isDense: true),
          items: [for (final kind in PaginationKind.values) DropdownMenuItem(value: kind, child: Text(kind.label))],
          onChanged: (kind) => kind == null ? null : onChanged(settings.copyWith(kind: kind)),
        ),
        const SizedBox(height: 10),
        _pathField(
          'pagination-items',
          'Items array (JSON path)',
          settings.itemsPath,
          (text) => onChanged(settings.copyWith(itemsPath: text.trim())),
          hint: 'e.g. data.items; empty when the body is the array',
        ),
        ..._strategyFields(settings, onChanged),
        const SizedBox(height: 10),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SettingNumberField(
              key: const ValueKey('pagination-max-pages'),
              value: settings.maxPages,
              labelText: 'At most (1 to 500)',
              suffixText: 'pages',
              width: 190,
              onChanged: (value) => onChanged(settings.copyWith(maxPages: value)),
            ),
            SettingNumberField(
              key: const ValueKey('pagination-delay'),
              value: settings.delayMs,
              labelText: 'Pause between pages',
              suffixText: 'ms',
              width: 200,
              onChanged: (value) => onChanged(settings.copyWith(delayMs: value)),
            ),
            SettingNumberField(
              key: const ValueKey('pagination-size'),
              value: settings.maxMegabytes,
              labelText: 'Size limit',
              suffixText: 'MB',
              width: 140,
              onChanged: (value) => onChanged(settings.copyWith(maxMegabytes: value)),
            ),
          ],
        ),
        FlowCheckbox(
          key: const ValueKey('pagination-stop-empty'),
          title: 'Stop at the first empty page',
          value: settings.stopOnEmpty,
          onChanged: (on) => onChanged(settings.copyWith(stopOnEmpty: on)),
        ),
        if (settings.kind == PaginationKind.offset)
          FlowCheckbox(
            key: const ValueKey('pagination-count'),
            title: 'Count the records first (Odoo search_count)',
            description: 'Asks the same model how many records match, so the last page is known and the pages are numbered '
                '"2/7". Only for an Odoo JSON-2 search_read.',
            value: settings.countTotal,
            onChanged: (on) => onChanged(settings.copyWith(countTotal: on)),
          ),
        if (problem != null)
          Text(problem, style: context.textStyles.caption.copyWith(color: context.colors.statusError)),
        const FlowHint(
          'It also stops when a page repeats (a cursor or link seen before, or the server ignoring the page parameter) and never '
          'follows a next-page link to another host. Send then reads "Send (all pages)".',
        ),
      ],
    );
  }

  /// The fields only some strategies use.
  List<Widget> _strategyFields(PaginationSettings settings, ValueChanged<PaginationSettings> onChanged) {
    Widget path(String key, String label, String value, ValueChanged<String> set, {String? hint}) =>
        _pathField(key, label, value, set, hint: hint);
    final location = DropdownButtonFormField<PageParamLocation>(
      key: ValueKey('pagination-location-${settings.location.name}'),
      initialValue: settings.location,
      isExpanded: true,
      decoration: const InputDecoration(labelText: 'The parameter is written in', isDense: true),
      items: [for (final l in PageParamLocation.values) DropdownMenuItem(value: l, child: Text(l.label))],
      onChanged: (l) => l == null ? null : onChanged(settings.copyWith(location: l)),
    );
    final inBody = settings.location == PageParamLocation.body;
    final paramHint = inBody ? 'JSON path in the body, e.g. offset' : 'Query parameter name, e.g. page';
    return switch (settings.kind) {
      PaginationKind.linkHeader => const [],
      PaginationKind.nextUrl => [
          path('pagination-next', 'Next-page URL (JSON path)', settings.nextPath,
              (text) => onChanged(settings.copyWith(nextPath: text.trim())), hint: 'e.g. next or @odata.nextLink'),
          path('pagination-has-more', 'Has more (JSON path, optional)', settings.hasMorePath,
              (text) => onChanged(settings.copyWith(hasMorePath: text.trim())), hint: 'e.g. has_more'),
        ],
      PaginationKind.cursor => [
          path('pagination-next', 'Next-page token (JSON path)', settings.nextPath,
              (text) => onChanged(settings.copyWith(nextPath: text.trim())), hint: 'e.g. nextPageToken'),
          const SizedBox(height: 10),
          location,
          path('pagination-param', 'Send the token as', settings.param,
              (text) => onChanged(settings.copyWith(param: text.trim())), hint: paramHint),
          path('pagination-has-more', 'Has more (JSON path, optional)', settings.hasMorePath,
              (text) => onChanged(settings.copyWith(hasMorePath: text.trim())), hint: 'e.g. has_more'),
        ],
      PaginationKind.page => [
          const SizedBox(height: 10),
          location,
          path('pagination-param', 'Page parameter', settings.param,
              (text) => onChanged(settings.copyWith(param: text.trim())), hint: paramHint),
          path('pagination-total', 'Total pages (JSON path, optional)', settings.totalPath,
              (text) => onChanged(settings.copyWith(totalPath: text.trim())), hint: 'e.g. total_pages'),
          path('pagination-has-more', 'Has more (JSON path, optional)', settings.hasMorePath,
              (text) => onChanged(settings.copyWith(hasMorePath: text.trim())), hint: 'e.g. has_more'),
        ],
      PaginationKind.offset => [
          const SizedBox(height: 10),
          location,
          path('pagination-param', 'Offset parameter', settings.param,
              (text) => onChanged(settings.copyWith(param: text.trim())), hint: paramHint),
          path('pagination-limit', 'Limit parameter (optional)', settings.limitParam,
              (text) => onChanged(settings.copyWith(limitParam: text.trim())), hint: 'e.g. limit'),
          path('pagination-total', 'Total items (JSON path, optional)', settings.totalPath,
              (text) => onChanged(settings.copyWith(totalPath: text.trim())), hint: 'e.g. total'),
        ],
    };
  }

  Widget _pathField(String key, String label, String value, ValueChanged<String> onChanged, {String? hint}) => Padding(
        padding: const EdgeInsets.only(top: 10),
        child: SyncedTextField(key: ValueKey(key), value: value, labelText: label, hintText: hint, onChanged: onChanged),
      );
}
