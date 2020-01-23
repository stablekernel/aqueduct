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
      throw CastError();
    }

    final elementType = intoType.typeArguments.first;
    final elements = (object as List).map((e) => runtimeCast(e, elementType));
    return (intoType as ClassMirror).newInstance(#from, [elements]).reflectee;
  } else if (intoType.isSubtypeOf(reflectType(Map, [String, dynamic]))) {
    if (object is! Map<String, dynamic>) {
      throw CastError();
    }

    final output = (intoType as ClassMirror)
        .newInstance(const Symbol(""), []).reflectee as Map<String, dynamic>;
    final valueType = intoType.typeArguments.last;
    (object as Map<String, dynamic>).forEach((key, val) {
      output[key] = runtimeCast(val, valueType);
    });
    return output;
  }

  throw CastError();
}
