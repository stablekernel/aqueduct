/*
  For building and running non-example applications, install 'aqueduct' command-line tool.

      pub global activate aqueduct
      aqueduct create my_app
      cd my_app/
      aqueduct serve

  More examples available: https://github.com/stablekernel/aqueduct_examples
 */

import 'dart:async';
import 'package:aqueduct/aqueduct.dart';

Future main() async {
  final app = new Application<App>()
    ..options.configurationFilePath = 'config.yaml'
    ..options.port = 8888;

  await app.start(numberOfInstances: 3);
}

class App extends ApplicationChannel {
  @override
  Controller get entryPoint {
    final router = new Router();
    router.route('/example/[:id]').link(() => new ExampleController());
    return router;
  }
}

class ExampleController extends ResourceController {
  @Operation.get()
  Future<Response> getExamples() async {
    return new Response.ok([]);
  }

  @Operation.get('id')
  Future<Response> getExampleById(@Bind.path('id') int id) async {
    return new Response.ok({'id': id});
  }
}