/// The kinds of Odoo failure that have a concrete cause and a concrete next step.
enum OdooErrorKind {
  /// `AccessError`: the model's access rights (ir.model.access) do not let this user do that.
  accessModel,

  /// `AccessError` from a record rule (ir.rule): the user may use the model but not these records.
  accessRule,

  /// A required field has no value.
  missingRequired,

  /// A value that has to be unique is already used.
  unique,

  /// A record cannot be deleted because others point at it, or a many2one points at a record that is not there.
  foreignKey,

  /// `MissingError`: a record id that no longer exists.
  missingRecord,

  /// A name that is not a field of the model.
  invalidField,

  /// A selection value or a date/number text the field cannot read.
  badValue,

  /// `ValidationError` from a constraint of the model, `UserError` from a business rule.
  validation,
}

/// What an Odoo error says, taken apart: which model, field and operation, which groups the message names, and what
/// to do about it. Read from the message alone; the live part of the doctor adds what only the server knows (see
/// `OdooErrorDoctor`).
final class OdooDiagnosis {
  final OdooErrorKind kind;

  /// The technical model name (`res.partner`) and its label (`Contact`), when the message names them.
  final String? model;
  final String? modelLabel;

  /// The technical field name (`name`) and its label, when the message names them.
  final String? field;
  final String? fieldLabel;

  /// `read`, `write`, `create` or `unlink`.
  final String? operation;

  /// The groups the message says may do the operation.
  final List<String> groups;

  /// The user id the message names (older servers do), and the record ids it names.
  final int? userId;
  final List<int> recordIds;

  /// The value of a unique key the message quotes (`Key (login)=(admin)`).
  final String? value;

  /// What it means, in a sentence or two.
  final String explanation;

  /// What to do about it, one step each. Steps that only the live server can complete are added by the doctor.
  final List<String> steps;

  const OdooDiagnosis({
    required this.kind,
    this.model,
    this.modelLabel,
    this.field,
    this.fieldLabel,
    this.operation,
    this.groups = const [],
    this.userId,
    this.recordIds = const [],
    this.value,
    required this.explanation,
    this.steps = const [],
  });

  /// `read`, `write`... as the verb of a sentence about rights.
  String get operationWords => switch (operation) {
        'write' => 'modify',
        'create' => 'create',
        'unlink' => 'delete',
        _ => 'read',
      };

  /// The same as a noun for "rules that apply to ...".
  String get operationGerund => switch (operation) {
        'write' => 'modifying',
        'create' => 'creating',
        'unlink' => 'deleting',
        _ => 'reading',
      };
}

/// Reads an Odoo error message (`odoo.exceptions.AccessError`, a database constraint, `MissingError`...) into an
/// [OdooDiagnosis]. Null for a message it does not recognise, so the caller keeps its generic wording.
abstract final class OdooDiagnoser {
  static OdooDiagnosis? diagnose(String exception, String message) {
    final short = exception.split('.').last;
    final text = message.trim();
    if (text.isEmpty && short.isEmpty) return null;

    if (short == 'AccessError' || text.contains('not allowed to access') || text.contains('top-secret records') || text.contains('Due to security restrictions')) {
      return _access(text);
    }
    if (short == 'MissingError' || text.contains('Record does not exist or has been deleted')) return _missingRecord(text);

    final required = _required(text);
    if (required != null) return required;
    final unique = _unique(text);
    if (unique != null) return unique;
    final foreign = _foreignKey(text);
    if (foreign != null) return foreign;
    final invalid = _invalidField(text);
    if (invalid != null) return invalid;
    final bad = _badValue(text);
    if (bad != null) return bad;

    if (short == 'ValidationError') {
      return OdooDiagnosis(
        kind: OdooErrorKind.validation,
        explanation: 'A constraint of the model (a Python @api.constrains check or an SQL constraint) rejected the values: the data is well formed but not allowed.',
        steps: const ['Read the message: it names the rule and usually the field. Change those values and send again.'],
      );
    }
    if (short == 'UserError' || short == 'RedirectWarning') {
      return OdooDiagnosis(
        kind: OdooErrorKind.validation,
        explanation: 'A business rule refused the operation on purpose, usually because of the state of the record (confirmed, posted, locked) or a missing setting.',
        steps: const ['Read the message: it says what to change first (the state of the record, a configuration, a related document).'],
      );
    }
    return null;
  }

