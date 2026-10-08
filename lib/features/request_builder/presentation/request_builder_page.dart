import 'widgets/variables/variable_text_form_field.dart';
import 'view_models/variable_scope.dart';
import '../../defaults/presentation/view_models/inherited_defaults_view_model.dart';
import '../../defaults/presentation/widgets/request_inherited_sections.dart';
import '../../auth_renewal/presentation/widgets/auth_notes_banner.dart';
import '../../auth_renewal/presentation/widgets/inherited_oauth2_status.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/di/injector.dart';
import '../domain/entities/api_request_entity.dart';
import '../../../core/layout/layout_prefs.dart';
import '../../../core/theme/context_theme_extensions.dart';
import '../../../core/widgets/gradient_button.dart';
import '../../../core/widgets/resizable_split.dart';
import '../../cors_proxy/presentation/cors_error_help.dart';
import '../../documentation/presentation/widgets/request_docs_tab.dart';
import '../../auth_doctor/presentation/auth_doctor_banner.dart';
import '../../odoo/presentation/widgets/odoo_error_banner.dart';
import '../../request_flow/presentation/widgets/flow_report_strip.dart';
import '../../request_flow/presentation/widgets/request_flow_tab.dart';
import '../../safety/domain/services/production_guard.dart';
import '../../safety/presentation/production_confirm_dialog.dart';
import '../../scripting/presentation/widgets/request_tests_tab.dart';
import '../../scripting/presentation/widgets/script_results_view.dart';
import '../../settings/presentation/widgets/request_settings_tab.dart';
import '../../shell/presentation/shell_view_model.dart';
import 'view_models/request_builder_view_model.dart';
import 'widgets/auth_editor.dart';
import 'widgets/body_editor.dart';
import 'widgets/code_snippet_dialog.dart';
import 'widgets/key_value_editor.dart';
import 'widgets/method_dropdown.dart';
import 'widgets/response_viewer.dart';

class RequestBuilderPage extends StatefulWidget {
  final int requestId;
  const RequestBuilderPage({required this.requestId}) : super(key: const ValueKey('request-builder'));

  @override
  State<RequestBuilderPage> createState() => _RequestBuilderPageState();
}

class _RequestBuilderPageState extends State<RequestBuilderPage> {
  late final RequestBuilderViewModel _viewModel;
  late final VariableScope _variableScope;

  /// What the request inherits from its collection and folders, shown read-only in the Headers, Auth and Tests tabs.
  late final InheritedDefaultsViewModel _inherited;
  final _responseFind = ResponseFindController();

  /// Ctrl/Cmd+L puts the cursor here.
  final _urlFocus = FocusNode();
  Object? _seenScriptResult;

  @override
  void initState() {
    super.initState();
    _viewModel = locator<RequestBuilderViewModel>();
    _variableScope = locator<VariableScope>();
    _inherited = locator<InheritedDefaultsViewModel>();
    // Variables are layered per collection, which is known once the request has loaded.
    _viewModel.addListener(_bindVariableScope);
    _viewModel.confirmSend = _confirmSend;
    _viewModel.load(widget.requestId);
    locator<ShellViewModel>()
      ..registerSender(widget.requestId, _viewModel.send)
      ..registerBodySearch(widget.requestId, _responseFind.open)
      ..registerTabAction(widget.requestId, TabAction.focusUrl, _urlFocus.requestFocus)
      ..registerTabAction(widget.requestId, TabAction.saveResponseExample, _responseFind.saveExample);
  }

