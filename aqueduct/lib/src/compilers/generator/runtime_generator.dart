import 'dart:async';
import 'dart:io';

import 'package:meta/meta.dart';

const String _directiveToken = "___DIRECTIVES___";
const String _assignmentToken = "___ASSIGNMENTS___";

class RuntimeGenerator {
  List<_RuntimeElement> _elements = [];

  void addRuntime({@required String kind, @required String name, @required String source}) {
    final uri = Uri.directory("$kind/")
        .resolve("${name.toLowerCase()}.dart");
    _elements.add(_RuntimeElement(kind, name, uri, source));
  }

  Future<void> writeTo(Uri directoryUri) async {
    final dir = Directory.fromUri(directoryUri);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final libraryFile = File.fromUri(dir.uri.resolve("loader.dart"));
    await libraryFile.writeAsString(loaderSource);

    await Future.forEach(_elements, (_RuntimeElement e) async {
      final file = File.fromUri(dir.uri.resolveUri(e.relativeUri));
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      await file.writeAsString(e.source);
    });
  }


  String get _loaderShell => """
import 'package:aqueduct/src/runtime/runtime.dart';
import 'package:aqueduct/src/runtime/app/app.dart';

$_directiveToken

class RuntimeLoader {
  static Runtime load() {
    final out = Runtime();
    final runtimes = <String, RuntimeBase>{};
    
    $_assignmentToken
    
    out.runtimes = RuntimeTypeCollection(runtimes);
    // caster = ??;

    return out;
  }
}  
  """;

  String get loaderSource {
    return _loaderShell
        .replaceFirst(_directiveToken, _directives)
        .replaceFirst(_assignmentToken, _assignments);
  }

  String get _directives {
    final buf = StringBuffer();

    _elements.forEach((e) {
      buf.writeln("import '${e.relativeUri.path}' as ${e.importAlias};");
    });

    return buf.toString();
  }

  String get _assignments {
    final buf = StringBuffer();

    _elements.forEach((e) {
      buf.writeln("runtimes['${e.typeName}'] = ${e.importAlias}.instance;");
    });

    return buf.toString();
  }
}

class _RuntimeElement {
  _RuntimeElement(this.kind, this.typeName, this.relativeUri, this.source);

  final String kind;
  final String typeName;
  final String source;
  final Uri relativeUri;

  String get importAlias {
    return "${kind.toLowerCase()}_${typeName.toLowerCase()}";
  }
}
