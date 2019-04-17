import 'dart:mirrors';

import 'package:aqueduct/src/openapi/documentable.dart';
import 'package:aqueduct/src/utilities/mirror_helpers.dart';
import 'package:open_api/v3.dart';

import '../request.dart';
import '../response.dart';
import '../serializable.dart';
import 'internal.dart';

/// Parent class for annotations used for optional parameters in controller methods
abstract class BoundInput {
  BoundInput(this.boundType, this.externalName);

  /// The name of the variable in the HTTP request.
  final String externalName;

  /// The type of the bound variable.
  final ClassMirror boundType;

  String get type;

  APIParameterLocation get location;

  void validate() {
    if (boundType.isAssignableTo(reflectType(List))) {
      _enforceTypeCanBeParsedFromString(boundType.typeArguments.first);
    } else {
      _enforceTypeCanBeParsedFromString(boundType);
    }
  }

  dynamic decode(Request request);

  dynamic convertParameterListWithMirror(
      List<String> parameterValues, TypeMirror typeMirror) {
    if (parameterValues == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(List))) {
      final iterable = parameterValues.map((str) =>
          convertParameterWithMirror(str, typeMirror.typeArguments.first));

      return (typeMirror as ClassMirror)
          .newInstance(#from, [iterable]).reflectee;
    } else {
      if (parameterValues.length > 1) {
        throw Response.badRequest(body: {
          "error": "multiple values for '$externalName' not expected"
        });
      }
      return convertParameterWithMirror(parameterValues.first, typeMirror);
    }
  }

  dynamic convertParameterWithMirror(
      String parameterValue, TypeMirror typeMirror) {
    if (parameterValue == null) {
      return null;
    }

    if (typeMirror.isSubtypeOf(reflectType(bool))) {
      return true;
    }

    if (typeMirror.isSubtypeOf(reflectType(String))) {
      return parameterValue;
    }

    final classMirror = typeMirror as ClassMirror;
    var parseDecl = classMirror.declarations[#parse];
    if (parseDecl == null) {
      throw StateError(
          "Invalid binding. Type '${MirrorSystem.getName(classMirror.simpleName)}' does not implement 'parse'.");
    }

    try {
      return classMirror
          .invoke(parseDecl.simpleName, [parameterValue]).reflectee;
    } catch (_) {
      throw Response.badRequest(
          body: {"error": "invalid value for '$externalName'"});
    }
  }
}

class BoundValue {
  BoundValue(this.value, {this.symbol});

  BoundValue.deferred(this.deferredBinder, {this.symbol});

  BoundValue.error(this.errorMessage);

  Symbol symbol;
  dynamic value;
  BoundParameter deferredBinder;
  String errorMessage;
}

class BoundPath extends BoundInput {
  BoundPath(ClassMirror typeMirror, String segment)
      : super(typeMirror, segment);

  @override
  String get type => "Path";

  @override
  APIParameterLocation get location => APIParameterLocation.path;

  @override
  dynamic decode(Request request) {
    return convertParameterWithMirror(
        request.path.variables[externalName], boundType);
  }
}

class BoundHeader extends BoundInput {
  BoundHeader(ClassMirror typeMirror, String header)
      : super(typeMirror, header);

  @override
  String get type => "Header";

  @override
  APIParameterLocation get location => APIParameterLocation.header;

  @override
  dynamic decode(Request request) {
    var value = request.raw.headers[externalName];
    return convertParameterListWithMirror(value, boundType);
  }
}

class BoundQueryParameter extends BoundInput {
  BoundQueryParameter(ClassMirror typeMirror, String key)
      : super(typeMirror, key);

  @override
  String get type => "Query Parameter";

  @override
  APIParameterLocation get location => APIParameterLocation.query;

  @override
  void validate() {
    final isListOfBools = boundType.isAssignableTo(reflectType(List)) &&
        boundType.typeArguments.first.isAssignableTo(reflectType(bool));

    if (boundType.isAssignableTo(reflectType(bool)) || isListOfBools) {
      return;
    }

    super.validate();
  }

  @override
  dynamic decode(Request request) {
    var queryParameters = request.raw.uri.queryParametersAll;
    var value = queryParameters[externalName];
    if (value == null) {
      if (requestHasFormData(request)) {
        value = request.body.as<Map<String, List<String>>>()[externalName];
      }
    }

    return convertParameterListWithMirror(value, boundType);
  }
}

class BoundBody extends BoundInput implements APIComponentDocumenter {
  BoundBody(ClassMirror typeMirror,
      {List<String> ignore, List<String> error, List<String> required})
      : ignoreFilter = ignore,
        errorFilter = error,
        requiredFilter = required,
        super(typeMirror, null);