  @override
  void didUpdateWidget(covariant RequestBuilderPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.requestId != widget.requestId) {
      _viewModel.load(widget.requestId);
      locator<ShellViewModel>()
        ..unregisterSender(oldWidget.requestId, _viewModel.send)
        ..unregisterBodySearch(oldWidget.requestId, _responseFind.open)
        ..unregisterTabAction(oldWidget.requestId, TabAction.focusUrl, _urlFocus.requestFocus)
        ..unregisterTabAction(oldWidget.requestId, TabAction.saveResponseExample, _responseFind.saveExample)
        ..registerSender(widget.requestId, _viewModel.send)
        ..registerBodySearch(widget.requestId, _responseFind.open)
        ..registerTabAction(widget.requestId, TabAction.focusUrl, _urlFocus.requestFocus)
        ..registerTabAction(widget.requestId, TabAction.saveResponseExample, _responseFind.saveExample);
    }
  }

  /// The production lock: asks before a data-changing request goes out while a production environment is active.
  Future<bool> _confirmSend(ApiRequestEntity request) async {
    if (!locator.isRegistered<ProductionGuard>()) return true;
    final guard = locator<ProductionGuard>();
    final warning = await guard.checkRequest(request);
    if (warning == null || !mounted) return true;
    return confirmProductionSend(context, warning, onSilence: () => guard.silenceForSession(warning.environmentName));
  }

  void _bindVariableScope() {
    final request = _viewModel.request;
    if (request != null) {
      // Variables, headers, auth and tests are inherited from the request's folders and collection, so both bind to
      // the folder it is in now: a request moved to another folder follows it.
      _variableScope.bindCollection(request.collectionId, folderId: request.folderId);
      _inherited.bind(request.collectionId, folderId: request.folderId);
    }
    // A script that just ran may have saved variables. The repositories' own
    // change streams say so too; this just makes the editors not wait for them.
    final scripts = _viewModel.lastScriptResult;
    if (!identical(scripts, _seenScriptResult)) {
      _seenScriptResult = scripts;
      if (scripts != null) _variableScope.refresh();
    }
  }

  @override
  void dispose() {
    locator<ShellViewModel>()
      ..unregisterSender(widget.requestId, _viewModel.send)
      ..unregisterBodySearch(widget.requestId, _responseFind.open)
      ..unregisterTabAction(widget.requestId, TabAction.focusUrl, _urlFocus.requestFocus)
      ..unregisterTabAction(widget.requestId, TabAction.saveResponseExample, _responseFind.saveExample);
    _urlFocus.dispose();
    _viewModel.removeListener(_bindVariableScope);
    _viewModel.dispose();
    _variableScope.dispose();
    _inherited.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<RequestBuilderViewModel>.value(value: _viewModel),
        ChangeNotifierProvider<VariableScope>.value(value: _variableScope),
        ChangeNotifierProvider<InheritedDefaultsViewModel>.value(value: _inherited),
        Provider<ResponseFindController>.value(value: _responseFind),
      ],
      child: Consumer<RequestBuilderViewModel>(
        builder: (context, vm, _) {
          if (vm.isLoading || vm.request == null) {
            return const Center(child: CircularProgressIndicator());
          }
          return _RequestBuilderBody(vm: vm, urlFocus: _urlFocus);
        },
      ),
    );
  }
}

/// Below this width the response goes under the request whatever the saved
/// preference says: two columns that narrow squeeze both editors unusably.
const _sideBySideMinWidth = 920.0;

/// Below this width request and response get one screen each (a segmented
/// switch) instead of two stacked panes that would each be a sliver.
const _phoneMaxWidth = 600.0;

class _RequestBuilderBody extends StatelessWidget {
  final RequestBuilderViewModel vm;
  final FocusNode urlFocus;
  const _RequestBuilderBody({required this.vm, required this.urlFocus});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final canSplitSideways = constraints.maxWidth >= _sideBySideMinWidth;
          final phone = constraints.maxWidth < _phoneMaxWidth;
          return Column(
            children: [
              _UrlBar(vm: vm, canChooseLayout: canSplitSideways, compact: phone, focusNode: urlFocus),
              const SizedBox(height: 12),
              Expanded(
                child: phone ? _PhoneSplit(vm: vm) : _SplitArea(vm: vm, canSplitSideways: canSplitSideways),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Request editor and response viewer as two floating panels with a drag
/// handle between them. Side by side or stacked per [LayoutPrefs].
class _SplitArea extends StatelessWidget {
  final RequestBuilderViewModel vm;
  final bool canSplitSideways;
  const _SplitArea({required this.vm, required this.canSplitSideways});

  @override
  Widget build(BuildContext context) {
    final prefs = context.watch<LayoutPrefs>();
    final sideways = canSplitSideways && prefs.responseLayout == ResponseLayout.right;
    return ResizableSplit(
      axis: sideways ? Axis.horizontal : Axis.vertical,
      fraction: prefs.requestFraction,
      minFirst: sideways ? 340 : 190,
      minSecond: sideways ? 320 : 190,
      onFractionChanged: prefs.setRequestFraction,
      onDragEnd: prefs.commit,
      onReset: prefs.resetRequestFraction,
      first: _Panel(child: _RequestPane(vm: vm)),
      second: _Panel(child: _ResponsePane(vm: vm)),
    );
  }
}

/// Phone layout: a Request/Response switch over one full-height panel. Both
/// panes stay mounted so the open editor tab and scroll positions survive a
/// switch, and a fresh response (or error) brings the Response pane forward.
class _PhoneSplit extends StatefulWidget {
  final RequestBuilderViewModel vm;
  const _PhoneSplit({required this.vm});

  @override
  State<_PhoneSplit> createState() => _PhoneSplitState();
}

class _PhoneSplitState extends State<_PhoneSplit> {
  bool _showResponse = false;
  Object? _lastResponse;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _lastResponse = widget.vm.response;
    _lastError = widget.vm.errorMessage;
    widget.vm.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.vm.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final vm = widget.vm;
    if (identical(vm.response, _lastResponse) && vm.errorMessage == _lastError) return;
    _lastResponse = vm.response;
    _lastError = vm.errorMessage;
    if ((vm.response != null || vm.errorMessage != null) && mounted) setState(() => _showResponse = true);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: const [
              ButtonSegment(value: false, label: Text('Request'), icon: Icon(Icons.edit_outlined, size: 16)),
              ButtonSegment(value: true, label: Text('Response'), icon: Icon(Icons.data_object, size: 16)),
            ],
            selected: {_showResponse},
            onSelectionChanged: (selection) => setState(() => _showResponse = selection.first),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: IndexedStack(
            index: _showResponse ? 1 : 0,
            children: [
              _Panel(child: _RequestPane(vm: widget.vm)),
              _Panel(child: _ResponsePane(vm: widget.vm)),
            ],
          ),
        ),
      ],
    );
  }
}

