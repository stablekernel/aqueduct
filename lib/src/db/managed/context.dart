import 'managed.dart';
import '../persistent_store/persistent_store.dart';
import '../query/query.dart';
import '../../http/request_sink.dart';

/// The target for database queries and coordinator of [Query]s.
///
/// An application that uses Aqueduct's ORM functionality must create an instance of this type. This is done
/// in a [RequestSink]'s constructor:
///
///         class MyRequestSink extends RequestSink {
///            MyRequestSink(ApplicationConfiguration config) : super(config) {
///               var store = new PostgreSQLPersistentStore(...);
///               var dataModel = new ManagedDataModel.fromCurrentMirrorSystem();
///               context = new ManagedContext(dataModel, store);
///            }
///
///            ManagedContext context;
///         }
///
/// A [Query] must have a valid [ManagedContext] to execute. Most applications only need one [ManagedContext],
/// so the most recently [ManagedContext] instantiated becomes the [ManagedContext.defaultContext]. By default, [Query]s
/// target the [ManagedContext.defaultContext] and need not be specified.
class ManagedContext {
  /// The default context that a [Query] runs on.
  ///
  /// For classes that require a [ManagedContext] - like [Query] - this is the default context when none
  /// is specified.
  ///
  /// This value is set when a [ManagedContext] is instantiated in an isolate; the last context created
  /// is the default context. Most applications
  /// will not use more than one [ManagedContext]. When running tests, you should set
  /// this value each time you instantiate a [ManagedContext] to ensure that a previous test isolate
  /// state did not set this property.
  static ManagedContext defaultContext;

  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This instance will become the [ManagedContext.defaultContext], unless another [ManagedContext]
  /// is created, in which the new context becomes the default context. See [ManagedContext.standalone]
  /// to create a context without setting it as the default context.
  ManagedContext(this.dataModel, this.persistentStore) {
    defaultContext = this;
  }

  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This constructor creates an instance in the same way the default constructor does,
  /// but does not set it to be the [defaultContext].
  ManagedContext.standalone(this.dataModel, this.persistentStore);

  /// The persistent store that [Query]s on this context are executed through.
  PersistentStore persistentStore;

  /// The data model containing the [ManagedEntity]s that describe the [ManagedObject]s this instance works with.
  ManagedDataModel dataModel;

  /// Returns an entity for a type from [dataModel].
  ///
  /// See [ManagedDataModel.entityForType].
  ManagedEntity entityForType(Type type) {
    return dataModel.entityForType(type);
  }
}
