import 'dart:mirrors';
import 'package:aqueduct/aqueduct.dart';
import 'package:aqueduct/src/application/channel.dart';

import 'package:aqueduct/src/runtime/app/mirror.dart';
import 'package:runtime/runtime.dart';

class ApplicationCompiler extends Compiler {
  @override
  Map<String, DynamicRuntime> compile(MirrorContext context) {
    final m = <String, DynamicRuntime>{};

    m.addEntries(context.getSubclassesOf(ApplicationChannel)
      .map((t) => MapEntry(_getClassName(t), ChannelRuntimeImpl(t))));
    m.addEntries(context.getSubclassesOf(Serializable)
      .map((t) => MapEntry(_getClassName(t), SerializableRuntimeImpl(t))));
    m.addEntries(context.getSubclassesOf(Controller)
      .map((t) => MapEntry(_getClassName(t), ControllerRuntimeImpl(t))));

    m[_getClassName(reflectClass(BodyDecoder))] = BodyDecoderRuntimeImpl();

    return m;
  }

  String _getClassName(ClassMirror mirror) {
    return MirrorSystem.getName(mirror.simpleName);
  }
}
