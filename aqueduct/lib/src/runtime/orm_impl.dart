import 'dart:mirrors';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';

import 'package:aqueduct/src/db/managed/managed.dart';
import 'package:aqueduct/src/runtime/orm/entity_builder.dart';
import 'package:aqueduct/src/utilities/sourcify.dart';
import 'package:meta/meta.dart';
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

  List<String> _getValidatorConstructionFromAnnotation(BuildContext buildCtx,
      Annotation annotation, ManagedPropertyDescription property,
      {@required List<Uri> importUris}) {
    // For every annotation, grab the name of the type and find the corresponding type mirror in our list of type mirrors.
    // Documentation mismatch: `annotation.name.name` is NOT the class name, it is the entire constructor name.
    final typeOfAnnotationName = annotation.name.name.split(".").first;
    final mirrorOfAnnotationType = buildCtx.context.types.firstWhere(
        (t) => MirrorSystem.getName(t.simpleName) == typeOfAnnotationName,
        orElse: () => null);

    // Following cases: @Validate, @Column(validators: [Validate]), or a const variable reference
    if (mirrorOfAnnotationType?.isSubtypeOf(reflectType(Validate)) ?? false) {
      // If the annotation is a const Validate instantiation, we just copy it directly
      // and import the file where the const constructor is declared.
      importUris?.add(annotation.element.source.uri);
      return [annotation.toSource().substring(1)];
    } else if (mirrorOfAnnotationType?.isSubtypeOf(reflectType(Column)) ??
        false) {
      // This is a direct column constructor and potentially has instances of Validate in its constructor
      // We should be able to navigate the unresolved AST to copy this text.
      return _getConstructorSourcesFromColumnArgList(annotation.arguments,
                  importUris: importUris)
              ?.map((c) => c)
              ?.toList() ??
          [];
    } else if (mirrorOfAnnotationType == null) {
      // Then this is not a const constructor - there is no type - it is a
      // instance (pointing at a const constructor) e.g. @primaryKey.
      final element = annotation.elementAnnotation?.element;
      if (element is! PropertyAccessorElement) {
        return [];
      }

      final type = (element as PropertyAccessorElement).variable.type;
      final isSubclassOrInstanceOfValidate = buildCtx.context
              .getSubclassesOf(Validate)
              .any((subclass) =>
                  MirrorSystem.getName(subclass.simpleName) ==
                  type.getDisplayString()) ||
          type.getDisplayString() == "Validate";
      final isInstanceOfColumn = type.getDisplayString() == "Column";

      if (isSubclassOrInstanceOfValidate) {
        importUris.add(annotation.element.source.uri);
        return [annotation.toSource().substring(1)];
      } else if (isInstanceOfColumn) {
        final originatingLibrary =
            element.session.getParsedLibraryByElement(element.library);
        final elementDeclaration = originatingLibrary
            .getElementDeclaration(
                (element as PropertyAccessorElement).variable)
            .node as VariableDeclaration;

        return _getConstructorSourcesFromColumnArgList(
                    (elementDeclaration.initializer as MethodInvocation)
                        .argumentList,
                    importUris: importUris)
                ?.map((c) => c)
                ?.toList() ??
            [];
      }
    }
    return [];
  }

  String _getValidators(
      BuildContext context, ManagedPropertyDescription property,
      {@required List<Uri> importUris}) {
    // For the property we are looking at, grab all of its annotations from the analyzer.
    // We also have all of the instances created by these annotations available in some
    // way or another in the [property].
    final fieldAnnotations = context.getAnnotationsFromField(
        EntityBuilder.getTableDefinitionForType(property.entity.instanceType)
            .reflectedType,
        property.name);

    final constructorInvocations = fieldAnnotations
        .map((annotation) => _getValidatorConstructionFromAnnotation(
            context, annotation, property,
            importUris: importUris))
        .expand((i) => i)
        .toList();

    if (property.type?.isEnumerated ?? false) {
      final enumeratedValues =
          property.type.enumerationMap.values.map(sourcifyValue).join(",");
      constructorInvocations.add('Validate.oneOf([$enumeratedValues])');
    }

    if (constructorInvocations.isEmpty) {
      return "";
    }

    final inverseType = property is ManagedRelationshipDescription
        ? "${property.destinationEntity.instanceType}"
        : "null";

    return """() {
  return [${constructorInvocations.join(",")}].map((v) {
    final state = v.compile(${_getManagedTypeInstantiator(property.type)}, relationshipInverseType: $inverseType);
    return ManagedValidator(v, state);
  });  
}()""";
  }

  List<String> _getConstructorSourcesFromColumnArgList(ArgumentList argList,
      {@required List<Uri> importUris}) {
    final expression = argList.arguments
        .whereType<NamedExpression>()
        .firstWhere((c) => c.name.label.name == "validators",
            orElse: () => null)
        ?.expression as ListLiteral;
    if (expression == null) {
      return null;
    }

    /*
    // todo: these expressions could also be a top-level var, a static const variable, and potentially others
    // we have to find out what imports are needed to support the expression
    importUris.addAll(expression.elements.map((e) {
      if (e is MethodInvocation) {
        return null;
      } else if (e is InstanceCreationExpression) {
        return e.staticElement.source.uri;
      }


      return null;
    }).where((e) => e != null));
    */

    return expression.elements.map((e) => e.toSource()).toList();
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
      BuildContext ctx, ManagedAttributeDescription attribute,
      {@required List<Uri> importUris}) {
    final transienceStr = attribute.isTransient
        ? "Serialize(input: ${attribute.transientStatus.isAvailableAsInput}, output: ${attribute.transientStatus.isAvailableAsOutput})"
        : null;
    final validatorStr = attribute.isTransient
        ? "[]"
        : "[${_getValidators(ctx, attribute, importUris: importUris)}]";

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
    size:${attribute.size},
    validators: $validatorStr.expand<ManagedValidator>((i) => i as Iterable<ManagedValidator>).toList())    
    """;
  }

  String _getRelationshipInstantiator(
      BuildContext ctx, ManagedRelationshipDescription relationship,
      {@required List<Uri> importUris}) {
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
  size:${relationship.size}
  includedInDefaultResultSet: ${relationship.isIncludedInDefaultResultSet},
  validators: [${_getValidators(ctx, relationship, importUris: importUris)}].expand<ManagedValidator>((i) => i as Iterable<ManagedValidator>).toList())
    """;
  }

  String _getEntityConstructor(BuildContext context,
      {@required List<Uri> importUris}) {
    final attributesStr = entity.attributes.keys.map((name) {
      return "'$name': ${_getAttributeInstantiator(context, entity.attributes[name], importUris: importUris)}";
    }).join(", ");

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
    final buf = StringBuffer();

    entity.properties.forEach((k, v) {
      if (v is ManagedAttributeDescription) {
        if (v.isTransient) {
          if (v.type.kind == ManagedPropertyType.list ||
              v.type.kind == ManagedPropertyType.map) {
            buf.writeln("""
            if (property.name == '$k') { return RuntimeContext.current.coerce<${v.type.type}>(value); } 
            """);
          }
        }
      }
    });

    buf.writeln(
        "throw StateError('unknown state in _getDynamicConvertFromPrimitiveValueImpl');");
    return buf.toString();
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
    final importUris = <Uri>[];

    final className = "${MirrorSystem.getName(instanceType.simpleName)}";
    final originalFileUri = instanceType.location.sourceUri.toString();
    final relationshipsStr = entity.relationships.keys.map((name) {
      return "'$name': ${_getRelationshipInstantiator(ctx, entity.relationships[name], importUris: importUris)}";
    }).join(", ");

    final uniqueStr = entity.uniquePropertySet == null
        ? "null"
        : "[${entity.uniquePropertySet.map((u) => "'${u.name}'").join(",")}].map((k) => entity.properties[k]).toList()";

    final entityConstructor =
        _getEntityConstructor(ctx, importUris: importUris);

    // Need to import any relationships types and metadata types
    // todo: limit import of importUris to only show symbols required to replicate metadata
    final directives = entity.relationships.values.map((r) {
      var mirror = reflectType(r.declaredType);
      if (mirror.isSubtypeOf(reflectType(ManagedSet))) {
        mirror = mirror.typeArguments.first;
      }

      final uri = mirror.location.sourceUri;
      return "import '$uri' show ${mirror.reflectedType};";
    }).toList()
      ..addAll(Set.from(importUris).map((uri) => "import '$uri';"));

    return """
import 'package:aqueduct/aqueduct.dart';
import 'package:runtime/runtime.dart';
import '$originalFileUri';
${directives.join("\n")}

final instance = ManagedEntityRuntimeImpl();

class ManagedEntityRuntimeImpl extends ManagedEntityRuntime {
  ManagedEntityRuntimeImpl() {
   _entity = $entityConstructor;
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
