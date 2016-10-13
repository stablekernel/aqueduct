part of aqueduct;

class _SourceGenerator {
  static String generate(Function closure, {List<String> imports: const [], String additionalContents}) {
    var gen = new _SourceGenerator(closure, imports: imports, additionalContents: additionalContents);
    return gen.source;
  }

  _SourceGenerator(this.closure, {this.imports: const [], this.additionalContents});

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
    builder.writeln("Future main (List<String> args, Map<String, dynamic> message) async {");
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

class _IsolateExecutor {
  _IsolateExecutor(this.generator, this.arguments, {this.message, this.packageConfigURI});

  _SourceGenerator generator;
  Map<String, dynamic> message;
  List<String> arguments;
  Uri packageConfigURI;
  Completer completer = new Completer();

  Future<dynamic> execute({Uri workingDirectory}) async {
    workingDirectory ??= Directory.current.uri;
    message ??= {};

    var tempFile = new File.fromUri(workingDirectory.resolve("tmp_${randomStringOfLength(10)}.dart"));
    tempFile.writeAsStringSync(generator.source);

    if (packageConfigURI != null && !(new File.fromUri(packageConfigURI).existsSync())) {
      throw new Exception("packageConfigURI specified but does not exist (${packageConfigURI}).");
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
        await Isolate.spawnUri(tempFile.uri, arguments, message, errorsAreFatal: true, onError: onErrorPort.sendPort, packageConfig: packageConfigURI);
      } else {
        await Isolate.spawnUri(tempFile.uri, arguments, message, errorsAreFatal: true, onError: onErrorPort.sendPort, automaticPackageResolution: true);
      }

      return await completer.future;
    } finally {
      tempFile.deleteSync();
      onErrorPort.close();
      controlPort.close();
    }
  }
}