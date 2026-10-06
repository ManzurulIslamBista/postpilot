import 'package:flutter/material.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../../request_builder/domain/entities/key_value_item.dart';
import '../../../request_builder/presentation/widgets/response_body_formatter.dart';
import '../../../request_builder/presentation/widgets/response_body_view.dart';
import '../../domain/entities/history_entry_entity.dart';
import '../../domain/entities/history_snapshot.dart';
import 'highlighted_text.dart';
import 'history_format.dart';

/// The Request tab: what was sent, as it was saved (`{{variables}}` as written, credentials masked).
class HistoryRequestView extends StatelessWidget {
  final HistoryRequestSnapshot snapshot;
  final String needle;
  const HistoryRequestView({super.key, required this.snapshot, required this.needle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono;
    final body = snapshot.body;
    final auth = snapshot.auth;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        ToolSection(
          title: 'Request',
          child: SelectableText.rich(
            TextSpan(
              style: mono,
              children: [
                TextSpan(text: '${snapshot.method.label} ', style: TextStyle(color: colors.forMethod(snapshot.method.label), fontWeight: FontWeight.w700)),
                ...highlightedSpans(context, snapshot.fullUrl, needle),
              ],
            ),
          ),
        ),
        if (snapshot.headers.isNotEmpty) ToolSection(title: 'Headers', child: _Pairs(items: snapshot.headers, needle: needle)),
        if (snapshot.queryParams.isNotEmpty)
          ToolSection(title: 'Query parameters', child: _Pairs(items: snapshot.queryParams, needle: needle)),
        if (auth.type != AuthType.none && auth.type != AuthType.inherit)
          ToolSection(
            title: 'Authorization',
            child: Text(
              '${auth.type.label}${snapshot.hasMaskedValues ? ': credentials were masked' : ''}',
              style: context.textStyles.body,
            ),
          ),
        if (body.type == BodyType.raw && body.rawText.isNotEmpty)
          ToolSection(
            title: 'Body (${body.rawContentType.name})',
            child: HistoryTextBlock(text: body.rawText, contentType: body.rawContentType.mimeType, needle: needle),
          ),
        if (body.type == BodyType.graphql) ...[
          ToolSection(title: 'GraphQL query', child: HistoryTextBlock(text: body.graphqlQuery, contentType: 'text/plain', needle: needle)),
          if (body.graphqlVariables.trim().isNotEmpty && body.graphqlVariables.trim() != '{}')
            ToolSection(
              title: 'GraphQL variables',
              child: HistoryTextBlock(text: body.graphqlVariables, contentType: 'application/json', needle: needle),
            ),
        ],
        if (body.type == BodyType.urlEncoded && body.urlEncodedFields.isNotEmpty)
          ToolSection(title: 'Form fields', child: _Pairs(items: body.urlEncodedFields, needle: needle)),
        if (body.type == BodyType.formData && body.formFields.any((f) => !(f.isFile && f.key.isEmpty)))
          ToolSection(
            title: 'Form data',
            child: _Pairs(items: [for (final f in body.formFields) if (!(f.isFile && f.key.isEmpty)) f], needle: needle),
          ),
        // Only the reference to the file is in History, never the file.
        if (body.type == BodyType.binary && body.binaryFile != null)
          ToolSection(title: 'Body (binary file)', child: _Pairs(items: [body.binaryFile!.copyWith(key: 'file')], needle: needle)),
        if (snapshot.headers.isEmpty &&
            snapshot.queryParams.isEmpty &&
            body.type == BodyType.none &&
            (auth.type == AuthType.none || auth.type == AuthType.inherit))
          Text('No headers, parameters or body.', style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
      ],
    );
  }
}

