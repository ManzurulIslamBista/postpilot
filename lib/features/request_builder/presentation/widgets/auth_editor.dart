import 'variables/variable_text_form_field.dart';
import '../../../../core/widgets/busy_label.dart';
import '../../../../core/theme/app_text_styles.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/di/injector.dart';
import '../../../../core/enums/auth_type.dart';
import '../../../../core/enums/body_type.dart';
import '../../../../core/enums/http_method.dart';
import '../../../../core/theme/context_theme_extensions.dart';
import '../../../../core/utils/variable_resolver.dart';
import '../../../auth_renewal/domain/services/token_status.dart';
import '../../../auth_renewal/presentation/view_models/relogin_section_view_model.dart';
import '../../../auth_renewal/presentation/widgets/relogin_section.dart';
import '../../domain/entities/api_request_entity.dart';
import '../../domain/entities/request_auth.dart';
import '../../domain/entities/request_body.dart';
import '../../domain/services/hmac_presets.dart';
import '../../domain/services/oauth2_token_service.dart';
import '../../domain/services/request_spec_builder.dart';
import '../view_models/request_oauth2_view_model.dart';
import '../view_models/variable_scope.dart';

class AuthEditor extends StatelessWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onChanged;

  /// False when editing a collection's own auth, which has no parent to inherit from.
  final bool allowInherit;

  /// Scopes `{{variable}}` resolution for OAuth 2.0 token requests to this
  /// collection's variables (plus environment and globals).
  final int? collectionId;

  /// The folder the auth belongs to (a folder's own auth, or the folder of the request): its variables,
  /// and those of the folders above it, resolve in OAuth 2.0 token requests too.
  final int? folderId;

  /// Adds the "Re-login on 401/403" section: for the auth of a collection or a folder, whose requests it
  /// applies to. Needs a [collectionId]; not shown while the auth only inherits, which holds no settings.
  final bool showRelogin;

  /// The request this auth belongs to, so that an HMAC auth can show the signature it would put on that
  /// request's body. Null for the auth of a collection or a folder: the preview then signs a sample body typed in.
  final ApiRequestEntity? previewRequest;

  const AuthEditor({
    super.key,
    required this.auth,
    required this.onChanged,
    this.allowInherit = true,
    this.collectionId,
    this.folderId,
    this.showRelogin = false,
    this.previewRequest,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<AuthType>(
          value: auth.type,
          onChanged: (t) => t == null ? null : onChanged(auth.copyWith(type: t)),
          items: [
            for (final t in AuthType.values)
              if (allowInherit || t != AuthType.inherit) DropdownMenuItem(value: t, child: Text(t.label)),
          ],
        ),
        const SizedBox(height: 12),
        // Keyed per type so the unkeyed TextFormFields below never inherit
        // another type's field state when the dropdown changes.
        KeyedSubtree(
          key: ValueKey(auth.type),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: switch (auth.type) {
              AuthType.apiKey => _apiKeyFields(),
              AuthType.bearer => _bearerFields(),
              AuthType.basic || AuthType.digest => _basicFields(),
              AuthType.awsSignatureV4 => _awsFields(),
              AuthType.jwtBearer => _jwtFields(),
              AuthType.hmac => [_HmacFields(auth: auth, onChanged: onChanged, previewRequest: previewRequest)],
              AuthType.oauth2 => [
                ChangeNotifierProvider<RequestOAuth2ViewModel>(
                  create: (_) => locator<RequestOAuth2ViewModel>(),
                  child: _OAuth2Fields(auth: auth, onChanged: onChanged, collectionId: collectionId, folderId: folderId),
                ),
              ],
              AuthType.none || AuthType.inherit => const [],
            },
          ),
        ),
        if (showRelogin &&
            collectionId != null &&
            auth.type != AuthType.inherit &&
            locator.isRegistered<ReloginSectionViewModel>())
          ChangeNotifierProvider<ReloginSectionViewModel>(
            create: (_) => locator<ReloginSectionViewModel>()..load(collectionId!),
            child: ReloginSection(auth: auth, onChanged: onChanged, collectionId: collectionId!),
          ),
      ],
    );
  }

  List<Widget> _apiKeyFields() => [
    VariableTextFormField(
      initialValue: auth.apiKeyName,
      decoration: const InputDecoration(labelText: 'Key'),
      onChanged: (v) => onChanged(auth.copyWith(apiKeyName: v)),
    ),
    VariableTextFormField(
      initialValue: auth.apiKeyValue,
      decoration: const InputDecoration(labelText: 'Value'),
      onChanged: (v) => onChanged(auth.copyWith(apiKeyValue: v)),
    ),
    DropdownButton<ApiKeyLocation>(
      value: auth.apiKeyLocation,
      onChanged: (l) => l == null ? null : onChanged(auth.copyWith(apiKeyLocation: l)),
      items: const [
        DropdownMenuItem(value: ApiKeyLocation.header, child: Text('Header')),
        DropdownMenuItem(value: ApiKeyLocation.query, child: Text('Query Params')),
      ],
    ),
  ];

  List<Widget> _bearerFields() => [
    VariableTextFormField(
      initialValue: auth.bearerToken,
      decoration: const InputDecoration(labelText: 'Token'),
      onChanged: (v) => onChanged(auth.copyWith(bearerToken: v)),
    ),
  ];

  List<Widget> _basicFields() => [
    VariableTextFormField(
      initialValue: auth.basicUsername,
      decoration: const InputDecoration(labelText: 'Username'),
      onChanged: (v) => onChanged(auth.copyWith(basicUsername: v)),
    ),
    VariableTextFormField(
      initialValue: auth.basicPassword,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Password'),
      onChanged: (v) => onChanged(auth.copyWith(basicPassword: v)),
    ),
  ];

  List<Widget> _awsFields() => [
    VariableTextFormField(
      initialValue: auth.awsAccessKey,
      decoration: const InputDecoration(labelText: 'Access Key'),
      onChanged: (v) => onChanged(auth.copyWith(awsAccessKey: v)),
    ),
    VariableTextFormField(
      initialValue: auth.awsSecretKey,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Secret Key'),
      onChanged: (v) => onChanged(auth.copyWith(awsSecretKey: v)),
    ),
    VariableTextFormField(
      initialValue: auth.awsSessionToken,
      decoration: const InputDecoration(labelText: 'Session Token (optional)'),
      onChanged: (v) => onChanged(auth.copyWith(awsSessionToken: v)),
    ),
    Row(
      children: [
        Expanded(
          child: VariableTextFormField(
            initialValue: auth.awsRegion,
            decoration: const InputDecoration(labelText: 'AWS Region'),
            onChanged: (v) => onChanged(auth.copyWith(awsRegion: v)),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: VariableTextFormField(
            initialValue: auth.awsService,
            decoration: const InputDecoration(labelText: 'Service Name'),
            onChanged: (v) => onChanged(auth.copyWith(awsService: v)),
          ),
        ),
      ],
    ),
  ];

  List<Widget> _jwtFields() => [
    DropdownButton<JwtAlgorithm>(
      value: auth.jwtAlgorithm,
      onChanged: (a) => a == null ? null : onChanged(auth.copyWith(jwtAlgorithm: a)),
      items: [for (final a in JwtAlgorithm.values) DropdownMenuItem(value: a, child: Text(a.label))],
    ),
    VariableTextFormField(
      initialValue: auth.jwtSecret,
      obscureText: true,
      decoration: const InputDecoration(labelText: 'Secret'),
      onChanged: (v) => onChanged(auth.copyWith(jwtSecret: v)),
    ),
    VariableTextFormField(
      initialValue: auth.jwtPayload,
      maxLines: 4,
      style: const TextStyle(fontFamily: AppFonts.monoFamily, fontFamilyFallback: AppFonts.monoFallback, fontSize: 13),
      decoration: const InputDecoration(labelText: 'Payload (JSON)'),
      onChanged: (v) => onChanged(auth.copyWith(jwtPayload: v)),
    ),
    VariableTextFormField(
      initialValue: auth.jwtHeaderPrefix,
      decoration: const InputDecoration(labelText: 'Header Prefix'),
      onChanged: (v) => onChanged(auth.copyWith(jwtHeaderPrefix: v)),
    ),
  ];
}

