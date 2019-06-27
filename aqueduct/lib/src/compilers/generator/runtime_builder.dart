import 'dart:async';

import 'dart:io';

import 'package:aqueduct/src/runtime/app/app.dart';
import 'package:aqueduct/src/runtime/orm/orm.dart';

class RuntimeBuilder {
  List<_RuntimeElement> _elements = [];

  void addRuntime(Type baseType, String typeName, String source) {
    final uri = Uri.directory("${baseType.toString().toLowerCase()}/")
        .resolve("${typeName.toLowerCase()}.dart");
    _elements.add(_RuntimeElement(baseType, typeName, uri, source));
  }

  Future<void> writeTo(Uri directoryUri) async {
    final dir = Directory.fromUri(directoryUri);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final libraryFile = File.fromUri(dir.uri.resolve("runtime_impl.dart"));
    await libraryFile.writeAsString(loaderSource);

    await Future.forEach(_elements, (_RuntimeElement e) async {
      final file = File.fromUri(dir.uri.resolveUri(e.relativeUri));
      if (!file.parent.existsSync()) {
        file.parent.createSync(recursive: true);
      }

      await file.writeAsString(e.source);
    });
  }

  static const String _directiveToken = "___DIRECTIVES___";
  static const String _assignmentToken = "___ASSIGNMENTS___";
  static const String _channelMapVariable = "channelMap";
  static const String _serializableMapVariable = "serializableMap";
  static const String _controllerMapVariable = "controllerMap";
  static const String _entityMapVariable = "entityMap";

  String get _loaderShell => """
import 'package:aqueduct/src/runtime/runtime.dart';
$_directiveToken

class RuntimeLoader {
  static Runtime load() {
    final out = Runtime();
    final $_channelMapVariable = <String, ChannelRuntime>{};
    final $_serializableMapVariable = <String, SerializableRuntime>{};
    final $_controllerMapVariable = <String, ControllerRuntime>{};
    final $_entityMapVariable = <String, ManagedEntityRuntime>{};
    
    $_assignmentToken
    
    
    out.channels = RuntimeTypeCollection($_channelMapVariable);
    out.serializables = RuntimeTypeCollection($_serializableMapVariable);
    out.controllers = RuntimeTypeCollection($_controllerMapVariable);
    out.managedEntities = RuntimeTypeCollection($_entityMapVariable);

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
      final varName = _getVariableNameForBaseType(e.baseType);
      buf.writeln("$varName['${e.typeName}'] = ${e.importAlias}.instance;");
    });

    return buf.toString();
  }

  String _getVariableNameForBaseType(Type baseType) {
    switch (baseType) {
      case ChannelRuntime: return _channelMapVariable;
      case SerializableRuntime: return _serializableMapVariable;
      case ManagedEntityRuntime: return _entityMapVariable;
      case ControllerRuntime: return _controllerMapVariable;
      default: throw ArgumentError("unsupported baseType '$baseType'");
    }
  }
}

class _RuntimeElement {
  _RuntimeElement(this.baseType, this.typeName, this.relativeUri, this.source);

  final Type baseType;
  final String typeName;
  final String source;
  final Uri relativeUri;

  String get importAlias {
    return "${baseType.toString().toLowerCase()}_${typeName.toLowerCase()}";
  }
}
