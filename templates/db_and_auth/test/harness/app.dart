import 'package:wildfire/wildfire.dart';
import 'package:aqueduct/test.dart';

export 'package:wildfire/wildfire.dart';
export 'package:aqueduct/test.dart';
export 'package:test/test.dart';
export 'package:aqueduct/aqueduct.dart';

/// A testing harness for wildfire.
///
/// Use instances of this class to start/stop the test wildfire server. Use [client] to execute
/// requests against the test server. This instance will create a temporary version of your
/// code's current database schema during startup. This instance will use configuration values
/// from config.src.yaml.
class TestApplication {
  static const String DefaultClientID = "com.aqueduct.test";
  static const String DefaultClientSecret = "kilimanjaro";
  static const String DefaultPublicClientID = "com.aqueduct.public";

  Application<WildfireChannel> application;
  WildfireChannel get channel => application.channel;
  TestClient client;

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
    RequestController.letUncaughtExceptionsEscape = true;
    application = new Application<WildfireChannel>();
    application.configuration.port = 0;
    application.configuration.configurationFilePath = "config.src.yaml";

    await application.test();

    await initializeDatabase();

    client = new TestClient(application)
      ..clientID = DefaultClientID
      ..clientSecret = DefaultClientSecret;
  }

  Future initializeDatabase() async {
    await createDatabaseSchema(ManagedContext.defaultContext);
    await addClientRecord();
    await addClientRecord(clientID: DefaultPublicClientID, clientSecret: null);
  }

  /// Stops running this application harness.
  ///
  /// This method stops the application from running and frees up any system resources it uses.
  /// Invoke this method in tearDownAll (or tearDown, depending on your test behavior).
  Future stop() async {
    await application?.stop();
  }

  /// Discards any persistent data stored during a test.
  ///
  /// Invoke this method in tearDown() to clear data between tests.
  Future discardPersistentData() async {
    await ManagedContext.defaultContext.persistentStore.close();
    await initializeDatabase();
  }

  /// Adds a client id/secret pair to the temporary database.
  ///
  /// [start] must have already been called prior to executing this method. By default,
  /// every application harness inserts a default client record during [start]. See [start]
  /// for more details.
  static Future<ManagedAuthClient> addClientRecord(
      {String clientID: DefaultClientID,
      String clientSecret: DefaultClientSecret}) async {
    var salt;
    var hashedPassword;
    if (clientSecret != null) {
      salt = AuthUtility.generateRandomSalt();
      hashedPassword = AuthUtility.generatePasswordHash(clientSecret, salt);
    }

    var clientQ = new Query<ManagedAuthClient>()
      ..values.id = clientID
      ..values.salt = salt
      ..values.hashedSecret = hashedPassword;
    return clientQ.insert();
  }

  /// Adds database tables to the temporary test database based on the declared [ManagedObject]s in this application.
  ///
  /// This method is executed during [start], and you shouldn't have to invoke it yourself.
  static Future createDatabaseSchema(
      ManagedContext context, {Logger logger}) async {
    var builder = new SchemaBuilder.toSchema(
        context.persistentStore, new Schema.fromDataModel(context.dataModel),
        isTemporary: true);

    for (var cmd in builder.commands) {
      logger?.info("$cmd");
      await context.persistentStore.execute(cmd);
    }
  }
}