  final List<String> ignoreFilter;
  final List<String> errorFilter;
  final List<String> requiredFilter;

  @override
  String get type => "Body";

  @override
  APIParameterLocation get location => null;

  bool get _isBoundToSerializable =>
      boundType.isSubtypeOf(reflectType(Serializable));

  bool get _isBoundToListOfSerializable =>
      boundType.isSubtypeOf(reflectType(List)) &&
      boundType.typeArguments.first.isSubtypeOf(reflectType(Serializable));

  @override
  void validate() {
    if (ignoreFilter != null || errorFilter != null || requiredFilter != null) {
      if (!(_isBoundToSerializable || _isBoundToListOfSerializable)) {
        throw 'Filters can only be used on Serializable or List<Serializable>.';
      }
    }
  }

  @override
  dynamic decode(Request request) {
    if (request.body.isEmpty) {
      return null;
    }

    if (_isBoundToSerializable) {
      final value =
          boundType.newInstance(const Symbol(""), []).reflectee as Serializable;
      value.read(request.body.as(),
          ignore: ignoreFilter, reject: errorFilter, require: requiredFilter);

      return value;
    } else if (_isBoundToListOfSerializable) {
      final bodyList = request.body.as<List<Map<String, dynamic>>>();
      if (bodyList.isEmpty) {
        return boundType.newInstance(#from, [[]]).reflectee;
      }

      final typeArg = boundType.typeArguments.first as ClassMirror;
      final iterable = bodyList.map((object) {
        final value =
            typeArg.newInstance(const Symbol(""), []).reflectee as Serializable;
        value.read(object,
            ignore: ignoreFilter, reject: errorFilter, require: requiredFilter);

        return value;
      }).toList();

      final v = boundType.newInstance(#from, [iterable]).reflectee;
      return v;
    }

    return runtimeCast(request.body.as(), boundType);
  }

  @override
  void documentComponents(APIDocumentContext context) {
    if (_isBoundToSerializable) {
      _registerType(context, boundType);
    } else if (_isBoundToListOfSerializable) {
      _registerType(context, boundType.typeArguments.first);
    }
  }

  APISchemaObject getSchemaObjectReference(APIDocumentContext context) {
    if (_isBoundToListOfSerializable) {
      return APISchemaObject.array(
          ofSchema: context.schema
              .getObjectWithType(boundType.typeArguments.first.reflectedType));
    } else if (_isBoundToSerializable) {
      return context.schema.getObjectWithType(boundType.reflectedType);
    }

    return null;
  }

  static void _registerType(APIDocumentContext context, TypeMirror typeMirror) {
    if (typeMirror is! ClassMirror) {
      return;
    }

    final classMirror = typeMirror as ClassMirror;
    if (!context.schema.hasRegisteredType(classMirror.reflectedType) &&
        _shouldDocumentSerializable(classMirror.reflectedType)) {
      final instance = classMirror.newInstance(const Symbol(''), []).reflectee
          as Serializable;
      context.schema.register(MirrorSystem.getName(classMirror.simpleName),
          instance.documentSchema(context),
          representation: classMirror.reflectedType);
    }
  }

  static bool _shouldDocumentSerializable(Type type) {
    final hierarchy = classHierarchyForClass(reflectClass(type));
    final definingType = hierarchy.firstWhere(
        (cm) => cm.staticMembers.containsKey(#shouldAutomaticallyDocument),
        orElse: () => null);
    if (definingType == null) {
      return Serializable.shouldAutomaticallyDocument;
    }
    return definingType.getField(#shouldAutomaticallyDocument).reflectee
        as bool;
  }
}

void _enforceTypeCanBeParsedFromString(TypeMirror typeMirror) {
  if (typeMirror is! ClassMirror) {
    throw 'Cannot bind dynamic type parameters.';
  }

  if (typeMirror.isAssignableTo(reflectType(String))) {
    return;
  }

  final classMirror = typeMirror as ClassMirror;
  if (!classMirror.staticMembers.containsKey(#parse)) {
    throw 'Parameter type does not implement static parse method.';
  }

  final parseMethod = classMirror.staticMembers[#parse];
  final params = parseMethod.parameters.where((p) => !p.isOptional).toList();
  if (params.length == 1 &&
      params.first.type.isAssignableTo(reflectType(String))) {
    return;
  }

  throw 'Invalid parameter type.';
}