  // --- access -------------------------------------------------------------------------------------------------

  static final _modelAccess = RegExp(r"not allowed to (access|modify|create|delete|read|write|unlink)\b[^']*'([^']*)'\s*\(([\w.]+)\)");
  static final _documentModel = RegExp(r'\(([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)+)\)');
  static final _userOf = RegExp(r'User:\s*(\d+)');
  static final _operationOf = RegExp(r"Operation:\s*(\w+)|'(read|write|create|unlink)'\s+access|(?:to|not allowed to)\s+(access|modify|create|delete)");

  static String _operation(String? word) => switch (word) {
        'modify' || 'write' => 'write',
        'create' => 'create',
        'delete' || 'unlink' => 'unlink',
        _ => 'read',
      };

  static List<String> _groupsIn(String text) {
    final at = text.indexOf('following groups');
    final scope = at < 0 ? (text.contains('access level') ? text : '') : text.substring(at);
    return [
      for (final m in RegExp(r'^[ \t]*-[ \t]+(.+?)[ \t]*$', multiLine: true).allMatches(scope))
        if (!m[1]!.startsWith('(')) m[1]!,
    ];
  }

  static OdooDiagnosis _access(String text) {
    final byRule = text.contains('Due to security restrictions') || text.contains('top-secret records') || text.contains('Records:');
    final direct = _modelAccess.firstMatch(text);
    final label = direct?[2];
    final model = direct?[3] ?? _documentModel.firstMatch(text)?[1];
    final operation = _operation(direct?[1] ?? _operationOf.firstMatch(text)?.groups([1, 2, 3]).firstWhere((g) => g != null, orElse: () => null));
    final user = int.tryParse(_userOf.firstMatch(text)?[1] ?? '');
    final groups = _groupsIn(text);
    final target = model == null ? 'this model' : (label == null || label.isEmpty ? model : '$label ($model)');
    if (byRule) {
      return OdooDiagnosis(
        kind: OdooErrorKind.accessRule,
        model: model,
        modelLabel: label,
        operation: operation,
        userId: user,
        explanation: 'The user may use $target, but a record rule (ir.rule) hides these particular records from it: '
            'typically records of another company, another salesperson or another team.',
        steps: [
          'Check which companies the user is allowed to use, and whether the record belongs to one of them.',
          if (model != null) 'Look at the record rules of $model (Settings, Technical, Security, Record Rules, in developer mode).',
          'Send the request as a user who sees the record, or read the record with another user to confirm it exists.',
        ],
      );
    }
    final verb = switch (operation) { 'write' => 'modify', 'create' => 'create', 'unlink' => 'delete', _ => 'read' };
    return OdooDiagnosis(
      kind: OdooErrorKind.accessModel,
      model: model,
      modelLabel: label,
      operation: operation,
      groups: groups,
      userId: user,
      explanation: 'The access rights of $target (ir.model.access) do not let the user $verb its records. '
          'This comes from the user\'s groups, not from the data in the request.',
      steps: [
        if (groups.isNotEmpty)
          'Add the user to one of these groups (Settings, Users & Companies, Users): ${groups.join(', ')}.'
        else if (model != null)
          'Find the groups that may $verb $model in Settings, Technical, Security, Access Rights (developer mode), and add the user to one.',
        if (model != null) 'Check ir.model.access for $model: a line for one of the user\'s groups with the ${_permissionName(operation)} box ticked.',
      ],
    );
  }

  static String _permissionName(String operation) => switch (operation) {
        'write' => 'Write',
        'create' => 'Create',
        'unlink' => 'Delete',
        _ => 'Read',
      };