/// The fields of an HMAC signature, and a live preview of the signature they give. Stateful for two things: a
/// preset that fills the fields in has to make their text fields start again from the new values (typing in one
/// must not, or it would lose its focus), and the sample body of the preview is typed in here.
class _HmacFields extends StatefulWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onChanged;
  final ApiRequestEntity? previewRequest;

  const _HmacFields({required this.auth, required this.onChanged, required this.previewRequest});

  @override
  State<_HmacFields> createState() => _HmacFieldsState();
}

class _HmacFieldsState extends State<_HmacFields> {
  int _generation = 0;
  String _sampleBody = '';

  /// Every edit goes through here: one that takes the fields away from the preset they were started from makes
  /// the auth a generic one.
  void _edit(RequestAuth next) => widget.onChanged(HmacPresets.settled(next));

  void _applyPreset(HmacPreset preset) {
    setState(() => _generation++);
    widget.onChanged(HmacPresets.apply(widget.auth, preset));
  }

  Widget _field(
    String name,
    String label,
    String value,
    RequestAuth Function(RequestAuth auth, String text) change, {
    bool obscure = false,
    bool mono = false,
    String? helper,
  }) => VariableTextFormField(
    key: ValueKey('hmac-$name-$_generation'),
    initialValue: value,
    obscureText: obscure,
    style: mono ? context.textStyles.mono : null,
    decoration: InputDecoration(labelText: label, helperText: helper, helperMaxLines: 3),
    onChanged: (text) => _edit(change(widget.auth, text)),
  );

