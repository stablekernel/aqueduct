import 'package:wildfire/wildfire.dart';
export 'package:wildfire/wildfire.dart';
export 'package:test/test.dart';

/// A testing harness for wildfire.
///
/// Use instances of this class to start/stop the test wildfire server. Use [client] to execute
/// requests against the test server. This instance will create a temporary version of your
/// code's current database schema during startup. This instance will use configuration values
/// from config.yaml.src.
class TestApplication {

  /// Creates an instance of this class.
  ///
  /// Reads configuration values from config.yaml.src. See [start] for usage.
  TestApplication() {
    configuration = new WildfireConfiguration("config.yaml.src");
    configuration.database.isTemporary = true;
  }

  Application<WildfireSink> application;
  WildfireSink get sink => application.mainIsolateSink;
  LoggingServer logger = new LoggingServer([]);
  TestClient client;
  WildfireConfiguration configuration;

  /// Starts running this test harness.
  ///
  /// This method will start a [LoggingServer] and an [Application] with [WildfireSink].
  /// It will also setup a temporary database connection to the database described in
  /// config.yaml.src. The current declared [ManagedObject]s in this application will be
  /// used to generate a temporary database schema. The [WildfireSink] instance will use
  /// this temporary database. Stopping this application will remove the data from the
  /// temporary database.
  ///
  /// An initial client ID/secret pair will be generated and added to the database
  /// for the [client] to use. This value is "com.aqueduct.test"/"kilimanjaro".
  ///
  /// You must call [stop] on this instance when tearing down your tests.
  Future start() async {
    await logger.start();

    application = new Application<WildfireSink>();
    application.configuration.configurationOptions = {
      WildfireSink.ConfigurationKey: configuration,
      WildfireSink.LoggingTargetKey: logger.getNewTarget()
    };

    await application.start(runOnMainIsolate: true);

    ManagedContext.defaultContext = sink.context;

    await createDatabaseSchema(sink.context, sink.logger);
    await addClientRecord();

    client = new TestClient(application)
      ..clientID = "com.aqueduct.test"
      ..clientSecret = "kilimanjaro";
  }

  /// Stops running this application harness.
  ///
  /// This method must be called during test tearDown.
  Future stop() async {
    await sink.context.persistentStore?.close();
    await logger?.stop();
    await application?.stop();
  }

  /// Adds a client id/secret pair to the temporary database.
  ///
  /// [start] must have already been called prior to executing this method. By default,
  /// every application harness inserts a default client record during [start]. See [start]
  /// for more details.
  static Future<ClientRecord> addClientRecord(
      {String clientID: "com.aqueduct.test",
      String clientSecret: "kilimanjaro"}) async {
    var salt = AuthServer.generateRandomSalt();
    var hashedPassword = AuthServer.generatePasswordHash(clientSecret, salt);
    var testClientRecord = new ClientRecord();
    testClientRecord.id = clientID;
    testClientRecord.salt = salt;
    testClientRecord.hashedPassword = hashedPassword;

    var clientQ = new Query<ClientRecord>()
      ..values.id = clientID
      ..values.salt = salt
      ..values.hashedPassword = hashedPassword;
    return await clientQ.insert();
  }

  /// Adds database tables to the temporary test database based on the declared [ManagedObject]s in this application.
  ///
  /// This method is executed during [start], and you shouldn't have to invoke it yourself.
  static Future createDatabaseSchema(
      ManagedContext context, Logger logger) async {
    var builder = new SchemaBuilder.toSchema(
        context.persistentStore, new Schema.fromDataModel(context.dataModel),
        isTemporary: true);

    for (var cmd in builder.commands) {
      logger?.info("$cmd");
      await context.persistentStore.execute(cmd);
    }
  }
}
