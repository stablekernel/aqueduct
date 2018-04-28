import 'package:wildfire/wildfire.dart';
import 'package:aqueduct_test/aqueduct_test.dart';

export 'package:wildfire/wildfire.dart';
export 'package:aqueduct_test/aqueduct_test.dart';
export 'package:test/test.dart';
export 'package:aqueduct/aqueduct.dart';

/// A testing harness for wildfire.
///
/// Use instances of this class to start/stop the test wildfire server. Use [client] to execute
/// requests against the test server. This instance will create a temporary version of your
/// code's current database schema during startup. This instance will use configuration values
/// from config.src.yaml.
class TestApplication {
  Application<WildfireChannel> application;
  TestClient client;

  String get configurationFilePath => "config.src.yaml";

  WildfireChannel get channel => application.channel;

  /// Starts running this test harness.
  ///
  /// This method will start an [Application] with [WildfireChannel].
  /// The declared [ManagedObject]s in this application will be
  /// used to generate a temporary database schema. The [WildfireChannel] instance will use
  /// this temporary database. Stopping this application will remove the data from the
  /// temporary database.
  ///
  /// An initial client ID/secret pair will be generated and added to the database
  /// for the [client] to use. This value is "com.aqueduct.test"/"kilimanjaro".
  ///
  /// Invoke this method in setUpAll (or setUp, depending on your test behavior). You may
  /// also use [discardPersistentData] to keep the application running but discard any
  /// data stored by the ORM during the test.
  ///
  /// You must call [stop] on this instance when tearing down your tests.
  Future start() async {
    Controller.letUncaughtExceptionsEscape = true;

    application = new Application<WildfireChannel>()
      ..options.port = 0
      ..options.configurationFilePath = configurationFilePath;

    await application.test();

    await initializeDatabase();

    client = new TestClient(application);
  }

  /// Stops running this application harness.
  ///
  /// This method stops the application from running and frees up any system resources it uses.
  /// Invoke this method in tearDownAll (or tearDown, depending on your test behavior).
  Future stop() async {
    await application?.stop();
  }

  Future initializeDatabase() async {
    await createDatabaseSchema(application.channel.context);
  }

  /// Discards any persistent data stored during a test.
  ///
  /// Invoke this method in tearDown() to clear data between tests.
  Future discardPersistentData() async {
    await application.channel.context.persistentStore.close();
    await initializeDatabase();
  }

  /// Adds database tables to the temporary test database based on the declared [ManagedObject]s in this application.
  ///
  /// This method is executed during [start], and you shouldn't have to invoke it yourself.
  static Future createDatabaseSchema(ManagedContext context, {Logger logger}) async {
    var builder = new SchemaBuilder.toSchema(context.persistentStore, new Schema.fromDataModel(context.dataModel),
        isTemporary: true);

    for (var cmd in builder.commands) {
      logger?.info("$cmd");
      await context.persistentStore.execute(cmd);
    }
  }
}