  /// A dropdown that looks like the text fields around it (label on top) and takes the width it is given, so a long
  /// choice is cut instead of overflowing a narrow pane.
  Widget _picker<T>(String label, T value, List<T> values, String Function(T) text, ValueChanged<T> onPicked) =>
      InputDecorator(
        isEmpty: false,
        decoration: InputDecoration(labelText: label),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<T>(
            value: value,
            isExpanded: true,
            isDense: true,
            onChanged: (picked) => picked == null ? null : onPicked(picked),
            items: [
              for (final v in values)
                DropdownMenuItem(value: v, child: Text(text(v), maxLines: 1, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _picker<HmacPreset>(
          'Provider preset',
          auth.hmacPreset,
          HmacPreset.values,
          (p) => p.label,
          _applyPreset,
        ),
        const SizedBox(height: 8),
        _field('secret', 'Secret', auth.hmacSecret, (a, v) => a.copyWith(hmacSecret: v), obscure: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _picker<HmacAlgorithm>(
                'Algorithm',
                auth.hmacAlgorithm,
                HmacAlgorithm.values,
                (a) => a.label,
                (a) => _edit(widget.auth.copyWith(hmacAlgorithm: a)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _picker<HmacEncoding>(
                'Encoding',
                auth.hmacEncoding,
                HmacEncoding.values,
                (e) => e.label,
                (e) => _edit(widget.auth.copyWith(hmacEncoding: e)),
              ),
            ),
          ],
        ),
        _field(
          'payload',
          'Signed payload',
          auth.hmacPayloadTemplate,
          (a, v) => a.copyWith(hmacPayloadTemplate: v),
          mono: true,
          helper: 'Placeholders: {body} {timestamp} {method} {path} {query} {url}',
        ),
        _field(
          'header-name',
          'Signature header',
          auth.hmacHeaderName,
          (a, v) => a.copyWith(hmacHeaderName: v),
        ),
        _field(
          'header-value',
          'Header value',
          auth.hmacHeaderTemplate,
          (a, v) => a.copyWith(hmacHeaderTemplate: v),
          mono: true,
          helper: 'Placeholders: {signature} {timestamp}',
        ),
        _field(
          'timestamp-header',
          'Timestamp header (optional)',
          auth.hmacTimestampHeader,
          (a, v) => a.copyWith(hmacTimestampHeader: v),
        ),
        const SizedBox(height: 8),
        _picker<HmacTimestampSource>(
          'Timestamp',
          auth.hmacTimestampSource,
          HmacTimestampSource.values,
          (s) => s.label,
          (s) => _edit(widget.auth.copyWith(hmacTimestampSource: s)),
        ),
        if (auth.hmacTimestampSource == HmacTimestampSource.fixed)
          _field(
            'timestamp-value',
            'Fixed timestamp',
            auth.hmacTimestampValue,
            (a, v) => a.copyWith(hmacTimestampValue: v),
            helper: 'The same value on every send, so a signature can be repeated and compared.',
          ),
        const Divider(),
        if (widget.previewRequest == null)
          TextFormField(
            key: const ValueKey('hmac-sample-body'),
            initialValue: _sampleBody,
            minLines: 1,
            maxLines: 4,
            style: context.textStyles.mono,
            decoration: const InputDecoration(
              labelText: 'Sample body for the preview',
              helperText: 'Each request signs its own body; this is only to see a signature here.',
              helperMaxLines: 2,
            ),
            onChanged: (text) => setState(() => _sampleBody = text),
          ),
        _HmacPreview(auth: auth, previewRequest: widget.previewRequest, sampleBody: _sampleBody),
      ],
    );
  }
}

/// What the HMAC auth would put on the request: the headers with the signature, and the exact text that was
/// signed. Read-only and selectable, to be compared with what the receiver computes.
class _HmacPreview extends StatelessWidget {
  final RequestAuth auth;
  final ApiRequestEntity? previewRequest;
  final String sampleBody;

  const _HmacPreview({required this.auth, required this.previewRequest, required this.sampleBody});

  static const _maxPayloadChars = 600;

  ApiRequestEntity _request() =>
      previewRequest?.copyWith(auth: auth) ??
      ApiRequestEntity(
        id: 0,
        collectionId: 0,
        folderId: null,
        name: 'Sample',
        method: HttpMethod.post,
        url: 'https://example.com/webhook',
        headers: const [],
        queryParams: const [],
        body: RequestBody(type: BodyType.raw, rawContentType: RawContentType.text, rawText: sampleBody),
        auth: auth,
      );

  @override
  Widget build(BuildContext context) {
    final scope = context.watch<VariableScope?>();
    final resolver = scope?.resolver ?? VariableResolver(const {});
    final request = _request();
    const builder = RequestSpecBuilder();
    final preview = builder.previewHmac(request, resolver);
    final signed = preview.signed;
    final missing = scope == null || !scope.isLoaded
        ? const <String>[]
        : [
            for (final v in builder.undefinedVariables(request, resolver))
              if (v.inBody || v.places.any((place) => place.startsWith('the HMAC'))) v.token,
          ];
    final caption = context.textStyles.caption;
    final quiet = caption.copyWith(color: context.colors.secondaryText);

    return Column(
      key: const ValueKey('hmac-signature-preview'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Signature preview', style: caption.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 2),
        Text(
          previewRequest == null
              ? 'Computed from the sample body above.'
              : "Computed from this request's URL and body, with the variables in use now.",
          style: quiet,
        ),
        const SizedBox(height: 8),
        if (preview.problem != null)
          Text(preview.problem!, style: caption.copyWith(color: context.colors.statusError))
        else if (signed != null) ...[
          for (final header in signed.headers.entries) ...[
            Text(header.key, style: quiet),
            SelectableText(header.value, style: context.textStyles.mono),
            const SizedBox(height: 6),
          ],
          if (signed.headers.isEmpty)
            Text(
              'No header name is set, so no signature would be sent.',
              style: caption.copyWith(color: context.colors.statusWarning),
            ),
          Text('Signature (${auth.hmacEncoding.label}), computed over ${signed.payload.length} bytes', style: quiet),
          SelectableText(signed.signature, style: context.textStyles.mono),
          const SizedBox(height: 6),
          Text('Text that was signed', style: quiet),
          SelectableText(_clip(signed.payloadText), style: context.textStyles.mono),
          if (signed.timestamp.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              auth.hmacTimestampSource == HmacTimestampSource.fixed
                  ? 'Timestamp ${signed.timestamp} (fixed).'
                  : 'Timestamp ${signed.timestamp} is the current time: the signature changes on every send.',
              style: quiet,
            ),
          ],
          if (auth.hmacSecret.isEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'The secret is empty, so this is the signature of an empty key.',
              style: caption.copyWith(color: context.colors.statusWarning),
            ),
          ],
        ],
        if (missing.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            'Not defined: ${missing.join(', ')}. The preview takes them as written.',
            style: caption.copyWith(color: context.colors.statusWarning),
          ),
        ],
      ],
    );
  }

  static String _clip(String text) =>
      text.length <= _maxPayloadChars ? text : '${text.substring(0, _maxPayloadChars)}…';
}