  // --- records and values -------------------------------------------------------------------------------------

  static OdooDiagnosis _missingRecord(String text) {
    final record = RegExp(r'Record:\s*([a-z][\w.]*)\(([\d,\s]*)\)').firstMatch(text);
    final ids = [
      for (final part in (record?[2] ?? '').split(','))
        if (int.tryParse(part.trim()) != null) int.parse(part.trim()),
    ];
    final model = record?[1] ?? _documentModel.firstMatch(text)?[1];
    final user = int.tryParse(_userOf.firstMatch(text)?[1] ?? '');
    return OdooDiagnosis(
      kind: OdooErrorKind.missingRecord,
      model: model,
      recordIds: ids,
      userId: user,
      explanation: '${ids.isEmpty ? 'A record' : (ids.length == 1 ? 'Record ${ids.single}' : 'Records ${ids.join(', ')}')}'
          '${model == null ? '' : ' of $model'} does not exist: it was deleted, or the id comes from another database.',
      steps: [
        'Search again for the current ids (search_read) instead of reusing an old one.',
        'An id typed from one database is wrong in the next one: use {{xmlid:module.name}} or {{ref:model:name}} in the body, which look the id up on every server.',
      ],
    );
  }

  static OdooDiagnosis? _required(String text) {
    final orm = RegExp(r"Missing required value for the field '([^']*)' \((\w+)\)").firstMatch(text);
    final older = RegExp(r'Model:\s*(.+?)\s*\(([\w.]+)\),\s*Field:\s*(.+?)\s*\((\w+)\)').firstMatch(text);
    final pg = RegExp(r'null value in column "(\w+)"(?: of relation "(\w+)")? violates not-null constraint').firstMatch(text);
    String? field;
    String? label;
    String? model;
    String? modelLabel;
    if (orm != null) {
      label = orm[1];
      field = orm[2];
    } else if (older != null && text.contains('mandatory field')) {
      modelLabel = older[1];
      model = older[2];
      label = older[3];
      field = older[4];
    } else if (pg != null) {
      field = pg[1];
    } else {
      return null;
    }
    return OdooDiagnosis(
      kind: OdooErrorKind.missingRequired,
      model: model,
      modelLabel: modelLabel,
      field: field,
      fieldLabel: label,
      explanation: 'The field ${label == null ? field : '$label ($field)'} of ${model ?? 'the model'} is required, but the request gives it no value '
          '(or the value was empty or false), and Odoo has no default for it.',
      steps: [
        'Add "$field" to the values you send (create: inside vals_list[0]; write: inside vals).',
        'The Payload tab of Odoo Studio marks every required field of a model, and the Check tab lists the ones a body forgets.',
      ],
    );
  }

  static OdooDiagnosis? _unique(String text) {
    final detail = RegExp(r'Key \(([^)]*)\)=\(([^)]*)\) already exists').firstMatch(text);
    final orm = RegExp(r"The values? for the fields? '([^']*)' already exists?").firstMatch(text);
    final pg = RegExp(r'duplicate key value violates unique constraint "([^"]*)"').firstMatch(text);
    if (detail == null && orm == null && pg == null && !text.contains('another record already exists') && !text.contains('must be unique')) return null;
    final fields = (detail?[1] ?? orm?[1] ?? '').split(',').map((f) => f.trim()).where((f) => f.isNotEmpty).toList();
    final field = fields.length == 1 ? fields.single : null;
    final value = detail?[2];
    return OdooDiagnosis(
      kind: OdooErrorKind.unique,
      field: field,
      value: value,
      explanation: 'A value that must be unique is already used by another record'
          '${fields.isEmpty ? '' : ' (${fields.join(', ')}${value == null ? '' : ' = $value'})'}.',
      steps: [
        'Send another value for ${fields.isEmpty ? 'that field' : fields.join(', ')}.',
        'Or update the record that already has it: find it with search_read and a domain on that field, then write to its id instead of creating a second one.',
      ],
    );
  }

