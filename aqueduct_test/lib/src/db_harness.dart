import 'dart:async';

import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';

/// Use methods from this class to test applications that use the Aqueduct ORM.
///
/// This class is mixed in to your [TestHarness] subclass to provide test
/// utilities for applications that use use the Aqueduct ORM. Methods from this class
/// manage setting up and tearing down your application's data model in a temporary database
/// for the purpose of testing.
///
/// You must override [context] to return your application's [ManagedContext] service.
/// You must override [seed] to insert static data in your database, as data is typically
/// cleared between tests.
///
/// You invoke [resetData] in your harness' [TestHarness.afterStart] method,
/// and typically in your test suite's [tearDown] method.
///
///         class Harness extends TestHarness<MyChannel> with TestHarnessORMMixin {
///             @override
///             ManagedContext get context => channel.context;
///
///             Future seed() async {
///               await Query.insertObject(...);
///             }
///         }
abstract class TestHarnessORMMixin {
  /// Must override to return [ManagedContext] of application under test.
  ///
  /// An [ApplicationChannel] should expose its [ManagedContext] service as a property.
  /// Return the context from this method.
  ManagedContext get context;

  /// Override this method to insert static data for each test run.
  ///
  /// This method gets invoked after [resetData] is called to re-provisioning static
  /// data in your application's database.
  ///
  /// For example, an application might have a table that contains country codes for
  /// every country in the world; this data would be cleared between each test case
  /// when [resetData] is called. By implementing this method, that data is recreated
  /// after the database is reset.
  Future seed() async {}

  /// Restores the initial database state of the application under test.
  ///
  /// This method destroys the connection to the application's database, deleting tables
  /// and data created during a test running. After the database is cleared,
  /// the application schema is reloaded and [seed] is invoked to re-provision
  /// static data.
  ///
  /// This method should be invoked in [TestHarness.afterStart] and typically is invoked
  /// in [tearDown] for your test suite.
  Future resetData({Logger logger}) async {
    await context.persistentStore.close();
    await addSchema(logger: logger);
    await seed();
  }

  /// Adds the database tables in [context] to the database for the application under test.
  ///
  /// This method executes database commands to create temporary tables in the test database.
  /// It is invoked by [resetData].
  Future addSchema({Logger logger}) async {
    final builder = SchemaBuilder.toSchema(
        context.persistentStore, Schema.fromDataModel(context.dataModel),
        isTemporary: true);

    for (var cmd in builder.commands) {
      logger?.info("$cmd");
      await context.persistentStore.execute(cmd);
    }
  }
}
