import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/shared_features/prompt_dialog.dart';
import '../../../../core/shortcuts/app_shortcuts.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../../core/utils/file_download.dart';
import '../../../../core/utils/set_cookie.dart';
import '../../domain/entities/api_response_entity.dart';
import '../../domain/entities/response_example_entity.dart';
import '../../../response_tools/domain/services/response_history.dart';
import '../../../response_tools/presentation/widgets/response_tools_dialog.dart';
import '../view_models/response_examples_view_model.dart';
import 'response_body_formatter.dart';
import 'response_body_view.dart';
import 'response_examples_tab.dart';

/// Narrower than this, the body toolbar wraps its search box onto a second row.
const _toolbarOneLineMinWidth = 460.0;

/// At least this wide, the status chips sit on the same line as the tabs.
const _headerOneLineMinWidth = 600.0;

/// Lets the screen around a [ResponseViewer] open its body search, which is
/// what Ctrl/Cmd+F does, and save the response as an example (Ctrl/Cmd+Shift+S).
/// The viewer attaches itself while it is on screen.
class ResponseFindController {
  VoidCallback? _open;
  VoidCallback? _saveExample;

  void open() => _open?.call();

  void saveExample() => _saveExample?.call();
}

class ResponseViewer extends StatefulWidget {
  /// The latest response, or null before the first send and after a failed
  /// one; the saved examples stay reachable either way.
  final ApiResponseEntity? response;

  /// The request whose saved examples are listed and added to.
  final int requestId;

  /// Base name for downloaded body files; falls back to "response".
  final String? requestName;

  /// False hides "Save as example", for a response that belongs to no saved
  /// request (a team request has no local row to attach an example to).
  final bool canSaveExamples;

  /// Optional hook for opening the body search from outside (Ctrl/Cmd+F).
  final ResponseFindController? findController;

  const ResponseViewer({
    super.key,
    required this.response,
    required this.requestId,
    this.requestName,
    this.canSaveExamples = true,
    this.findController,
  });

  @override
  State<ResponseViewer> createState() => _ResponseViewerState();
}

class _ResponseViewerState extends State<ResponseViewer> {
  static const _searchDebounce = Duration(milliseconds: 250);

  late final ResponseExamplesViewModel _examplesViewModel;
  // Picked up from the DefaultTabController below (the examples list switches
  // tabs through it too); Ctrl/Cmd+F uses it to return to the Body tab.
  TabController? _tabs;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _searchTimer;
  ResponseBodyMode _mode = ResponseBodyMode.pretty;
  String _query = '';
  int _currentMatch = 0;
  ResponseBodyFormatter? _liveFormatter;
  ResponseExampleEntity? _selectedExample;
  ResponseBodyFormatter? _exampleFormatter;

  // Matches are only recomputed when the shown text or the query changes, not
  // on every rebuild the parent triggers.
  String? _searchedText;
  String _searchedQuery = '';
  List<int> _matches = const [];

  @override
  void initState() {
    super.initState();
    _examplesViewModel = locator<ResponseExamplesViewModel>()..watch(widget.requestId);
    _liveFormatter = _formatterFor(widget.response);
    _remember(widget.response);
    widget.findController?._open = _openSearch;
    widget.findController?._saveExample = _saveLiveResponseAsExample;
  }

