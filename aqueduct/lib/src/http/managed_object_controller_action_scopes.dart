/// Allows [ManagedObjectController]s to have different scopes for each CRUD action.
///
/// An instance of it could be passed to [ManagedObjectController] constructor to enable that behavior
class ActionScopes {
  const ActionScopes(
      {this.index, this.delete, this.update, this.create, this.find});

  final List<String> find;
  final List<String> index;
  final List<String> create;
  final List<String> update;
  final List<String> delete;
}