class _OAuth2Fields extends StatefulWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onChanged;
  final int? collectionId;
  final int? folderId;

  const _OAuth2Fields({required this.auth, required this.onChanged, required this.collectionId, this.folderId});

  @override
  State<_OAuth2Fields> createState() => _OAuth2FieldsState();
}

class _OAuth2FieldsState extends State<_OAuth2Fields> {
  /// A token response arrives after a network round-trip, during which the
  /// user may have kept editing. It is applied to the auth as it is now (the
  /// state always sees the latest [widget]), not as it was when the button was
  /// pressed, so those edits survive.
  void _applyToken(OAuth2Token token) => widget.onChanged(
    widget.auth.withOAuth2Token(token.accessToken, token.expiresAt, refreshToken: token.refreshToken ?? ''),
  );

  @override
  Widget build(BuildContext context) {
    final auth = widget.auth;
    final onChanged = widget.onChanged;
    final collectionId = widget.collectionId;
    final vm = context.watch<RequestOAuth2ViewModel>()..folderId = widget.folderId;
    final grant = auth.oauth2GrantType;
    final isPkce = grant == OAuth2GrantType.authorizationCodePkce;
    final status = vm.statusOf(auth);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButton<OAuth2GrantType>(
          value: grant,
          onChanged: (g) => g == null ? null : onChanged(auth.copyWith(oauth2GrantType: g)),
          items: [for (final g in OAuth2GrantType.values) DropdownMenuItem(value: g, child: Text(g.label))],
        ),
        if (isPkce)
          _field(
            'oauth2AuthorizationUrl',
            'Authorization URL',
            auth.oauth2AuthorizationUrl,
            (v) => onChanged(auth.copyWith(oauth2AuthorizationUrl: v)),
          ),
        _field(
          'oauth2AccessTokenUrl',
          'Access Token URL',
          auth.oauth2AccessTokenUrl,
          (v) => onChanged(auth.copyWith(oauth2AccessTokenUrl: v)),
        ),
        if (isPkce)
          _field(
            'oauth2RedirectUri',
            'Redirect URI',
            auth.oauth2RedirectUri,
            (v) => onChanged(auth.copyWith(oauth2RedirectUri: v)),
          ),
        _field('oauth2ClientId', 'Client ID', auth.oauth2ClientId, (v) => onChanged(auth.copyWith(oauth2ClientId: v))),
        _field(
          'oauth2ClientSecret',
          isPkce ? 'Client Secret (optional for public clients)' : 'Client Secret',
          auth.oauth2ClientSecret,
          (v) => onChanged(auth.copyWith(oauth2ClientSecret: v)),
          obscure: true,
        ),
        if (grant == OAuth2GrantType.password) ...[
          _field('oauth2Username', 'Username', auth.oauth2Username, (v) => onChanged(auth.copyWith(oauth2Username: v))),
          _field(
            'oauth2Password',
            'Password',
            auth.oauth2Password,
            (v) => onChanged(auth.copyWith(oauth2Password: v)),
            obscure: true,
          ),
        ],
        _field(
          'oauth2Scope',
          'Scope (space-separated)',
          auth.oauth2Scope,
          (v) => onChanged(auth.copyWith(oauth2Scope: v)),
        ),
        _field(
          'oauth2Audience',
          'Audience (optional)',
          auth.oauth2Audience,
          (v) => onChanged(auth.copyWith(oauth2Audience: v)),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Text('Client authentication', style: context.textStyles.caption),
            const SizedBox(width: 12),
            DropdownButton<OAuth2ClientAuthentication>(
              value: auth.oauth2ClientAuthentication,
              onChanged: (c) => c == null ? null : onChanged(auth.copyWith(oauth2ClientAuthentication: c)),
              items: [
                for (final c in OAuth2ClientAuthentication.values) DropdownMenuItem(value: c, child: Text(c.label)),
              ],
            ),
          ],
        ),
        const Divider(),
        _TokenStatus(
          auth: auth,
          onChanged: onChanged,
          onRefresh: vm.isFetching ? null : () => vm.refreshToken(auth, _applyToken, collectionId: collectionId),
          onClear: () {
            vm.forgetRenewedTokens();
            onChanged(auth.clearOAuth2Token());
          },
          status: status,
        ),
        SwitchListTile(
          key: const ValueKey('oauth2-auto-renew'),
          contentPadding: EdgeInsets.zero,
          dense: true,
          title: const Text('Auto-renew'),
          subtitle: Text(status.renewalLine, style: context.textStyles.caption.copyWith(color: context.colors.secondaryText)),
          value: auth.oauth2AutoRenew,
          onChanged: (on) => onChanged(auth.copyWith(oauth2AutoRenew: on)),
        ),
        if (vm.errorMessage != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              vm.errorMessage!,
              style: context.textStyles.caption.copyWith(color: context.colors.statusError),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton(
              onPressed: vm.isFetching
                  ? null
                  : () => isPkce
                        ? _openAuthorization(context, vm)
                        : vm.fetchToken(auth, _applyToken, collectionId: collectionId),
              child: BusyLabel(
                busy: vm.isFetching,
                icon: Icons.vpn_key_outlined,
                label: isPkce ? 'Get new access token (opens browser)' : 'Get new access token',
                busyLabel: 'Fetching token…',
              ),
            ),
            // The refresh token (or a one-POST grant) renews without a person; Authorization Code without one cannot.
            if (status.selfRenewing)
              OutlinedButton(
                key: const ValueKey('oauth2-renew-now'),
                onPressed: vm.isFetching ? null : () => vm.renewNow(auth, _applyToken, collectionId: collectionId),
                child: BusyLabel(busy: vm.isFetching, icon: Icons.autorenew, label: 'Renew now', busyLabel: 'Renewing…'),
              ),
          ],
        ),
        if (isPkce && vm.authorizationUrl != null) ...[
          const SizedBox(height: 12),
          _AuthorizationCodeExchange(
            auth: auth,
            onToken: _applyToken,
            collectionId: collectionId,
            authorizationUrl: vm.authorizationUrl!,
          ),
        ],
      ],
    );
  }

  Future<void> _openAuthorization(BuildContext context, RequestOAuth2ViewModel vm) async {
    await vm.startAuthorizationCodeFlow(widget.auth, collectionId: widget.collectionId);
    final url = vm.authorizationUrl;
    if (url == null) return;
    final opened = await launchUrl(url);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Couldn't open the browser — copy the URL below instead")));
    }
  }

  Widget _field(String key, String label, String value, ValueChanged<String> onChanged, {bool obscure = false}) =>
      VariableTextFormField(
        key: ValueKey(key),
        initialValue: value,
        obscureText: obscure,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      );
}