  @override
  void didUpdateWidget(covariant ResponseViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.findController != oldWidget.findController) {
      if (oldWidget.findController?._open == _openSearch) oldWidget.findController?._open = null;
      if (oldWidget.findController?._saveExample == _saveLiveResponseAsExample) oldWidget.findController?._saveExample = null;
      widget.findController?._open = _openSearch;
      widget.findController?._saveExample = _saveLiveResponseAsExample;
    }
    if (widget.response != oldWidget.response) {
      _liveFormatter = _formatterFor(widget.response);
      _remember(widget.response);
      _selectedExample = null;
      _exampleFormatter = null;
      _currentMatch = 0;
    }
    if (widget.requestId != oldWidget.requestId) {
      _examplesViewModel.watch(widget.requestId);
      _selectedExample = null;
      _exampleFormatter = null;
      _currentMatch = 0;
    }
  }

  /// Keeps each response for "Compare" in the response tools.
  void _remember(ApiResponseEntity? response) {
    if (response != null && locator.isRegistered<ResponseHistory>()) {
      locator<ResponseHistory>().record(widget.requestId, response);
    }
  }

  @override
  void dispose() {
    if (widget.findController?._open == _openSearch) widget.findController?._open = null;
    if (widget.findController?._saveExample == _saveLiveResponseAsExample) widget.findController?._saveExample = null;
    _searchTimer?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    _examplesViewModel.dispose();
    super.dispose();
  }

  ResponseBodyFormatter? _formatterFor(ApiResponseEntity? response) => response == null
      ? null
      : ResponseBodyFormatter(response.headers, response.bodyBytes, truncated: response.truncated);

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<ResponseExamplesViewModel>.value(
      value: _examplesViewModel,
      child: Consumer<ResponseExamplesViewModel>(
        builder: (context, vm, _) {
          final example = _currentExample(vm.examples);
          final formatter = example == null ? _liveFormatter : _exampleFormatter;
          final headers = example?.headers ?? widget.response?.headers;
          return DefaultTabController(
            length: 3,
            child: Builder(
              builder: (context) {
                _tabs = DefaultTabController.of(context);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildHeader(example, vm.examples.length),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildBodyTab(context, formatter, example: example),
                          _buildHeadersTab(context, headers, setCookies: example == null ? widget.response?.setCookies : null),
                          ResponseExamplesTab(selectedId: example?.id, onSelect: _selectExample),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          );
        },
      ),
    );
  }

  /// The status/time/size chips and the Body/Headers/Examples tabs. On one line
  /// when the pane is wide enough (saving a row of height for the body), stacked
  /// otherwise.
  Widget _buildHeader(ResponseExampleEntity? example, int exampleCount) {
    TabBar tabs({required bool divider}) => TabBar(
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      // On one line the row draws the divider itself, under the chips as well.
      dividerHeight: divider ? null : 0,
      tabs: [
        const Tab(text: 'Body'),
        const Tab(text: 'Headers'),
        Tab(text: 'Examples ($exampleCount)'),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final summary = _buildSummary(example);
        if (constraints.maxWidth < _headerOneLineMinWidth) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: summary),
              tabs(divider: true),
            ],
          );
        }
        return DecoratedBox(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: context.colors.borderSubtle)),
          ),
          child: Row(
            children: [
              Expanded(child: tabs(divider: false)),
              Padding(padding: const EdgeInsets.only(left: 8), child: summary),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummary(ResponseExampleEntity? example) {
    if (example != null) return ResponseExampleSummary(example: example, onClose: _clearExample);
    final response = widget.response;
    return response == null ? const _NoResponseSummary() : _LiveSummary(response: response);
  }

  Widget _buildBodyTab(
    BuildContext context,
    ResponseBodyFormatter? formatter, {
    required ResponseExampleEntity? example,
  }) {
    if (formatter == null) return const _EmptyState();
    final viewingExample = example != null;
    final isImage = formatter.kind == ResponseContentKind.image;
    final displayText = isImage ? null : formatter.displayTextFor(_mode);
    final matches = displayText == null ? const <int>[] : _matchesFor(displayText);
    final current = matches.isEmpty ? 0 : _currentMatch.clamp(0, matches.length - 1);
    final response = widget.response;
    final body = formatter.text;
    // Whether what is shown is only the first part of the body.
    final cutOff = example?.truncated ?? response?.truncated ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final actions = [
                IconButton(
                  icon: const Icon(Icons.copy, size: 18),
                  tooltip: 'Copy body',
                  onPressed: formatter.isTextual ? () => _copy(context, formatter.textFor(_mode), 'Body copied') : null,
                ),
                IconButton(
                  icon: const Icon(Icons.download, size: 18),
                  tooltip: 'Download body',
                  onPressed: () => _download(context, formatter, cutOff: cutOff),
                ),
                if (widget.canSaveExamples)
                  IconButton(
                    icon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    tooltip: formatter.isTextual ? 'Save as example' : "Binary responses can't be saved as examples",
                    onPressed: !viewingExample && response != null && body != null && formatter.isTextual
                        ? () => _saveAsExample(context, response, body)
                        : null,
                  ),
                IconButton(
                  icon: const Icon(Icons.auto_fix_high, size: 18),
                  tooltip: 'Response tools',
                  onPressed: !viewingExample && response != null && formatter.isTextual
                      ? () => ResponseToolsDialog.show(
                            context,
                            requestId: widget.requestId,
                            requestName: widget.requestName ?? 'Response',
                            response: response,
                          )
                      : null,
                ),
              ];
              if (isImage) return Row(children: [const Spacer(), ...actions]);
              final search = _buildSearchField(context, matches.length, current);
              // A narrow response pane (dragged thin, or a phone) cannot fit the
              // mode switch, a usable search box and the actions on one line:
              // search drops to its own row instead of being squeezed to nothing.
              if (constraints.maxWidth < _toolbarOneLineMinWidth) {
                return Column(
                  children: [
                    Row(
                      children: [
                        _ModeSelector(mode: _mode, onChanged: _setMode),
                        const Spacer(),
                        ...actions,
                      ],
                    ),
                    const SizedBox(height: 8),
                    search,
                  ],
                );
              }
              return Row(
                children: [
                  _ModeSelector(mode: _mode, onChanged: _setMode),
                  const SizedBox(width: 8),
                  Expanded(child: search),
                  ...actions,
                ],
              );
            },
          ),
        ),
        if (cutOff) _SizeLimitNotice(forExample: viewingExample),
        if (displayText != null && formatter.isTruncated(_mode))
          _TruncationNotice(shown: displayText.length, total: formatter.textFor(_mode).length),
        Expanded(
          child: ResponseBodyView(
            formatter: formatter,
            mode: _mode,
            query: _query,
            matchIndices: matches,
            currentMatch: current,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchField(BuildContext context, int matchCount, int current) {
    final capped = matchCount >= maxSearchHighlights;
    return CallbackShortcuts(
      bindings: {const SingleActivator(LogicalKeyboardKey.escape): _closeSearch},
      child: TextField(
        focusNode: _searchFocus,
        controller: _searchController,
        style: context.textStyles.caption,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search body',
          prefixIcon: const Icon(Icons.search, size: 16),
          prefixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          suffixIcon: _query.isEmpty
              ? null
              : _MatchNavigator(
                  label: matchCount == 0 ? 'No matches' : '${current + 1}/$matchCount${capped ? '+' : ''}',
                  hasMatches: matchCount > 0,
                  onPrevious: () => _stepMatch(-1),
                  onNext: () => _stepMatch(1),
                  onClear: _clearSearch,
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        ),
        onChanged: _onSearchChanged,
        // Keeps focus in the field, so Enter can step through the matches repeatedly.
        onEditingComplete: () {},
        onSubmitted: (_) => _stepMatch(HardwareKeyboard.instance.isShiftPressed ? -1 : 1),
      ),
    );
  }

  /// One row per header, except `Set-Cookie`, which gets one row per cookie:
  /// joined into a single line the cookies cannot be told apart, and a cookie's
  /// `Expires` date has a comma of its own.
  List<MapEntry<String, String>> _headerRows(Map<String, String> headers, List<String>? setCookies) => [
        for (final entry in headers.entries)
          if (entry.key.toLowerCase() == 'set-cookie')
            for (final cookie in (setCookies != null && setCookies.isNotEmpty ? setCookies : SetCookies.split(entry.value)))
              MapEntry(entry.key, cookie)
          else
            entry,
      ];

  Widget _buildHeadersTab(BuildContext context, Map<String, String>? headers, {List<String>? setCookies}) {
    if (headers == null) return const _EmptyState();
    final rows = _headerRows(headers, setCookies);
    final headersText = rows.map((e) => '${e.key}: ${e.value}').join('\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 8),
          child: Row(
            children: [
              Text('${rows.length} headers', style: context.textStyles.caption),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.copy, size: 18),
                tooltip: 'Copy headers',
                onPressed: rows.isEmpty ? null : () => _copy(context, headersText, 'Headers copied'),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(8),
            children: [
              for (final entry in rows)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: SelectableText('${entry.key}: ${entry.value}', style: context.textStyles.mono),
                ),
            ],
          ),
        ),
      ],
    );
  }

  List<int> _matchesFor(String text) {
    if (!identical(text, _searchedText) || _query != _searchedQuery) {
      _searchedText = text;
      _searchedQuery = _query;
      _matches = findMatches(text, _query);
    }
    return _matches;
  }

  void _setMode(ResponseBodyMode mode) => setState(() {
    _mode = mode;
    _currentMatch = 0;
  });

  void _onSearchChanged(String value) {
    _searchTimer?.cancel();
    _searchTimer = Timer(_searchDebounce, () => _commitQuery(value));
  }

  void _commitQuery(String value) {
    if (!mounted) return;
    setState(() {
      _query = value;
      _currentMatch = 0;
    });
  }

  void _stepMatch(int step) {
    // Enter straight after typing applies the pending query rather than stepping.
    if (_searchTimer?.isActive ?? false) {
      _searchTimer!.cancel();
      _commitQuery(_searchController.text);
      return;
    }
    if (_matches.isEmpty) return;
    setState(() => _currentMatch = (_currentMatch + step) % _matches.length);
  }

  /// Ctrl/Cmd+F: show the body search and put the caret in it, ready to type.
  void _openSearch() {
    final tabs = _tabs;
    if (tabs != null && tabs.index != 0) tabs.index = 0;
    // The rendered preview has no text to search; Pretty does.
    if (_mode == ResponseBodyMode.preview) setState(() => _mode = ResponseBodyMode.pretty);
    _focusSearchWhenReady(10);
  }

  // The field only exists once the Body tab has been built, a frame or two
  // after switching to it, so keep trying for a few frames.
  void _focusSearchWhenReady(int framesLeft) {
    WidgetsBinding.instance
      ..addPostFrameCallback((_) {
        if (!mounted) return;
        if (_searchFocus.context == null) {
          if (framesLeft > 0) _focusSearchWhenReady(framesLeft - 1);
          return;
        }
        _searchFocus.requestFocus();
        // Selected, so typing replaces the previous search, as in a browser.
        _searchController.selection = TextSelection(baseOffset: 0, extentOffset: _searchController.text.length);
      })
      ..scheduleFrame();
  }

  void _closeSearch() {
    _clearSearch();
    _searchFocus.unfocus();
  }

  void _clearSearch() {
    _searchTimer?.cancel();
    setState(() {
      _searchController.clear();
      _query = '';
      _currentMatch = 0;
    });
  }

  ResponseExampleEntity? _currentExample(List<ResponseExampleEntity> examples) {
    final id = _selectedExample?.id;
    if (id == null) return null;
    for (final example in examples) {
      if (example.id == id) return example;
    }
    return null;
  }

  void _selectExample(ResponseExampleEntity example) {
    setState(() {
      _selectedExample = example;
      _exampleFormatter = ResponseBodyFormatter.fromText(example.headers, example.body);
      _currentMatch = 0;
    });
  }

  void _clearExample() {
    setState(() {
      _selectedExample = null;
      _exampleFormatter = null;
      _currentMatch = 0;
    });
  }

  void _copy(BuildContext context, String text, String message) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _download(BuildContext context, ResponseBodyFormatter formatter, {required bool cutOff}) async {
    final messenger = ScaffoldMessenger.of(context);
    if (cutOff) {
      final proceed = await showConfirmDialog(
        context,
        title: 'Incomplete body',
        message:
            'This body was cut off at the response size limit, so the file will be incomplete — '
            'an archive, PDF or image made from it may not open. Raise the limit in Settings to get the whole body.',
        confirmLabel: 'Download anyway',
      );
      if (!proceed) return;
    }
    try {
      final path = await downloadFile(
        fileName: formatter.downloadFileName(requestName: widget.requestName),
        bytes: formatter.bytes,
        mimeType: formatter.downloadMimeType,
      );
      if (path != null) messenger.showSnackBar(SnackBar(content: Text('Saved to $path')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text("Couldn't save file: $e")));
    }
  }

  /// The shortcut's route into "Save as example": the live response, never an example being viewed. Says why
  /// when there is nothing to save, since a shortcut that does nothing looks broken.
  void _saveLiveResponseAsExample() {
    final response = widget.response;
    final formatter = _liveFormatter;
    final body = formatter?.text;
    final String? reason = !widget.canSaveExamples
        ? 'This request has no saved row to attach an example to'
        : response == null
        ? 'Send the request first: there is no response to save'
        : formatter == null || body == null || !formatter.isTextual
        ? "Binary responses can't be saved as examples"
        : _selectedExample != null
        ? 'Switch back to the live response to save it as an example'
        : null;
    if (reason != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(reason)));
      return;
    }
    _saveAsExample(context, response!, body!);
  }

  Future<void> _saveAsExample(BuildContext context, ApiResponseEntity response, String body) async {
    if (response.truncated) {
      final proceed = await showConfirmDialog(
        context,
        title: 'Save a partial body?',
        message:
            'This response was cut off at the size limit, so the example will hold only the first part of it. '
            'Raise the limit in Settings to keep the whole body.',
        confirmLabel: 'Save anyway',
      );
      if (!proceed || !context.mounted) return;
    }
    final name = await showPromptDialog(
      context,
      title: 'Save as example',
      initialValue: '${response.statusCode} ${response.statusMessage}'.trim(),
    );
    if (name == null) return;
    await _examplesViewModel.saveExample(name: name, response: response, body: body);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Example saved')));
  }
}

