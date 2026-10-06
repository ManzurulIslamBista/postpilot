import 'package:flutter/material.dart';
import 'run_triage_controller.dart';
import 'triage_pane.dart';

/// The runner's results with a second tab, Triage: what the finished run says about what broke.
class RunResultsTabs extends StatelessWidget {
  /// The runner's own list of results.
  final Widget results;
  final RunTriageController triage;

  /// Runs only the failed requests again (the runner dialog starts a run with exactly those ticked).
  final ValueChanged<List<int>>? onRerunFailed;

  const RunResultsTabs({super.key, required this.results, required this.triage, this.onRerunFailed});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListenableBuilder(
            listenable: triage,
            builder: (context, _) {
              final report = triage.analysis?.report;
              final causes = report?.groups.length ?? 0;
              return TabBar(
                isScrollable: true,
                tabAlignment: TabAlignment.start,
                tabs: [
                  const Tab(height: 36, text: 'Results'),
                  Tab(height: 36, text: report != null && report.hasFailures ? 'Triage ($causes ${causes == 1 ? 'cause' : 'causes'})' : 'Triage'),
                ],
              );
            },
          ),
          Expanded(
            child: TabBarView(
              physics: const NeverScrollableScrollPhysics(),
              children: [
                results,
                ListenableBuilder(
                  listenable: triage,
                  builder: (context, _) => TriagePane(
                    analysis: triage.analysis,
                    busy: triage.isAnalysing,
                    isPartial: triage.isPartial,
                    note: triage.saveError ?? (triage.savedRecordId == null ? null : 'Saved to the run history of this collection (its menu, Run history).'),
                    noteIsError: triage.saveError != null,
                    onRerunFailed: onRerunFailed,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
