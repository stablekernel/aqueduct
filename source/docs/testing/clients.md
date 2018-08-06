# Using Aqueduct when Writing Client Applications

Running an Aqueduct server locally while developing client applications is an important part of the development process. Run applications through their `bin/main.dart` script or `aqueduct serve`. The former allows for [debugging](debugger.md) the application with a debugger.

## Enable Logging and Return Server Errors

Ensure that logging is on while developing client applications by registering a listener on `ApplicationChannel.logger`.

```dart
class MyApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    logger.onRecord.listen((record) {
      print("$record ${record.error ?? ""} ${record.stackTrace ?? ""}");
    });
  }
  ...
}
```

A useful feature to turn on during debugging is sending stack traces for 500 Server Error responses. Turn this flag on in a `ApplicationChannel` while debugging:

```dart
class MyApplicationChannel extends ApplicationChannel {
  @override
  Future prepare() async {
    Controller.includeErrorDetailsInServerErrorResponses = true;
  }
  ...
}
```

When a 500 error is encountered, the server will send the stack trace back to the client so you can view it while developing the client application without having to switch terminals. This property should never be left on for production code.

## Avoid Port Conflicts

Applications run with `aqueduct serve` default to port 8888. You may use the `--port` command-line option to pick a different port:

```
aqueduct serve --port 4000
```

## Provision a Database for Client Testing

For applications that use the ORM, you must have a locally running database with a schema that matches your application's data model.

If you are using OAuth 2.0, you must have also added client identifiers to the locally running database. You may add client identifiers with the [aqueduct auth](../auth/cli.md) command-line tool.
