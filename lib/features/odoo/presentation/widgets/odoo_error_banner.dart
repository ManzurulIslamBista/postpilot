import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../request_builder/domain/entities/api_response_entity.dart';
import '../../domain/services/odoo_error_parser.dart';

/// Appears above a response when it is an Odoo error, turning the raw
/// exception into a title, what it means, what to check, and the traceback
/// frames that matter. Shows nothing for any other response.
class OdooErrorBanner extends StatefulWidget {
  final ApiResponseEntity response;
  const OdooErrorBanner({super.key, required this.response});

  @override
  State<OdooErrorBanner> createState() => _OdooErrorBannerState();
}

class _OdooErrorBannerState extends State<OdooErrorBanner> {
  OdooErrorInfo? _info;
  ApiResponseEntity? _parsedFor;
  bool _open = false;

  OdooErrorInfo? _parse() {
    if (identical(_parsedFor, widget.response)) return _info;
    _parsedFor = widget.response;
    _open = false;
    final r = widget.response;
    if (r.bodyBytes.isEmpty || r.bodyBytes.length > 512 * 1024 || r.bodyBytes.first != 0x7B) return _info = null;
    return _info = OdooErrorParser.parse(utf8.decode(r.bodyBytes, allowMalformed: true), statusCode: r.statusCode);
  }

  @override
  Widget build(BuildContext context) {
    final info = _parse();
    if (info == null) return const SizedBox.shrink();
    final colors = context.colors;
    final hasMore = info.frames.isNotEmpty || info.failingLine != null;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        color: colors.statusError.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.statusError.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.bug_report_outlined, size: 18, color: colors.statusError),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Odoo: ${info.title}',
                      style: context.textStyles.body.copyWith(fontWeight: FontWeight.w700, color: colors.statusError),
                    ),
                    if (info.message.isNotEmpty) SelectableText(info.message, style: context.textStyles.body),
                    if (info.hint != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(info.hint!, style: context.textStyles.caption.copyWith(color: colors.secondaryText)),
                      ),
                  ],
                ),
              ),
              if (hasMore)
                TextButton(
                  style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                  onPressed: () => setState(() => _open = !_open),
                  child: Text(_open ? 'Hide details' : 'Details'),
                ),
            ],
          ),
          if (_open) ...[
            const SizedBox(height: 6),
            if (info.exception.isNotEmpty) SelectableText(info.exception, style: context.textStyles.mono.copyWith(fontSize: 12, color: colors.syntaxKey)),
            for (final f in info.frames) SelectableText(f, style: context.textStyles.mono.copyWith(fontSize: 11.5, color: colors.secondaryText)),
            if (info.failingLine != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: SelectableText(info.failingLine!, style: context.textStyles.mono.copyWith(fontSize: 12, color: colors.statusError)),
              ),
          ],
        ],
      ),
    );
  }
}
