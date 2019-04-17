import 'dart:mirrors';

import 'package:aqueduct/src/utilities/mirror_helpers.dart';

import '../request.dart';
import '../resource_controller_bindings.dart';
import 'internal.dart';

class BoundParameter {
  BoundParameter(VariableMirror mirror, {this.isRequired = false})
      : symbol = mirror.simpleName {
    final b = mirror.metadata.firstWhere((im) => im.reflectee is Bind).reflectee
        as Bind;

    if (mirror.type is! ClassMirror) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(symbol)}' on '${getMethodAndClassName(mirror)}': "
          "'${MirrorSystem.getName(mirror.type.simpleName)}'. Cannot bind dynamic parameters.");
    }

    binding = b.bindToType(mirror.type as ClassMirror);

    try {
      binding.validate();
    } catch (e) {
      throw StateError(
          "Invalid binding '${MirrorSystem.getName(symbol)}' on '${getMethodAndClassName(mirror)}': "
          "$e");
    }
  }

  final Symbol symbol;
  final bool isRequired;

  String get name => binding.externalName;

  BoundInput binding;

  dynamic decode(Request request) {
    return binding.decode(request);
  }
}