  static OdooDiagnosis? _foreignKey(String text) {
    final pg = RegExp(r'violates foreign key constraint').hasMatch(text);
    final orm = text.contains('another model requires the record being deleted');
    if (!pg && !orm) return null;
    final missingTarget = RegExp(r'Key \((\w+)\)=\((\d+)\) is not present in table "(\w+)"').firstMatch(text);
    if (missingTarget != null) {
      return OdooDiagnosis(
        kind: OdooErrorKind.foreignKey,
        field: missingTarget[1],
        recordIds: [int.parse(missingTarget[2]!)],
        explanation: 'The field ${missingTarget[1]} points at record ${missingTarget[2]} of ${missingTarget[3]}, which does not exist '
            '(it was deleted, or the id belongs to another database).',
        steps: [
          'Send the id of a record that exists: look it up with name_search, or use {{xmlid:module.name}} / {{ref:model:name}} so it is looked up for you.',
        ],
      );
    }
    final model = RegExp(r'Model:\s*(.+?)\s*\(([\w.]+)\)').firstMatch(text);
    return OdooDiagnosis(
      kind: OdooErrorKind.foreignKey,
      model: model?[2],
      modelLabel: model?[1],
      explanation: 'The record cannot be deleted because other records still point at it.',
      steps: const [
        'Archive it instead (write active = false), which keeps the links.',
        'Or delete or re-point the records that use it first; the message names the model that needs it.',
      ],
    );
  }

  static OdooDiagnosis? _invalidField(String text) {
    String? field;
    String? model;
    final onModel = RegExp(r"(?:Invalid|Unknown) field '(\w+)' (?:on|in) (?:model )?'?([a-z][\w.]*)'?").firstMatch(text);
    final inLeaf = RegExp(r'Invalid field ([a-z][a-z0-9_]*(?:\.[a-z0-9_]+)*)\.(\w+) in leaf').firstMatch(text);
    final plain = RegExp(r"(?:Invalid|Unknown) field '?(\w+)'?|Field '(\w+)' does not exist").firstMatch(text);
    if (onModel != null) {
      field = onModel[1];
      model = onModel[2];
    } else if (inLeaf != null) {
      model = inLeaf[1];
      field = inLeaf[2];
    } else if (plain != null) {
      field = plain[1] ?? plain[2];
    }
    if (field == null) return null;
    return OdooDiagnosis(
      kind: OdooErrorKind.invalidField,
      model: model,
      field: field,
      explanation: '"$field" is not a field of ${model ?? 'this model'}: a typo, a field of a module that is not installed, or one that was renamed in this version.',
      steps: const [
        'Read the real field names with fields_get (the Explorer tab), or run the Check tab on the body: it suggests the nearest names.',
      ],
    );
  }

  static OdooDiagnosis? _badValue(String text) {
    final selection = RegExp(r"Wrong value for ([\w.]+)\.(\w+): '?([^'\n]*)'?").firstMatch(text);
    if (selection != null) {
      return OdooDiagnosis(
        kind: OdooErrorKind.badValue,
        model: selection[1],
        field: selection[2],
        value: selection[3],
        explanation: '"${selection[3]}" is not one of the values the selection field ${selection[2]} of ${selection[1]} accepts.',
        steps: const ['Use one of the stored values of the selection (the Payload tab lists them), not the label shown in the UI.'],
      );
    }
    final date = RegExp(r"time data '([^']*)' does not match format '([^']*)'").firstMatch(text);
    if (date != null) {
      return OdooDiagnosis(
        kind: OdooErrorKind.badValue,
        value: date[1],
        explanation: '"${date[1]}" is not a date or datetime Odoo can read here: it expects ${date[2]}.',
        steps: const ['Write dates as YYYY-MM-DD and datetimes as YYYY-MM-DD HH:MM:SS, in UTC.'],
      );
    }
    return null;
  }
}
