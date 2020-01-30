import 'dart:async';

import 'package:aqueduct/src/openapi/openapi.dart';
import 'package:aqueduct_test/aqueduct_test.dart';
import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

import 'package:aqueduct/src/dev/helpers.dart';

void main() {
  final app = Application<TestChannel>();
  Controller.letUncaughtExceptionsEscape = true;
  app.options.port = 8888;
  final client = Agent.onPort(app.options.port);

  final errorResponseMatcher = (field) => hasResponse(400, body: {
        'error': 'entity validation failed',
        'reasons': contains(contains(field))
      });

  setUpAll(() async {
    await app.startOnCurrentIsolate();
  });

  tearDownAll(() async {
    await app.channel.context.close();
    await app.stop();
  });

  group("Create", () {
    final modelWithRequired = () => TestModel()..requireCreate = true;

    final successResponseMatcher =
        (json) => hasResponse(200, body: partial(json));

    setUp(() async {});

    test("require filter works", () async {
      final bad = TestModel();
      final errorResp = await client.post("/controller", body: bad.asMap());
      expect(errorResp, errorResponseMatcher('requireCreate'));

      final good = modelWithRequired();
      final successResp = await client.post("/controller", body: good.asMap());

      expect(successResp, successResponseMatcher({'requireCreate': true}));
    });

    test("accept filter works", () async {
      final withAccept = modelWithRequired()..acceptCreate = true;
      final respWithAccepted =
          await client.post("/controller", body: withAccept.asMap());
      expect(respWithAccepted, successResponseMatcher({'acceptCreate': true}));

      final expected = modelWithRequired();
      final withNotAccept = modelWithRequired()..dontAcceptCreate = true;
      final respWithNotAccepted =
          await client.post("/controller", body: withNotAccept.asMap());
      expect(respWithNotAccepted,
          successResponseMatcher({'dontAcceptCreate': null}));
    });

    test("ignore filter works", () async {
      final expected = modelWithRequired();
      final withIgnored = modelWithRequired()..ignoreCreate = true;
      final respWithNotAccepted =
          await client.post("/controller", body: withIgnored.asMap());
      expect(
          respWithNotAccepted, successResponseMatcher({'ignoreCreate': null}));
    });

    test("reject filter works", () async {
      final withRejected = modelWithRequired()..rejectCreate = true;
      final respWithNotAccepted =
          await client.post("/controller", body: withRejected.asMap());
      expect(respWithNotAccepted, errorResponseMatcher('rejectCreate'));
    });
  });

  group("Update", () {
    TestModel insertedModel;
    String endpoint;

    final modelWithRequired = () => TestModel()..requireUpdate = true;
    final successResponseMatcher = (json) =>
        hasResponse(200, body: partial({...json, 'id': insertedModel.id}));

    setUpAll(() async {
      insertedModel = await app.channel.context.insertObject(TestModel());
      endpoint = "/controller/${insertedModel.id}";
    });

    test("require filter works", () async {
      final bad = TestModel();
      final errorResp = await client.put(endpoint, body: bad.asMap());
      expect(errorResp, errorResponseMatcher('requireUpdate'));

      final good = modelWithRequired();
      final successResp = await client.put(endpoint, body: good.asMap());
      expect(successResp, successResponseMatcher({'requireUpdate': true}));
    });

    test("accept filter works", () async {
      final withAccept = modelWithRequired()..acceptUpdate = true;
      final respWithAccepted =
          await client.put(endpoint, body: withAccept.asMap());
      expect(respWithAccepted, successResponseMatcher({'acceptUpdate': true}));

      final withNotAccept = modelWithRequired()..dontAcceptUpdate = true;
      final respWithNotAccepted =
          await client.put(endpoint, body: withNotAccept.asMap());
      expect(respWithNotAccepted,
          successResponseMatcher({'dontAcceptUpdate': null}));
    });

    test("ignore filter works", () async {
      final expected = modelWithRequired();
      final withIgnored = modelWithRequired()..ignoreUpdate = true;
      final respWithNotAccepted =
          await client.put(endpoint, body: withIgnored.asMap());
      expect(
          respWithNotAccepted, successResponseMatcher({'ignoreCreate': null}));
    });

    // test("reject filter works", () async {
    //   final withRejected = modelWithRequired()..rejectCreate = true;
    //   final respWithNotAccepted =
    //       await client.post("/controller", body: withRejected.asMap());
    //   expect(respWithNotAccepted, errorResponseMatcher('rejectCreate'));
    // });
  });
}

class TestChannel extends ApplicationChannel {
  ManagedContext context;

  @override
  Future prepare() async {
    var dataModel = ManagedDataModel([TestModel]);
    var persistentStore = PostgreSQLPersistentStore(
        "dart", "dart", "localhost", 5432, "dart_test");
    context = ManagedContext(dataModel, persistentStore);

    var targetSchema = Schema.fromDataModel(context.dataModel);
    var schemaBuilder = SchemaBuilder.toSchema(
        context.persistentStore, targetSchema,
        isTemporary: true);

    var commands = schemaBuilder.commands;
    for (var cmd in commands) {
      await context.persistentStore.execute(cmd);
    }
  }

  @override
  Controller get entryPoint {
    final router = Router();
    router
        .route("/controller/[:id]")
        .link(() => ManagedObjectController<TestModel>(
              context,
              createFilter: const ReadBodyFilter(
                accept: [
                  "acceptCreate",
                  "rejectCreate",
                  "ignoreCreate",
                  "requireCreate"
                ],
                ignore: ['ignoreCreate'],
                reject: ['rejectCreate'],
                require: ['requireCreate'],
              ),
              updateFilter: const ReadBodyFilter(
                accept: [
                  "acceptUpdate",
                  "rejectUpdate",
                  "ignoreUpdate",
                  "requireUpdate"
                ],
                ignore: ['ignoreUpdate'],
                reject: ['rejectUpdate'],
                require: ['requireUpdate'],
              ),
            ));

    return router;
  }
}

class TestModel extends ManagedObject<_TestModel> implements _TestModel {
  TestModel();
}

class _TestModel {
  @primaryKey
  int id;

  @Column(nullable: true)
  bool dontAcceptCreate;
  @Column(nullable: true)
  bool acceptCreate;
  @Column(nullable: true)
  bool ignoreCreate;
  @Column(nullable: true)
  bool rejectCreate;
  @Column(nullable: true)
  bool requireCreate;
  @Column(nullable: true)
  bool dontAcceptUpdate;
  @Column(nullable: true)
  bool acceptUpdate;
  @Column(nullable: true)
  bool ignoreUpdate;
  @Column(nullable: true)
  bool rejectUpdate;
  @Column(nullable: true)
  bool requireUpdate;
}
