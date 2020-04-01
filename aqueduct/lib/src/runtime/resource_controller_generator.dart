import 'dart:mirrors';

import 'package:aqueduct/src/http/resource_controller_bindings.dart';
import 'package:aqueduct/src/http/resource_controller_interfaces.dart';
import 'package:aqueduct/src/runtime/resource_controller/documenter.dart';
import 'package:aqueduct/src/runtime/resource_controller_impl.dart';
import 'package:aqueduct/src/utilities/sourcify.dart';
import 'package:runtime/runtime.dart';

String getInvokerSource(BuildContext context,
    ResourceControllerRuntimeImpl controller, ResourceControllerOperation op) {
  final buf = StringBuffer();
  final subclassName = MirrorSystem.getName(controller.type.simpleName);

  buf.writeln("(rc, args) {");
  buf.writeln("  return (rc as $subclassName).${op.dartMethodName}(");

  var counter = 0;
  op.positionalParameters.forEach((p) {
    buf.writeln("    args.positionalArguments[$counter] as ${p.type},");
    counter++;
  });

  op.namedParameters.forEach((p) {
    var defaultValue = sourcifyValue(p.defaultValue);

    buf.writeln(
        "    ${p.symbolName}: args.namedArguments['${p.symbolName}'] as ${p.type} ?? $defaultValue,");
  });

  buf.writeln("  );");
  buf.writeln("}");

  return buf.toString();
}

String getApplyRequestPropertiesSource(
    BuildContext context, ResourceControllerRuntimeImpl runtime) {
  StringBuffer buf = StringBuffer();
  final subclassName = MirrorSystem.getName(runtime.type.simpleName);

  runtime.ivarParameters.forEach((f) {
    buf.writeln("(untypedController as $subclassName).${f.symbolName} "
        "= args.instanceVariables['${f.symbolName}'] as ${f.type};");
  });

  return buf.toString();
}

String getResourceControllerImplSource(
    BuildContext context, ResourceControllerRuntimeImpl runtime) {
  final ivarSources = runtime.ivarParameters
      .map((i) => getParameterSource(context, runtime, i))
      .join(",\n");
  final operationSources = runtime.operations
      .map((o) => getOperationSource(context, runtime, o))
      .join(",\n");

  return """
class ResourceControllerRuntimeImpl extends ResourceControllerRuntime {
  ResourceControllerRuntimeImpl() {
    ivarParameters = [$ivarSources];
    operations = [$operationSources];
  }    
  
  void applyRequestProperties(ResourceController untypedController,
    ResourceControllerOperationInvocationArgs args) {
    ${getApplyRequestPropertiesSource(context, runtime)}
  }
}
  """;
}

String getDecoderSource(
    BuildContext context,
    ResourceControllerRuntimeImpl runtime,
    ResourceControllerParameter parameter) {
  switch (parameter.location) {
    case BindingType.path:
      {
        return getElementDecoderSource(parameter.type);
      }
      break;
    case BindingType.header:
      {
        return getListDecoderSource(parameter);
      }
      break;
    case BindingType.query:
      {
        return getListDecoderSource(parameter);
      }
      break;
    case BindingType.body:
      {
        return getBodyDecoderSource(parameter);
      }
      break;
  }
  throw StateError("unknown parameter");
}

String sourcifyFilter(List<String> filter) {
  if (filter == null) {
    return "null";
  }

  return "[${filter?.map((s) => "'$s'")?.join(",")}]";
}

String getBodyDecoderSource(ResourceControllerParameter p) {
  final ignore = sourcifyFilter(p.ignoreFilter);
  final reject = sourcifyFilter(p.rejectFilter);
  final require = sourcifyFilter(p.requireFilter);
  final accept = sourcifyFilter(p.acceptFilter);
  if (isSerializable(p.type)) {
    return """(v) {
    return ${p.type}()
      ..read((v as RequestBody).as(), 
           accept: $accept,
           ignore: $ignore,
           reject: $reject,
           require: $require);
    }
    """;
  } else if (isListSerializable(p.type)) {
    return """ (b) {
      final body = b as RequestBody;
      final bodyList = body.as<List<Map<String, dynamic>>>();
      if (bodyList.isEmpty) {
        return ${p.type}.from([]);         
      }

      final iterable = bodyList.map((object) {
        return ${reflectType(p.type).typeArguments.first.reflectedType}()
          ..read(object,
            accept: $accept,
            ignore: $ignore,
            reject: $reject,
            require: $require);
      }).toList();

      return ${p.type}.from(iterable);       
    }""";
  }

  return """(b) { 
    return (b as RequestBody).as<${p.type}>();
  }""";
}

String getElementDecoderSource(Type type) {
  final className = "${type}";
  if (reflectType(type).isSubtypeOf(reflectType(bool))) {
    return "(v) { return true; }";
  } else if (reflectType(type).isSubtypeOf(reflectType(String))) {
    return "(v) { return v as String; }";
  }

  return """(v) {
  try {
    return $className.parse(v as String);
  } catch (_) {
    throw ArgumentError("invalid value");
  }
}
      """;
}

String getListDecoderSource(ResourceControllerParameter p) {
  if (reflectType(p.type).isSubtypeOf(reflectType(List))) {
    final mapper = getElementDecoderSource(
      reflectType(p.type).typeArguments.first.reflectedType);
    return """(v) {
  return ${p.type}.from((v as List).map($mapper));  
}  """;
  }

  return """(v) {
  final listOfValues = v as List;
  if (listOfValues.length > 1) {
    throw ArgumentError("multiple values not expected");
  }
  return ${getElementDecoderSource(p.type)}(listOfValues.first);
}  
  """;
}

String getParameterSource(
    BuildContext context,
    ResourceControllerRuntimeImpl runtime,
    ResourceControllerParameter parameter) {
  return """
ResourceControllerParameter.make<${parameter.type}>(
  name: ${sourcifyValue(parameter.name)},
  acceptFilter: ${sourcifyFilter(parameter.acceptFilter)},
  ignoreFilter: ${sourcifyFilter(parameter.ignoreFilter)},
  rejectFilter: ${sourcifyFilter(parameter.rejectFilter)},
  requireFilter: ${sourcifyFilter(parameter.requireFilter)},  
  symbolName: ${sourcifyValue(parameter.symbolName)},
  location: ${sourcifyValue(parameter.location)},
  isRequired: ${sourcifyValue(parameter.isRequired)},
  defaultValue: ${sourcifyValue(parameter.defaultValue)},
  decoder: ${getDecoderSource(context, runtime, parameter)})
  """;
}

String getOperationSource(
    BuildContext context,
    ResourceControllerRuntimeImpl runtime,
    ResourceControllerOperation operation) {
  final scopeElements = operation.scopes?.map((s) => "AuthScope(${sourcifyValue(s.toString())})")?.join(",");
  final namedParameters = operation.namedParameters
      .map((p) => getParameterSource(context, runtime, p))
      .join(",");
  final positionalParameters = operation.positionalParameters
      .map((p) => getParameterSource(context, runtime, p))
      .join(",");
  final pathVars = operation.pathVariables.map((s) => "'$s'").join(",");

  return """
ResourceControllerOperation(
  positionalParameters: [$positionalParameters],
  namedParameters: [$namedParameters],
  scopes: ${operation.scopes == null ? null : "[$scopeElements]"},
  dartMethodName: ${sourcifyValue(operation.dartMethodName)},
  httpMethod: ${sourcifyValue(operation.httpMethod)},
  pathVariables: [$pathVars],
  invoker: ${getInvokerSource(context, runtime, operation)})  
  """;
}
