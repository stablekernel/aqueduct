import 'package:wildfire/wildfire.dart';
import 'package:scribe/scribe.dart';
import 'dart:async';

class TestApplication {
  TestApplication() {
    configuration = new WildfireConfiguration("config.yaml.src");
    configuration.database.isTemporary = true;
  }

  Application<WildfireSink> application;
  WildfireSink get stream => application.server.stream;
  LoggingServer logger = new LoggingServer([]);
  TestClient client;
  WildfireConfiguration configuration;

  Future start() async {
    await logger.start();

    application = new Application<WildfireSink>();
    application.configuration.configurationOptions = {
      WildfireSink.ConfigurationKey: configuration,
      WildfireSink.LoggingTargetKey : logger.getNewTarget()
    };

    await application.start(runOnMainIsolate: true);

    ModelContext.defaultContext = stream.context;

    await createDatabaseSchema(stream.context, stream.logger);
    await addClientRecord();

    client = new TestClient(application.configuration.port)
      ..clientID = "com.aqueduct.test"
      ..clientSecret = "kilimanjaro";
  }

  Future stop() async {
    await stream.context.persistentStore?.close();
    await logger?.stop();
    await application?.stop();
  }

  static Future addClientRecord({String clientID: "com.aqueduct.test", String clientSecret: "kilimanjaro"}) async {
    var salt = AuthenticationServer.generateRandomSalt();
    var hashedPassword = AuthenticationServer.generatePasswordHash(clientSecret, salt);
    var testClientRecord = new ClientRecord();
    testClientRecord.id = clientID;
    testClientRecord.salt = salt;
    testClientRecord.hashedPassword = hashedPassword;

    var clientQ = new Query<ClientRecord>()
      ..values.id = clientID
      ..values.salt = salt
      ..values.hashedPassword = hashedPassword;
    await clientQ.insert();
  }

  static Future createDatabaseSchema(ModelContext context, Logger logger) async {
    var generator = new SchemaGenerator(context.dataModel);
    var json = generator.serialized;
    var pGenerator = new PostgreSQLSchemaGenerator(json, temporary: true);

    for (var cmd in pGenerator.commandList.split(";\n")) {
      logger?.info("$cmd");
      await context.persistentStore.execute(cmd);
    }
  }
}