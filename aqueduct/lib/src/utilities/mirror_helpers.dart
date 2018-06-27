import 'dart:mirrors';

dynamic runtimeCast(dynamic object, TypeMirror intoType) {
  if (intoType.reflectedType == dynamic) {
    return object;
  }

  final objectType = reflect(object).type;
  if (objectType.isAssignableTo(intoType)) {
    return object;
  }

  if (intoType.isSubtypeOf(reflectType(List))) {
    if (object is! List) {
      throw new CastError();
    }

    final elementType = intoType.typeArguments.first;
    final elements = (object as List).map((e) => runtimeCast(e, elementType));
    return (intoType as ClassMirror).newInstance(#from, [elements]).reflectee;
  } else if (intoType.isSubtypeOf(reflectType(Map, [String, dynamic]))) {
    if (object is! Map<String, dynamic>) {
      throw new CastError();
    }

    final Map<String, dynamic> output = (intoType as ClassMirror).newInstance(const Symbol(""), []).reflectee;
    final valueType = intoType.typeArguments.last;
    (object as Map<String, dynamic>).forEach((key, val) {
      output[key] = runtimeCast(val, valueType);
    });
    return output;
  }

  throw new CastError();
}

dynamic firstMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata.firstWhere((im) => im.type.isSubtypeOf(tMirror), orElse: () => null)?.reflectee;
}

List<dynamic> allMetadataOfType(Type t, DeclarationMirror dm) {
  var tMirror = reflectType(t);
  return dm.metadata.where((im) => im.type.isSubtypeOf(tMirror)).map((im) => im.reflectee).toList();
}
