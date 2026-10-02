import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/code_block.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/quick_decoder.dart';
import '../view_models/response_tools_view_model.dart';

/// Decodes what is inside the response (JWTs, Unix timestamps) and anything
/// the user pastes (Base64, URL-encoded text, a token, a timestamp).
class DecodeTab extends StatefulWidget {
  final ResponseToolsViewModel viewModel;
  const DecodeTab({super.key, required this.viewModel});

  @override
  State<DecodeTab> createState() => _DecodeTabState();
}

class _DecodeTabState extends State<DecodeTab> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  String _relative(DateTime t) {
    final d = t.difference(DateTime.now().toUtc());
    final abs = d.abs();
    final span = abs.inDays >= 1
        ? '${abs.inDays} d'
        : abs.inHours >= 1
            ? '${abs.inHours} h'
            : abs.inMinutes >= 1
                ? '${abs.inMinutes} min'
                : '${abs.inSeconds} s';
    return d.isNegative ? '$span ago' : 'in $span';
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.viewModel.data;
    final colors = context.colors;
    final jwts = data.isJson ? JwtDecoder.findIn(data.json) : <String, String>{};
    final stamps = data.isJson ? EpochConverter.findIn(data.json) : const <({String path, num value, EpochGuess guess})>[];
    final results = QuickDecoder.decodeAll(_input.text);
    const enc = JsonEncoder.withIndent('  ');
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ToolSection(
          title: 'Found in this response',
          hint: jwts.isEmpty && stamps.isEmpty ? 'No JWT or Unix timestamp found.' : null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in jwts.entries)
                Builder(builder: (context) {
                  final jwt = JwtDecoder.tryDecode(entry.value)!;
                  final exp = jwt.expiresAt;
                  final expired = jwt.isExpired(DateTime.now());
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        InfoBanner(
                          kind: exp == null ? BannerKind.info : (expired ? BannerKind.error : BannerKind.success),
                          title: 'JWT at ${entry.key}',
                          message: exp == null
                              ? 'No expiry claim. Signature not verified.'
                              : '${expired ? 'Expired' : 'Expires'} ${_relative(exp)} (${exp.toIso8601String()}). Signature not verified.',
                        ),
                        const SizedBox(height: 6),
                        SizedBox(height: 150, child: CodeBlock(text: enc.convert({'header': jwt.header, 'payload': jwt.payload}), label: 'JWT')),
                      ],
                    ),
                  );
                }),
              for (final s in stamps)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(Icons.schedule, size: 15, color: colors.secondaryText),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SelectableText.rich(
                          TextSpan(children: [
                            TextSpan(text: '${s.path}  ', style: context.textStyles.mono.copyWith(color: colors.syntaxKey)),
                            TextSpan(text: '${s.value}  ', style: context.textStyles.mono.copyWith(color: colors.syntaxNumber)),
                            TextSpan(
                              text: '${s.guess.utc.toIso8601String()}  (${_relative(s.guess.utc)}, ${s.guess.unit})',
                              style: context.textStyles.caption,
                            ),
                          ]),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        ToolSection(
          title: 'Decode anything',
          hint: 'Paste a JWT, Base64, a URL-encoded string, a Unix timestamp or a date.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: _input,
                minLines: 2,
                maxLines: 5,
                style: context.textStyles.mono,
                decoration: const InputDecoration(hintText: 'eyJhbGciOi…  /  SGVsbG8=  /  1700000000'),
                onChanged: (_) => setState(() {}),
              ),
              const SizedBox(height: 10),
              for (final r in results)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: SizedBox(
                    height: (r.output.split('\n').length * 20.0 + 56).clamp(90.0, 220.0),
                    child: CodeBlock(text: r.output, label: r.kind, wrap: true),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
