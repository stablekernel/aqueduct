import 'dart:mirrors';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/runtime/orm/entity_builder.dart';
import 'package:aqueduct/src/utilities/mirror_cast.dart';
import 'package:aqueduct/src/utilities/sourcify.dart';
import 'package:runtime/runtime.dart';

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime
    implements SourceCompiler {
  ManagedEntityRuntimeImpl(this.instanceType, this.entity);

  final ClassMirror instanceType;

  @override
  final ManagedEntity entity;

  @override
  ManagedObject instanceOfImplementation({ManagedBacking backing}) {
    final object = instanceType.newInstance(const Symbol(""), []).reflectee
        as ManagedObject;
    if (backing != null) {
      object.backing = backing;
    }
    return object;
  }

  @override
  void setTransientValueForKey(
      ManagedObject object, String key, dynamic value) {
    reflect(object).setField(Symbol(key), value);
  }

  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    final type =
        reflectType(ManagedSet, [instanceType.reflectedType]) as ClassMirror;
    return type.newInstance(const Symbol("fromDynamic"), [objects]).reflectee
        as ManagedSet;
  }

  @override
  dynamic getTransientValueForKey(ManagedObject object, String key) {
    return reflect(object).getField(Symbol(key)).reflectee;
  }

  @override
  bool isValueInstanceOf(dynamic value) {
    return reflect(value).type.isAssignableTo(instanceType);
  }

  @override
  bool isValueListOf(dynamic value) {
    final type = reflect(value).type;

    if (!type.isSubtypeOf(reflectType(List))) {
      return false;
    }

    return type.typeArguments.first.isAssignableTo(instanceType);
  }

  @override
  String getPropertyName(Invocation invocation, ManagedEntity entity) {
    // It memberName is not in symbolMap, it may be because that property doesn't exist for this object's entity.
    // But it also may occur for private ivars, in which case, we reconstruct the symbol and try that.
    return entity.symbolMap[invocation.memberName] ??
        entity.symbolMap[Symbol(MirrorSystem.getName(invocation.memberName))];
  }

  @override
  dynamic dynamicConvertFromPrimitiveValue(
      ManagedPropertyDescription property, dynamic value) {
    return runtimeCast(value, reflectType(property.type.type));
  }

  String _getValidatorConstructionFromAnnotation(BuildContext buildCtx,
      Annotation annotation, ManagedPropertyDescription property) {
    // For every annotation, grab the name of the type and find the corresponding type mirror in our list of type mirrors.
    // Documentation mismatch: `annotation.name.name` is NOT the class name, it is the entire constructor name.
    final typeOfAnnotationName = annotation.name.name.split(".").first;
    final mirrorOfAnnotationType = buildCtx.context.types.firstWhere(
        (t) => MirrorSystem.getName(t.simpleName) == typeOfAnnotationName,
        orElse: () => null);

    // todo joeconwaystk
    // NEXT STEP
    // FOr each WILL IMPORT print statement (3 total?)
    // we actuallyneed to import that uri in the generated source file
    // and

    String validatorSource;
    if (mirrorOfAnnotationType?.isSubtypeOf(reflectType(Validate)) ?? false) {
      // If the annotation is a const Validate instantiation, we just copy it directly.
      print("WILL IMPORT (a): ${annotation.element.source.uri}");
      validatorSource = "[${annotation.toSource().substring(1)}]";
    } else if (mirrorOfAnnotationType?.isSubtypeOf(reflectType(Column)) ??
        false) {
      // This is a direct column constructor and potentially has instances of Validate in its constructor
      // We should be able to navigate the unresolved AST to copy this text.
      validatorSource =
          _getValidatorArgExpressionFromColumnArgList(annotation.arguments)
              ?.toSource();
      if (validatorSource == null) {
        return null;
      }
    } else if (mirrorOfAnnotationType == null) {
      // Then this is not a const constructor - there is no type - it is a
      // instance (pointing at a const constructor) e.g. @primaryKey.
      final element = annotation.elementAnnotation?.element;
      if (element is! PropertyAccessorElement) {
        return null;
      }

      final type = (element as PropertyAccessorElement).variable.type;
      final isSubclassOfValidate = buildCtx.context
          .getSubclassesOf(Validate)
          .any((subclass) =>
              MirrorSystem.getName(subclass.simpleName) ==
              type.getDisplayString());
      final isSubclassOfColumm = type.getDisplayString() == "Column";

      if (isSubclassOfValidate) {
        print("WILL IMPORT (b): ${annotation.element.source.uri}");
        validatorSource = "[${annotation.toSource().substring(1)}]";
      } else if (isSubclassOfColumm) {
        // todo: for each validator in the arg list, import its source uri
        final originatingLibrary =
            element.session.getParsedLibraryByElement(element.library);
        final elementDeclaration = originatingLibrary
            .getElementDeclaration(
                (element as PropertyAccessorElement).variable)
            .node as VariableDeclaration;

        final args = _getValidatorArgExpressionFromColumnArgList(
            (elementDeclaration.initializer as MethodInvocation).argumentList);

        if (args == null) {
          return null;
        }

        validatorSource = args.toSource();
      }

      // If it was something other than what we expected, so bail out
      return null;
    } else {
      return null;
    }

    final inverseType = property is ManagedRelationshipDescription
        ? "${property.destinationEntity.instanceType}"
        : "null";
    // Once we have the const instantiation source, return a code snippet that instantiates all of the validation objects.
    return """() {
  return $validatorSource.map((v) {
    final state = v.compile(${_getManagedTypeInstantiator(property.type)}, relationshipInverseType: $inverseType);
    return ManagedValidator(v, state);
  });  
}()""";
  }

  String _getValidators(
      BuildContext context, ManagedPropertyDescription property) {
    // For the property we are looking at, grab all of its annotations from the analyzer.
    // We also have all of the instances created by these annotations available in some
    // way or another in the [property].
    final fieldAnnotations = context.getAnnotationsFromField(
        EntityBuilder.getTableDefinitionForType(property.entity.instanceType)
            .reflectedType,
        property.name);

    return fieldAnnotations
        .map((annotation) => _getValidatorConstructionFromAnnotation(
            context, annotation, property))
        .where((s) => s != null)
        .join(",");
  }

  Expression _getValidatorArgExpressionFromColumnArgList(ArgumentList argList) {
    return argList.arguments
        .whereType<NamedExpression>()
        .firstWhere((c) => c.name.label.name == "validators",
            orElse: () => null)
        ?.expression;
  }

  String _getManagedTypeInstantiator(ManagedType type) {
    if (type == null) {
      return "null";
    }

    final elementStr = type.elements == null
        ? "null"
        : _getManagedTypeInstantiator(type.elements);

    final enumStr = type.enumerationMap == null
        ? "null"
        : "{${type.enumerationMap.keys.map((k) {
            var vStr = sourcifyValue(type.enumerationMap[k]);
            return "'$k': $vStr";
          }).join(",")}}";

    return "ManagedType.make<${type.type}>(${type.kind}, $elementStr, $enumStr)";
  }

  String _getDefaultValueLiteral(ManagedAttributeDescription attribute) {
    final value = attribute.defaultValue;
    return sourcifyValue(value,
        onError:
            "The default value for '${attribute.entity.instanceType}.${attribute.name}' "
            "contains both double and single quotes");
  }

  String _getAttributeInstantiator(
      BuildContext ctx, ManagedAttributeDescription attribute) {
    final transienceStr = attribute.isTransient
        ? "Serialize(input: ${attribute.transientStatus.isAvailableAsInput}, output: ${attribute.transientStatus.isAvailableAsOutput})"
        : null;
    final validatorStr =
        attribute.isTransient ? "[]" : "[${_getValidators(ctx, attribute)}]";

    return """
ManagedAttributeDescription.make<${attribute.declaredType}>(entity, '${attribute.name}',
    ${_getManagedTypeInstantiator(attribute.type)}, 
    transientStatus: $transienceStr,
    primaryKey: ${attribute.isPrimaryKey},
    defaultValue: ${_getDefaultValueLiteral(attribute)},
    unique: ${attribute.isUnique},
    indexed: ${attribute.isIndexed},
    nullable: ${attribute.isNullable},
    includedInDefaultResultSet: ${attribute.isIncludedInDefaultResultSet},
    autoincrement: ${attribute.autoincrement},
    validators: $validatorStr.expand<ManagedValidator>((i) => i as Iterable<ManagedValidator>).toList())    
    """;
  }

  String _getRelationshipInstantiator(
      BuildContext ctx, ManagedRelationshipDescription relationship) {
    return """
ManagedRelationshipDescription.make<${relationship.declaredType}>(
  entity,
  '${relationship.name}',
  ${_getManagedTypeInstantiator(relationship.type)},
  dataModel.entities.firstWhere((e) => e.name == '${relationship.destinationEntity.name}'),
  ${relationship.deleteRule},
  ${relationship.relationshipType},
  '${relationship.inverseKey}',
  unique: ${relationship.isUnique},
  indexed: ${relationship.isIndexed},
  nullable: ${relationship.isNullable},
  includedInDefaultResultSet: ${relationship.isIncludedInDefaultResultSet},
  validators: [${_getValidators(ctx, relationship)}].expand<ManagedValidator>((i) => i as Iterable<ManagedValidator>).toList())
    """;
  }

  String _getEntityConstructor(BuildContext context) {
    final attributesStr = entity.attributes.keys.map((name) {
      return "'$name': ${_getAttributeInstantiator(context, entity.attributes[name])}";
    }).join(", ");

    final uniqueStr = entity.uniquePropertySet == null
        ? "null"
        : "[${entity.uniquePropertySet.map((u) => "'${u.name}'").join(",")}].map((k) => entity.attributes[k]).toList()";

    final symbolMapBuffer = StringBuffer();
    entity.properties.forEach((str, val) {
      final sourcifiedKey = sourcifyValue(str);
      symbolMapBuffer.write("Symbol($sourcifiedKey): $sourcifiedKey,");
      symbolMapBuffer
          .write("Symbol(${sourcifyValue("$str=")}): $sourcifiedKey,");
    });

    final tableDef =
        EntityBuilder.getTableDefinitionForType(entity.instanceType)
            .reflectedType
            .toString();

    return """() {    
final entity = ManagedEntity('${entity.tableName}', ${entity.instanceType}, ${sourcifyValue(tableDef)});
return entity    
    ..primaryKey = '${entity.primaryKey}'
    ..symbolMap = {${symbolMapBuffer.toString()}}
    ..attributes = {$attributesStr};    
}()""";
  }

  String _getSetTransientValueForKeyImpl(BuildContext ctx) {
    final cases = entity.attributes.values
        .where((attr) => attr.isTransient)
        .where((attr) => attr.transientStatus.isAvailableAsInput)
        .map((attr) {
      return "case '${attr.name}': (object as ${instanceType.reflectedType}).${attr.name} = value as ${attr.declaredType}; break;";
    }).join("\n");

    return """switch (key) {
    $cases
}""";
  }

  String _getGetTransientValueForKeyImpl(BuildContext ctx) {
    final cases = entity.attributes.values
        .where((attr) => attr.isTransient)
        .where((attr) => attr.transientStatus.isAvailableAsOutput)
        .map((attr) {
      return "case '${attr.name}': return (object as ${instanceType.reflectedType}).${attr.name};";
    }).join("\n");

    return """switch (key) {
    $cases
}""";
  }

  String _getDynamicConvertFromPrimitiveValueImpl(BuildContext ctx) {
    return """/* this needs to be improved to use the property's type to fix the implementation */
return value;
    """;
  }

  String _getGetPropertyNameImpl(BuildContext ctx) {
    return """final name = entity.symbolMap[invocation.memberName];
if (name != null) {
  return name;
}

final invocationMemberNameAsString = invocation.memberName.toString();
final idxUnderscore = invocationMemberNameAsString.indexOf("_");
if (idxUnderscore < 0) {
  return null;
}
final idxEnd = invocationMemberNameAsString.indexOf("\\")");
if (idxEnd < 0) {
  return null;
}
final symbolName = invocationMemberNameAsString.substring(idxUnderscore, idxEnd);

return entity.symbolMap[Symbol(symbolName)];
""";
  }

  @override
  String compile(BuildContext ctx) {
    final className = "${MirrorSystem.getName(instanceType.simpleName)}";
    final originalFileUri = instanceType.location.sourceUri.toString();
    final relationshipsStr = entity.relationships.keys.map((name) {
      return "'$name': ${_getRelationshipInstantiator(ctx, entity.relationships[name])}";
    }).join(", ");

    final uniqueStr = entity.uniquePropertySet == null
        ? "null"
        : "[${entity.uniquePropertySet.map((u) => "'${u.name}'").join(",")}].map((k) => entity.properties[k]).toList()";

    // Need to import any relationships...
    final directives = entity.relationships.values.map((r) {
      var mirror = reflectType(r.declaredType);
      if (mirror.isSubtypeOf(reflectType(ManagedSet))) {
        mirror = mirror.typeArguments.first;
      }

      final uri = mirror.location.sourceUri;
      return "import '$uri' show ${mirror.reflectedType};";
    }).join("\n");

    return """
import 'package:aqueduct/aqueduct.dart';
import '$originalFileUri';
$directives

final instance = ManagedEntityRuntimeImpl();

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl() {
   _entity = ${_getEntityConstructor(ctx)};
  }

  ManagedEntity _entity;

  @override
  ManagedEntity get entity => _entity; 

  @override
  void finalize(ManagedDataModel dataModel) {
    _entity.relationships = {$relationshipsStr};
    _entity.validators = [];
    _entity.validators.addAll(_entity.attributes.values.expand((a) => a.validators));
    _entity.validators.addAll(_entity.relationships.values.expand((a) => a.validators));
    
    entity.uniquePropertySet = $uniqueStr;
  }

  @override
  ManagedObject instanceOfImplementation({ManagedBacking backing}) {
    final object = $className();
    if (backing != null) {
      object.backing = backing;
    }
    return object;
  }
  
  @override
  void setTransientValueForKey(ManagedObject object, String key, dynamic value) {
    ${_getSetTransientValueForKeyImpl(ctx)}
  }
  
  @override
  ManagedSet setOfImplementation(Iterable<dynamic> objects) {
    return ManagedSet<$className>.fromDynamic(objects); 
  }
  
  @override
  dynamic getTransientValueForKey(ManagedObject object, String key) {
    ${_getGetTransientValueForKeyImpl(ctx)}
  }
  
  @override
  bool isValueInstanceOf(dynamic value) {
    return value is $className;
  }
  
  @override
  bool isValueListOf(dynamic value) {
    return value is List<$className>;
  }
  
  @override
  String getPropertyName(Invocation invocation, ManagedEntity entity) {
    ${_getGetPropertyNameImpl(ctx)}    
  }
  
  @override
  dynamic dynamicConvertFromPrimitiveValue(ManagedPropertyDescription property, dynamic value) {
    ${_getDynamicConvertFromPrimitiveValueImpl(ctx)}  
  }
}   
    """;
  }
}
