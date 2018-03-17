import 'dart:async';

import 'package:aqueduct/src/application/service_registry.dart';
import 'package:aqueduct/src/db/managed/data_model_manager.dart';

import 'managed.dart';
import '../persistent_store/persistent_store.dart';
import '../query/query.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/openapi/documentable.dart';

/// A service object required to execute [Query]s.
///
/// You create objects of this type to use the Aqueduct ORM. Create instances in [ApplicationChannel.prepare]
/// and inject them into controllers that execute database queries.
///
/// A context must have a [PersistentStore] (that determines the database queries are sent to) and a [ManagedDataModel] (that determines
/// the [ManagedObject]s that can be used).
///
/// Example usage:
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
///            Controller get entryPoint {
///              final router = new Router();
///              router.route("/path").link(() => new DBController(context));
///              return router;
///            }
///         }
class ManagedContext implements APIComponentDocumenter {
  /// Creates an instance of [ManagedContext] from a [ManagedDataModel] and [PersistentStore].
  ///
  /// This is the default constructor.
  ManagedContext(this.dataModel, this.persistentStore) {
    ManagedDataModelManager.add(dataModel);
    ApplicationServiceRegistry.defaultInstance.register<ManagedContext>(this, (o) => o.close());
  }

  /// The persistent store that [Query]s on this context are executed through.
  final PersistentStore persistentStore;

  /// The data model containing the [ManagedEntity]s that describe the [ManagedObject]s this instance works with.
  final ManagedDataModel dataModel;

  /// Closes this context and release its underlying resources.
  ///
  /// This method closes the connection to [persistentStore] and releases [dataModel].
  /// A context may not be reused once it has been closed.
  Future close() async {
    await persistentStore?.close();
    dataModel?.release();
  }

  /// Returns an entity for a type from [dataModel].
  ///
  /// See [ManagedDataModel.entityForType].
  ManagedEntity entityForType(Type type) {
    return dataModel.entityForType(type);
  }

  @override
  void documentComponents(APIDocumentContext context) => dataModel.documentComponents(context);
}
