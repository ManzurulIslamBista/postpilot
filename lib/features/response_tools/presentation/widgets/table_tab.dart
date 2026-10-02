import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/info_banner.dart';
import '../../domain/services/json_table.dart';
import '../view_models/response_tools_view_model.dart';

/// The first array of objects in the response as a table, with CSV export.
class TableTab extends StatelessWidget {
  final ResponseToolsViewModel viewModel;
  const TableTab({super.key, required this.viewModel});

  static const _maxShown = 200;

  @override
  Widget build(BuildContext context) {
    final data = viewModel.data;
    final table = data.isJson ? JsonTable.find(data.json) : null;
    if (table == null) {
      return const EmptyHint(
        icon: Icons.table_chart_outlined,
        title: 'No list of objects found',
        message: 'The table view needs a JSON array of objects, at the top level or inside the first few levels '
            '(for example data.items or result).',
      );
    }
    final colors = context.colors;
    final shown = table.rows.take(_maxShown).toList();
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.table_rows_outlined, size: 16, color: colors.secondaryText),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${table.path.isEmpty ? 'Response' : table.path} · ${table.rows.length} rows · ${table.columns.length} columns'
                  '${table.rows.length > _maxShown ? ' (showing $_maxShown)' : ''}',
                  style: context.textStyles.caption.copyWith(color: colors.secondaryText),
                ),
              ),
              FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: table.toCsv()));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('CSV copied')));
                  }
                },
                icon: const Icon(Icons.download_outlined, size: 16),
                label: const Text('Copy as CSV'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: colors.appBackground,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
                      headingRowHeight: 38,
                      dataRowMinHeight: 34,
                      dataRowMaxHeight: 34,
                      columnSpacing: 22,
                      headingTextStyle: context.textStyles.caption.copyWith(fontWeight: FontWeight.w700, color: colors.syntaxKey),
                      columns: [for (final c in table.columns) DataColumn(label: Text(c))],
                      rows: [
                        for (final row in shown)
                          DataRow(
                            cells: [
                              for (final c in table.columns)
                                DataCell(
                                  ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 260),
                                    child: Text(
                                      JsonTable.cell(row[c]),
                                      overflow: TextOverflow.ellipsis,
                                      style: context.textStyles.mono.copyWith(fontSize: 12),
                                    ),
                                  ),
                                  onTap: () async {
                                    await Clipboard.setData(ClipboardData(text: JsonTable.cell(row[c])));
                                    if (context.mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cell copied')));
                                    }
                                  },
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
