/// Allows [ManagedObjectController]s to filter the body parameters of POST and PUT request
///
/// An instance of it could be passed to [ManagedObjectController] constructor to enable that behavior

class ReadBodyFilter {
  const ReadBodyFilter({this.accept, this.ignore, this.reject, this.require});

  final List<String> accept;
  final List<String> ignore;
  final List<String> reject;
  final List<String> require;
}
