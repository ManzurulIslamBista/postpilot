abstract interface class UseCase<Output, Params> {
  Future<Output> call(Params params);
}

final class NoParams {
  const NoParams();
}
