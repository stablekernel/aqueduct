import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/auth/auth.dart';

/// Allows [ResourceController]s to have different scope for each operation method.
///
/// This type is used as an annotation to an operation method declared in a [ResourceController].
///
/// If an operation method has this annotation, an incoming [Request.authorization] must have sufficient
/// scope for the method to be executed. If not, a 403 Forbidden response is sent. Sufficient scope
/// requires that *every* listed scope is met by the request.
///
/// The typical use case is to require more scope for an editing action than a viewing action. Example:
///
///         class NoteController extends ResourceController {
///           @Scope(['notes.readonly']);
///           @Operation.get('id')
///           Future<Response> getNote(@Bind.path('id') int id) async {
///             ...
///           }
///
///           @Scope(['notes']);
///           @Operation.post()
///           Future<Response> createNote() async {
///             ...
///           }
///         }
///
/// An [Authorizer] *must* have been previously linked in the channel. Otherwise, an error is thrown
/// at runtime. Example:
///
///         router
///           .route("/notes/[:id]")
///           .link(() => Authorizer.bearer(authServer))
///           .link(() => NoteController());
class Scope {
  /// Add to [ResourceController] operation method to require authorization scope.
  ///
  /// An incoming [Request.authorization] must have sufficient scope for all [scopes].
  const Scope(this.scopes);

  /// The list of authorization scopes required.
  final List<String> scopes;
}
