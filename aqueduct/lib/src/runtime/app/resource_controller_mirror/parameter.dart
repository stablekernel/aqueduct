import 'dart:mirrors';

import 'package:aqueduct/src/http/http.dart';
import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/runtime/app/resource_controller_mirror/bindings.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';

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

    binding = bindToType(b, mirror.type as ClassMirror);

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

  BoundInput bindToType(Bind metadata, ClassMirror typeMirror) {
    switch (metadata.bindingType) {
      case BindingType.query:
        return BoundQueryParameter(typeMirror, metadata.name);
      case BindingType.header:
        return BoundHeader(typeMirror, metadata.name);
      case BindingType.body:
        return BoundBody(typeMirror, ignore: metadata.ignore, error: metadata.reject, required: metadata.require);
      case BindingType.path:
        return BoundPath(typeMirror, metadata.name);
    }
    throw StateError(
      "Invalid controller. Operation parameter binding '${metadata.bindingType}' on '${metadata.name}' is unknown.");
  }
}
