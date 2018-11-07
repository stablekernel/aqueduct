import 'dart:async';

import '../persistent_store/persistent_store.dart';
import 'schema.dart';

/// Thrown when [Migration] encounters an error.
class MigrationException implements Exception {
  MigrationException(this.message);
  String message;

  @override
  String toString() => message;
}

/// The base class for migration instructions.
///
/// For each set of changes to a database, a subclass of [Migration] is created.
/// Subclasses will override [upgrade] to make changes to the [Schema] which
/// are translated into database operations to update a database's schema.
abstract class Migration {
  /// The current state of the [Schema].
  ///
  /// During migration, this value will be modified as [SchemaBuilder] operations
  /// are executed. See [SchemaBuilder].
  Schema get currentSchema => database.schema;

  /// The [PersistentStore] that represents the database being migrated.
  PersistentStore get store => database.store;

  // This value is provided by the 'upgrade' tool and is derived from the filename.
  int version;

  /// Receiver for database altering operations.
  ///
  /// Methods invoked on this instance - such as [SchemaBuilder.createTable] - will be validated
  /// and generate the appropriate SQL commands to apply to a database to alter its schema.
  SchemaBuilder database;

  /// Method invoked to upgrade a database to this migration version.
  ///
  /// Subclasses will override this method and invoke methods on [database] to upgrade
  /// the database represented by [store].
  Future upgrade();

  /// Method invoked to downgrade a database from this migration version.
  ///
  /// Subclasses will override this method and invoke methods on [database] to downgrade
  /// the database represented by [store].
  Future downgrade();

  /// Method invoked to seed a database's data after this migration version is upgraded to.
  ///
  /// Subclasses will override this method and invoke query methods on [store] to add data
  /// to a database after this migration version is executed.
  Future seed();

  static String sourceForSchemaUpgrade(
      Schema existingSchema, Schema newSchema, int version,
      {List<String> changeList}) {
    final diff = existingSchema.differenceFrom(newSchema);
    final source = SchemaBuilder.fromDifference(null, diff, changeList: changeList).commands.map((line) => "\t\t$line").join("\n");

    return """
import 'dart:async';
import 'package:aqueduct/aqueduct.dart';   

class Migration$version extends Migration { 
  @override
  Future upgrade() async {
   $source
  }
  
  @override
  Future downgrade() async {}
  
  @override
  Future seed() async {}
}
    """;
  }
}