/// `Name: value` rows; a disabled row is dimmed.
class _Pairs extends StatelessWidget {
  final List<KeyValueItem> items;
  final String needle;
  const _Pairs({required this.items, required this.needle});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final mono = context.textStyles.mono;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: SelectableText.rich(
              TextSpan(
                style: item.enabled ? mono : mono.copyWith(color: colors.secondaryText, decoration: TextDecoration.lineThrough),
                children: [
                  ...highlightedSpans(
                    context,
                    '${item.key}: ',
                    needle,
                    style: TextStyle(color: item.enabled ? colors.syntaxKey : colors.secondaryText, fontWeight: FontWeight.w600),
                  ),
                  ...highlightedSpans(context, item.isFile ? '@${item.value}' : item.value, needle),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A body as a bordered, syntax-coloured block that is as tall as its text, up to a limit; the search is marked in it.
class HistoryTextBlock extends StatefulWidget {
  final String text;
  final String contentType;
  final String needle;

  /// Fixed height instead of fitting the text.
  final double? height;
  const HistoryTextBlock({super.key, required this.text, required this.contentType, required this.needle, this.height});

  @override
  State<HistoryTextBlock> createState() => _HistoryTextBlockState();
}

class _HistoryTextBlockState extends State<HistoryTextBlock> {
  late ResponseBodyFormatter _formatter = _build();

  ResponseBodyFormatter _build() => ResponseBodyFormatter.fromText({'content-type': widget.contentType}, widget.text);

  @override
  void didUpdateWidget(covariant HistoryTextBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text || oldWidget.contentType != widget.contentType) _formatter = _build();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final shown = _formatter.displayTextFor(ResponseBodyMode.pretty);
    final lines = '\n'.allMatches(shown).length + 1;
    final height = widget.height ?? (lines * 19.0 + 30).clamp(56.0, 300.0);
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: colors.appBackground,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ResponseBodyView(
        formatter: _formatter,
        mode: ResponseBodyMode.pretty,
        query: widget.needle,
        matchIndices: findMatches(shown, widget.needle),
      ),
    );
  }
}

/// The Response tab: the status line, a note on what is not kept, and the stored body.
class HistoryResponseView extends StatefulWidget {
  final HistoryEntryEntity entry;
  final HistoryDetail? detail;
  final String needle;
  const HistoryResponseView({super.key, required this.entry, required this.detail, required this.needle});

  @override
  State<HistoryResponseView> createState() => _HistoryResponseViewState();
}

class _HistoryResponseViewState extends State<HistoryResponseView> {
  ResponseBodyMode _mode = ResponseBodyMode.pretty;
  ResponseBodyFormatter? _formatter;
  HistoryDetail? _formatted;

  ResponseBodyFormatter _formatterFor(HistoryDetail detail) {
    if (!identical(_formatted, detail) || _formatter == null) {
      _formatted = detail;
      _formatter = ResponseBodyFormatter.fromText(
        {if (detail.responseContentType != null) 'content-type': detail.responseContentType!},
        detail.responseText ?? '',
      );
    }
    return _formatter!;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final entry = widget.entry;
    final detail = widget.detail;
    final meta = entry.meta;
    final caption = context.textStyles.caption.copyWith(color: colors.secondaryText);

    if (entry.statusCode == null) {
      return Padding(
        padding: const EdgeInsets.all(14),
        child: InfoBanner(
          kind: BannerKind.error,
          title: 'No response',
          message: meta?.error ?? 'The request failed before any response arrived.',
        ),
      );
    }

    final size = entrySize(entry);
    final body = detail != null && detail.hasResponseBody ? detail.responseText! : null;
    final formatter = body == null ? null : _formatterFor(detail!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              HistoryStatusChip(entry: entry),
              if (meta?.statusMessage != null) Text(meta!.statusMessage!, style: context.textStyles.body),
              if (entry.durationMs != null) Text(formatDuration(entry.durationMs!), style: caption),
              if (size != null) Text(size, style: caption),
              if (detail?.responseContentType != null) Text(detail!.responseContentType!, style: caption),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Text(
            'Response headers are not kept in History: they can hold cookies and tokens.',
            style: caption,
          ),
        ),
        if (detail?.responseTruncated == true)
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 0),
            child: const InfoBanner(
              kind: BannerKind.warning,
              message: 'Only the first part of this response is kept: it was longer than the limit in Settings > History.',
            ),
          ),
        const SizedBox(height: 8),
        if (formatter == null)
          Expanded(
            child: EmptyHint(
              icon: Icons.inbox_outlined,
              title: 'No response body kept',
              message: entry.hasDetails
                  ? 'The body was empty or not text (an image, a file), so only its size is recorded.'
                  : 'This entry was recorded without details, or "Keep request/response bodies in history" was off (Settings > History).',
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SegmentedButton<ResponseBodyMode>(
                showSelectedIcon: false,
                style: const ButtonStyle(visualDensity: VisualDensity.compact),
                segments: const [
                  ButtonSegment(value: ResponseBodyMode.pretty, label: Text('Pretty')),
                  ButtonSegment(value: ResponseBodyMode.raw, label: Text('Raw')),
                ],
                selected: {_mode},
                onSelectionChanged: (selection) => setState(() => _mode = selection.first),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              decoration: BoxDecoration(
                color: colors.appBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ResponseBodyView(
                formatter: formatter,
                mode: _mode,
                query: widget.needle,
                matchIndices: findMatches(formatter.displayTextFor(_mode), widget.needle),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