class _TokenStatus extends StatelessWidget {
  final RequestAuth auth;
  final ValueChanged<RequestAuth> onChanged;

  /// Null while a token request is already running.
  final VoidCallback? onRefresh;
  final VoidCallback onClear;
  final TokenStatus status;

  const _TokenStatus({
    required this.auth,
    required this.onChanged,
    required this.onRefresh,
    required this.onClear,
    required this.status,
  });

  @override
  Widget build(BuildContext context) {
    final token = auth.oauth2AccessToken;
    final expired = status.health == TokenHealth.expired;
    final statusColor = switch (status.health) {
      TokenHealth.missing => context.colors.secondaryText,
      TokenHealth.expired => context.colors.statusError,
      TokenHealth.expiring => context.colors.statusWarning,
      TokenHealth.valid || TokenHealth.noExpiry => context.colors.statusSuccess,
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              auth.hasOAuth2Token && !expired ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: statusColor,
            ),
            const SizedBox(width: 6),
            Text(status.headline, style: context.textStyles.caption.copyWith(color: statusColor)),
            const Spacer(),
            if (auth.hasOAuth2Token) ...[
              if (auth.hasOAuth2RefreshToken)
                IconButton(icon: const Icon(Icons.refresh, size: 16), tooltip: 'Refresh token', onPressed: onRefresh),
              IconButton(
                icon: const Icon(Icons.copy, size: 16),
                tooltip: 'Copy token',
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: token));
                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Token copied')));
                },
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 16),
                tooltip: 'Clear token',
                onPressed: onClear,
              ),
            ],
          ],
        ),
        if (auth.hasOAuth2Token)
          SelectableText(_preview(token), style: context.textStyles.mono.copyWith(color: context.colors.secondaryText)),
      ],
    );
  }

  static String _preview(String token) =>
      token.length <= 32 ? token : '${token.substring(0, 20)}…${token.substring(token.length - 8)}';
}

