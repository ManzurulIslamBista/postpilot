/// Keeps one column's session from leaking into the next. A request that logs in as `user` sets a session cookie; if the
/// `anonymous` column then ran with that cookie in the jar it would not be anonymous. A column with an identity runs
/// inside [isolated]: with no cookies, and the cookies the person had are back when it is over.
abstract interface class MatrixSessionIsolation {
  Future<T> isolated<T>(Future<T> Function() body);
}
