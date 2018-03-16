import 'managed.dart';
import '../persistent_store/persistent_store.dart';
import '../query/query.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/openapi/documentable.dart';

/// The target for database queries and coordinator of [Query]s.
///
/// An application that uses Aqueduct's ORM functionality must create an instance of this type. This is done
/// in a [ApplicationChannel]'s constructor:
///
///         class Channel extends ApplicationChannel {
///            ManagedContext context;
///
///            @override
///            Future prepare() async {
///               var store = new PostgreSQLPersistentStore(...);
///               var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
///               context = new ManagedContext(dataModel, store);
///            }
///
///            @override
///            Controller get entryPoint => ...;
///         }
///
/// A [Query] must have a valid [ManagedContext] to execute. Most applications only need one [ManagedContext],
/// so the most recently [ManagedContext] instantiated becomes the [ManagedContext.defaultContext]. By default, [Query]s
/// target the [ManagedContext.defaultContext] and need not be specified.
class ManagedContext implements APIComponentDocumenter {
  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This instance will become the [ManagedContext.defaultContext], unless another [ManagedContext]
  /// is created, in which the new context becomes the default context. See [ManagedContext.standalone]
  /// to create a context without setting it as the default context.
  ManagedContext(this.dataModel, this.persistentStore);

  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This constructor creates an instance in the same way the default constructor does,
  /// but does not set it to be the [defaultContext].
  ManagedContext.standalone(this.dataModel, this.persistentStore);

  /// The persistent store that [Query]s on this context are executed through.
  final PersistentStore persistentStore;

  /// The data model containing the [ManagedEntity]s that describe the [ManagedObject]s this instance works with.
  final ManagedDataModel dataModel;

  /// Returns an entity for a type from [dataModel].
  ///
  /// See [ManagedDataModel.entityForType].
  ManagedEntity entityForType(Type type) {
    return dataModel.entityForType(type);
  }

  @override
  void documentComponents(APIDocumentContext context) => dataModel.documentComponents(context);
}