/// A rounded, bordered surface that lifts a pane off the backdrop.
class _Panel extends StatelessWidget {
  final Widget child;
  const _Panel({required this.child});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.border),
        boxShadow: [BoxShadow(color: colors.shadow, blurRadius: 14, offset: const Offset(0, 4))],
      ),
      child: ClipRRect(borderRadius: BorderRadius.circular(11), child: child),
    );
  }
}

/// Method + URL + Send as one rounded bar that lights up while the URL is focused.
class _UrlBar extends StatefulWidget {
  final RequestBuilderViewModel vm;
  final bool canChooseLayout;

  /// Phone width: Send drops its icon so the URL keeps usable room.
  final bool compact;
  final FocusNode? focusNode;
  const _UrlBar({required this.vm, required this.canChooseLayout, this.compact = false, this.focusNode});

  @override
  State<_UrlBar> createState() => _UrlBarState();
}

class _UrlBarState extends State<_UrlBar> {
  bool _focused = false;
  late int _seenUrlRevision = widget.vm.urlRevision;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final vm = widget.vm;
    final request = vm.request!;
    final layout = context.select<LayoutPrefs, ResponseLayout>((p) => p.responseLayout);
    if (vm.urlRevision != _seenUrlRevision) {
      _seenUrlRevision = vm.urlRevision;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('cURL command applied: method, URL, headers, body and auth were filled in')),
          );
        }
      });
    }
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.fromLTRB(6, 5, 6, 5),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _focused ? colors.mainAccent : colors.border, width: _focused ? 1.4 : 1),
        boxShadow: [
          BoxShadow(
            color: _focused ? colors.glow : colors.shadow,
            blurRadius: _focused ? 16 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          MethodDropdown(value: request.method, onChanged: vm.updateMethod),
          Container(width: 1, height: 22, margin: const EdgeInsets.symmetric(horizontal: 6), color: colors.border),
          Expanded(
            child: Focus(
              onFocusChange: (focused) => setState(() => _focused = focused),
              child: VariableTextFormField(
                key: ValueKey('url-${vm.urlRevision}'),
                focusNode: widget.focusNode,
                initialValue: request.url,
                style: context.textStyles.body.copyWith(fontSize: 14),
                decoration: const InputDecoration(
                  hintText: 'https://api.example.com/{{path}}',
                  isDense: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(horizontal: 6, vertical: 10),
                ),
                onChanged: vm.updateUrl,
                onFieldSubmitted: (_) => vm.send(),
              ),
            ),
          ),
          if (widget.canChooseLayout)
            IconButton(
              icon: Icon(
                layout == ResponseLayout.right ? Icons.view_agenda_outlined : Icons.vertical_split_outlined,
                size: 18,
              ),
              tooltip: layout == ResponseLayout.right ? 'Show response below' : 'Show response on the right',
              onPressed: context.read<LayoutPrefs>().toggleResponseLayout,
            ),
          IconButton(
            icon: const Icon(Icons.code, size: 18),
            tooltip: 'Generate code',
            onPressed: () => CodeSnippetDialog.show(context, vm),
          ),
          const SizedBox(width: 4),
          if (vm.isSending)
            OutlinedButton.icon(
              onPressed: vm.cancelSend,
              icon: const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
              label: const Text('Cancel'),
            )
          else
            GradientButton(
              label: vm.sendLabel,
              icon: widget.compact ? null : Icons.send_rounded,
              padding: EdgeInsets.symmetric(horizontal: widget.compact ? 14 : 20, vertical: 11),
              onPressed: vm.send,
            ),
        ],
      ),
    );
  }
}