class _LiveSummary extends StatelessWidget {
  final ApiResponseEntity response;
  const _LiveSummary({required this.response});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        StatusChip(
          label: '${response.statusCode} ${response.statusMessage}'.trim(),
          icon: response.isSuccess ? Icons.check_circle_outline : Icons.error_outline,
          color: context.colors.forStatus(response.statusCode),
        ),
        StatusChip(label: '${response.duration.inMilliseconds} ms', icon: Icons.schedule),
        StatusChip(label: _formatSize(response.sizeBytes), icon: Icons.data_usage),
      ],
    );
  }

  String _formatSize(int bytes) => bytes < 1024 ? '$bytes B' : '${(bytes / 1024).toStringAsFixed(1)} KB';
}

class _NoResponseSummary extends StatelessWidget {
  const _NoResponseSummary();

  @override
  Widget build(BuildContext context) =>
      Text('No response yet. Press Send or ${AppShortcut.sendRequest.keyLabel}.', style: context.textStyles.caption);
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        'Press Send or ${AppShortcut.sendRequest.keyLabel} to see the response, or open a saved example from the Examples tab.',
        textAlign: TextAlign.center,
        style: context.textStyles.caption,
      ),
    );
  }
}

class _SizeLimitNotice extends StatelessWidget {
  /// A saved example carries the cut-off with it, long after the limit that
  /// caused it was hit.
  final bool forExample;
  const _SizeLimitNotice({required this.forExample});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: context.colors.mainAccent.withValues(alpha: 0.12),
      child: Text(
        forExample
            ? 'This example holds only the first part of the response: it was cut off at the size limit when saved'
            : 'Response larger than the limit was cut off — raise the limit in Settings',
        style: context.textStyles.caption,
      ),
    );
  }
}

