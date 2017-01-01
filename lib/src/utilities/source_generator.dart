import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'token_generator.dart';
import 'dart:mirrors';

class SourceGenerator {
  static String generate(Function closure,
      {List<String> imports: const [], String additionalContents}) {
    var gen = new SourceGenerator(closure,
        imports: imports, additionalContents: additionalContents);
    return gen.source;
  }

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
  static Future<dynamic> executeSource(
      SourceGenerator source,
      List<String> arguments,
      {Map<String, dynamic> message,
      Uri packageConfigURI,
      Uri workingDirectory}) async {
    var executor = new IsolateExecutor(source, arguments, message: message, packageConfigURI: packageConfigURI);

    return executor.execute(workingDirectory: workingDirectory);
  }

  IsolateExecutor(this.generator, this.arguments,
      {this.message, this.packageConfigURI});

  SourceGenerator generator;
  Map<String, dynamic> message;
  List<String> arguments;
  Uri packageConfigURI;
  Completer completer = new Completer();

  Future<dynamic> execute({Uri workingDirectory}) async {
    workingDirectory ??= Directory.current.uri;
    message ??= {};

    var tempFile = new File.fromUri(
        workingDirectory.resolve("tmp_${randomStringOfLength(10)}.dart"));
    tempFile.writeAsStringSync(generator.source);

    if (packageConfigURI != null &&
        !(new File.fromUri(packageConfigURI).existsSync())) {
      throw new IsolateExecutorException(
          "packageConfigURI specified but does not exist '${packageConfigURI.path}'.");
    }

    var onErrorPort = new ReceivePort()
      ..listen((err) {
        completer.completeError(err);
      });

    var controlPort = new ReceivePort()
      ..listen((results) {
        completer.complete(results);
      });

    try {
      message["_sendPort"] = controlPort.sendPort;

      if (packageConfigURI != null) {
        await Isolate.spawnUri(tempFile.uri, arguments, message,
            errorsAreFatal: true,
            onError: onErrorPort.sendPort,
            packageConfig: packageConfigURI);
      } else {
        await Isolate.spawnUri(tempFile.uri, arguments, message,
            errorsAreFatal: true,
            onError: onErrorPort.sendPort,
            automaticPackageResolution: true);
      }

      return await completer.future;
    } finally {
      tempFile.deleteSync();
      onErrorPort.close();
      controlPort.close();
    }
  }
}

class IsolateExecutorException implements Exception {
  IsolateExecutorException(this.message);

  final String message;

  String toString() => "IsolateExecutorException: $message";
}