class _RequestPane extends StatelessWidget {
  final RequestBuilderViewModel vm;
  const _RequestPane({required this.vm});

  @override
  Widget build(BuildContext context) {
    final request = vm.request!;
    return DefaultTabController(
      length: 8,
      child: Column(
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                Tab(text: 'Params'),
                Tab(text: 'Headers'),
                Tab(text: 'Body'),
                Tab(text: 'Auth'),
                Tab(text: 'Tests'),
                Tab(text: 'Flow'),
                Tab(text: 'Settings'),
                Tab(text: 'Docs'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _scrollable(KeyValueEditor(items: request.queryParams, onChanged: vm.updateQueryParams)),
                _scrollable(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // What the collection and its folders pass down, with "override" and "turn off" for this request.
                      RequestInheritedHeaders(requestHeaders: request.headers, onChanged: vm.updateHeaders),
                      KeyValueEditor(items: request.headers, onChanged: vm.updateHeaders),
                    ],
                  ),
                ),
                _padded(BodyEditor(body: request.body, onChanged: vm.updateBody)),
                _scrollable(
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      RequestInheritedAuth(auth: request.auth, onOverride: vm.updateAuth),
                      InheritedOAuth2Status(requestAuth: request.auth),
                      AuthEditor(
                        auth: request.auth,
                        collectionId: request.collectionId,
                        folderId: request.folderId,
                        previewRequest: request,
                        onChanged: vm.updateAuth,
                      ),
                    ],
                  ),
                ),
                _scrollable(RequestTestsTab(requestId: request.id)),
                _scrollable(
                  RequestFlowTab(
                    requestId: request.id,
                    method: request.method,
                    request: request,
                    response: vm.response,
                  ),
                ),
                _scrollable(RequestSettingsTab(requestId: request.id)),
                _scrollable(RequestDocsTab(requestId: request.id)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _padded(Widget child) => Padding(padding: const EdgeInsets.all(12), child: child);

  Widget _scrollable(Widget child) => SingleChildScrollView(padding: const EdgeInsets.all(12), child: child);
}

class _ResponsePane extends StatelessWidget {
  final RequestBuilderViewModel vm;
  const _ResponsePane({required this.vm});

  @override
  Widget build(BuildContext context) {
    final request = vm.request!;
    final colors = context.colors;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // A thin bar while the request is in flight; the panel keeps its height
        // either way so the content below does not jump when it appears.
        SizedBox(
          height: 2,
          child: vm.isSending ? LinearProgressIndicator(minHeight: 2, backgroundColor: colors.borderSubtle) : null,
        ),
        if (vm.errorMessage != null)
          Container(
            color: colors.statusError.withValues(alpha: 0.1),
            child: vm.errorDetail == null
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(vm.errorMessage!, style: TextStyle(color: colors.statusError)),
                  )
                : ExpansionTile(
                    tilePadding: const EdgeInsets.symmetric(horizontal: 12),
                    title: Text(vm.errorMessage!, style: TextStyle(color: colors.statusError)),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: Text(vm.errorDetail!, style: TextStyle(color: colors.statusError)),
                        ),
                      ),
                    ],
                  ),
          ),
        if (vm.errorMessage != null && vm.errorHelp != null) CorsErrorHelp(help: vm.errorHelp!),
        if (vm.response != null) AuthNotesBanner(notes: vm.response!.authNotes),
        if (vm.response != null) OdooErrorBanner(response: vm.response!, request: request),
        if (vm.response != null) AuthDoctorBanner(response: vm.response!, request: request),
        if (vm.isSending && vm.flowStatus != null) _FlowStatusLine(text: vm.flowStatus!),
        if (vm.lastFlow != null) FlowReportStrip(report: vm.lastFlow!),
        if (vm.lastScriptResult != null) ScriptResultsView(result: vm.lastScriptResult!),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ResponseViewer(
              response: vm.response,
              requestId: request.id,
              requestName: request.name,
              findController: context.read<ResponseFindController>(),
            ),
          ),
        ),
      ],
    );
  }
}

/// What the flow around a send in flight is doing right now (`attempt 2/3 after 1.2 s`, `poll 4/30`, `page 3`),
/// under the progress bar. Only there while sending.
class _FlowStatusLine extends StatelessWidget {
  final String text;
  const _FlowStatusLine({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 2),
      child: Text(text, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
    );
  }
}