class _TruncationNotice extends StatelessWidget {
  final int shown;
  final int total;
  const _TruncationNotice({required this.shown, required this.total});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      color: context.colors.mainAccent.withValues(alpha: 0.12),
      child: Text(
        'Showing the first ${_compact(shown)} of ${_compact(total)} characters, and search covers only that part. '
        'Copy or Download gives the full body.',
        style: context.textStyles.caption,
      ),
    );
  }

  String _compact(int count) {
    if (count >= 1000000) return '${(count / 1000000).toStringAsFixed(1)}M';
    if (count >= 1000) return '${(count / 1000).round()}K';
    return '$count';
  }
}

class _MatchNavigator extends StatelessWidget {
  final String label;
  final bool hasMatches;
  final VoidCallback onPrevious;
  final VoidCallback onNext;
  final VoidCallback onClear;

  const _MatchNavigator({
    required this.label,
    required this.hasMatches,
    required this.onPrevious,
    required this.onNext,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: context.textStyles.caption),
        ),
        _button(Icons.keyboard_arrow_up, 'Previous match (Shift+Enter)', hasMatches ? onPrevious : null),
        _button(Icons.keyboard_arrow_down, 'Next match (Enter)', hasMatches ? onNext : null),
        _button(Icons.close, 'Clear search', onClear),
      ],
    );
  }

  Widget _button(IconData icon, String tooltip, VoidCallback? onPressed) => IconButton(
    icon: Icon(icon, size: 16),
    tooltip: tooltip,
    padding: EdgeInsets.zero,
    constraints: const BoxConstraints.tightFor(width: 24, height: 24),
    onPressed: onPressed,
  );
}

class _ModeSelector extends StatelessWidget {
  final ResponseBodyMode mode;
  final ValueChanged<ResponseBodyMode> onChanged;
  const _ModeSelector({required this.mode, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ResponseBodyMode>(
      segments: const [
        ButtonSegment(value: ResponseBodyMode.pretty, label: Text('Pretty')),
        ButtonSegment(value: ResponseBodyMode.raw, label: Text('Raw')),
        ButtonSegment(value: ResponseBodyMode.preview, label: Text('Preview')),
      ],
      selected: {mode},
      showSelectedIcon: false,
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        padding: const WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 10)),
        textStyle: WidgetStatePropertyAll(context.textStyles.caption),
      ),
      onSelectionChanged: (selection) => onChanged(selection.first),
    );
  }
}
