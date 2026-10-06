import 'upload_body.dart';
import 'upload_file_source.dart';

/// A browser cannot read a path: the files its user picked are kept in memory for the session ([SessionFiles]).
UploadFileSource createUploadFileSource({String? baseDir}) => MemoryUploadFileSource(SessionFiles.shared);
