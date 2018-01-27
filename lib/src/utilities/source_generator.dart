import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:mirrors';

class SourceGenerator {
  SourceGenerator(this.closure,
      {this.imports: const [], this.additionalContents});

  Function closure;

  List<String> imports;
  String additionalContents;

  String get source {
    var source = (reflect(closure) as ClosureMirror).function.source;
    var builder = new StringBuffer();

    imports.forEach((import) {
      builder.writeln("import '$import';");
    });

    builder.writeln("");
    builder.writeln(
        "Future main (List<String> args, Map<String, dynamic> message) async {");
    builder.writeln("  var sendPort = message['_sendPort'];");
    builder.writeln("  var f = $source;");
    builder.writeln("  var result = await f(args, message);");
    builder.writeln("  sendPort.send(result);");
    builder.writeln("}");

    if (additionalContents != null) {
      var strippedSource = additionalContents
          .split("\n")
          .where((l) => !l.startsWith("import '"))
          .join("\n");
      builder.writeln(strippedSource);
    }

    return builder.toString();
  }
}

class IsolateExecutor {
  IsolateExecutor(this.generator, this.arguments,
      {this.message, this.packageConfigURI});

  static Future<dynamic> executeSource(
      SourceGenerator source, List<String> arguments,
      {Map<String, dynamic> message, Uri packageConfigURI}) async {
    var executor = new IsolateExecutor(source, arguments,
        message: message, packageConfigURI: packageConfigURI);

    return executor.execute();
  }

  SourceGenerator generator;
  Map<String, dynamic> message;
  List<String> arguments;
  Uri packageConfigURI;
  Completer completer = new Completer();

  Future<dynamic> execute() async {
    message ??= {};

    if (packageConfigURI != null &&
        !(new File.fromUri(packageConfigURI).existsSync())) {
      throw new StateError("Package file '$packageConfigURI' not found. Run 'pub get' and retry.");
    }

    var onErrorPort = new ReceivePort()
      ..listen((err) {
        if (err is List<String>) {
          final source = Uri.encodeComponent(generator.source);
          final stack = new StackTrace.fromString(err.last.replaceAll(source, ""));

          completer.completeError(new StateError(err.first), stack);
        } else {
          completer.completeError(err);
        }
      });

    var controlPort = new ReceivePort()
      ..listen((results) {
        completer.complete(results);
      });

    try {
      message["_sendPort"] = controlPort.sendPort;

      final source = generator.source;
      final dataUri = Uri.parse("data:application/dart;charset=utf-8,${Uri.encodeComponent(source)}");
      if (packageConfigURI != null) {
        await Isolate.spawnUri(dataUri, arguments, message,
            errorsAreFatal: true,
            onError: onErrorPort.sendPort,
            packageConfig: packageConfigURI);
      } else {
        await Isolate.spawnUri(dataUri, arguments, message,
            errorsAreFatal: true,
            onError: onErrorPort.sendPort,
            automaticPackageResolution: true);
      }

      return await completer.future;
    } finally {
      onErrorPort.close();
      controlPort.close();
    }
  }
}