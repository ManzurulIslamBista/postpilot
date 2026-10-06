import '../../../../../core/network/upload_body.dart';
import '../../entities/key_value_item.dart';
import '../../entities/request_body.dart';

/// The warning an import gives for the files it brought in by path: a path like `C:\Users\ann\a.png` names one place
/// on one machine, so the request breaks for a teammate (and on this machine once the file moves).
abstract final class UploadPathNote {
  /// How many of the file rows of [bodies] (form-data files and the file of a binary body) have a path that belongs
  /// to one machine. A path made of a `{{variable}}` and a name does not.
  static int machineSpecificIn(Iterable<RequestBody> bodies) {
    var count = 0;
    for (final body in bodies) {
      count += machineSpecificRows(body.formFields);
    }
    return count;
  }

  static int machineSpecificRows(Iterable<KeyValueItem> rows) =>
      rows.where((row) => row.isFile && FilePaths.isMachineSpecific(row.value)).length;

  /// The sentence for [count] such paths; null when there are none.
  static String? of(int count) {
    if (count <= 0) return null;
    final subject = count == 1 ? '1 file path points' : '$count file paths point';
    return '$subject to this machine, so ${count == 1 ? 'it' : 'they'} will not work for a teammate. '
        'Replace the start of the path with a variable, for example {{uploadDir}}/avatar.png.';
  }
}
