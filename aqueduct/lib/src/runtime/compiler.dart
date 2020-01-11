import 'dart:io';
import 'dart:mirrors';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/application/channel.dart';
import 'package:aqueduct/src/runtime/orm/data_model_compiler.dart';

import 'package:aqueduct/src/runtime/impl.dart';
import 'package:runtime/runtime.dart';

class AqueductCompiler extends Compiler {
  @override
  Map<String, dynamic> compile(MirrorContext context) {
    final m = <String, dynamic>{};

    m.addEntries(context.getSubclassesOf(ApplicationChannel)
      .map((t) => MapEntry(_getClassName(t), ChannelRuntimeImpl(t))));
    m.addEntries(context.getSubclassesOf(Serializable)
      .map((t) => MapEntry(_getClassName(t), SerializableRuntimeImpl(t))));
    m.addEntries(context.getSubclassesOf(Controller)
      .map((t) => MapEntry(_getClassName(t), ControllerRuntimeImpl(t))));
    m.addEntries(context.getSubclassesOf(BodyDecoder)
      .map((t) => MapEntry(_getClassName(t), BodyDecoderRuntimeImpl())));

    m.addAll(DataModelCompiler().compile(context));

    return m;
  }

  String _getClassName(ClassMirror mirror) {
    return MirrorSystem.getName(mirror.simpleName);
  }

  @override
  void deflectPackage(Directory destinationDirectory) {
    final libFile = File.fromUri(
      destinationDirectory.uri.resolve("lib/").resolve("aqueduct.dart"));
    final contents = libFile.readAsStringSync();
    libFile.writeAsStringSync(
      contents.replaceFirst("export 'package:aqueduct/src/runtime/compiler.dart';", ""));
  }
}
