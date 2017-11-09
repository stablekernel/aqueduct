import 'dart:async';

import 'package:test/test.dart';
import 'package:aqueduct/aqueduct.dart';

void main() {
  test("Can add resources to registry that get shut down", () async {
    var controller = new StreamController();
    ApplicationServiceRegistry.defaultInstance.register<StreamController>(controller, (s) => s.close());

    var msgCompleter = new Completer();
    controller.stream.listen((msg) {
      msgCompleter.complete();
    });

    controller.add("whatever");
    await msgCompleter.future;

    await ApplicationServiceRegistry.defaultInstance.close();
    expect(controller.isClosed, true);
  });

  test("Can remove resource", () async {
    var controller = new StreamController();
    ApplicationServiceRegistry.defaultInstance.register<StreamController>(controller, (s) => s.close());

    var msgCompleter = new Completer();
    controller.stream.listen((msg) {
      msgCompleter.complete();
    });

    controller.add("whatever");
    await msgCompleter.future;

    ApplicationServiceRegistry.defaultInstance.unregister(controller);

    await ApplicationServiceRegistry.defaultInstance.close();
    expect(controller.isClosed, false);

    await controller.close();
  });
}