/// The half of the PKCE flow that needs local state: the authorization URL
/// the user was sent to, and the code they paste back.
class _AuthorizationCodeExchange extends StatefulWidget {
  final RequestAuth auth;
  final ValueChanged<OAuth2Token> onToken;
  final int? collectionId;
  final Uri authorizationUrl;

  const _AuthorizationCodeExchange({
    required this.auth,
    required this.onToken,
    required this.collectionId,
    required this.authorizationUrl,
  });

  @override
  State<_AuthorizationCodeExchange> createState() => _AuthorizationCodeExchangeState();
}

class _AuthorizationCodeExchangeState extends State<_AuthorizationCodeExchange> {
  final _codeController = TextEditingController();

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<RequestOAuth2ViewModel>();
    final url = widget.authorizationUrl.toString();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '1. Sign in at the URL below, then copy the redirect URL (or just its `code`).',
          style: context.textStyles.caption,
        ),
        Row(
          children: [
            Expanded(child: SelectableText(url, maxLines: 2, style: context.textStyles.mono)),
            IconButton(
              icon: const Icon(Icons.copy, size: 16),
              tooltip: 'Copy URL',
              onPressed: () {
                Clipboard.setData(ClipboardData(text: url));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL copied')));
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('2. Paste it here and exchange it for a token.', style: context.textStyles.caption),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _codeController,
                decoration: const InputDecoration(labelText: 'Authorization code or redirect URL', isDense: true),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.tonal(
              onPressed: vm.isFetching
                  ? null
                  : () => vm.exchangeAuthorizationCode(
                      widget.auth,
                      _codeController.text,
                      widget.onToken,
                      collectionId: widget.collectionId,
                    ),
              child: BusyLabel(busy: vm.isFetching, label: 'Exchange code', busyLabel: 'Exchanging…'),
            ),
          ],
        ),
      ],
    );
  }
}
