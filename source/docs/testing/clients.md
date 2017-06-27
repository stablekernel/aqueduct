# Using Aqueduct when Writing Client Applications

Running an Aqueduct server locally while developing client applications is an important part of the development process. Run applications through their `bin/main.dart` script or `aqueduct serve`. The former allows for [debugging](debugger.md) the application with a debugger.

## Enable Logging and Return Server Errors

Ensure that logging is on while developing client applications by registering a listener on `RequestSink.logger`.

```dart
class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config) {
    logger.onRecord.listen((record) {
      print("$record ${record.error ?? ""} ${record.stackTrace ?? ""}");
    });
  }
  ...
}
```

A useful feature to turn on during debugging is sending stack traces for 500 Server Error responses. Turn this flag on in a `RequestSink` while debugging:

```dart
class MyRequestSink extends RequestSink {
  MyRequestSink(ApplicationConfiguration config) : super(config) {
    RequestController.includeErrorDetailsInServerErrorResponses = true;
  }
  ...
}
```

When a 500 error is encountered, the server will send the stack trace back to the client so you can view it while developing the client application without having to switch terminals. This property should never be left on for production code.

## Avoid Port Conflicts

Aqueduct applications run through the `bin/main.dart` script default to port 8000. Applications run with `aqueduct serve` default to port 8081. You may use the `--port` command-line option to pick a different port:

```
aqueduct serve --port 4000
```

## Provision a Database During Client Testing

See [provisioning a database](database.md) for more details.
