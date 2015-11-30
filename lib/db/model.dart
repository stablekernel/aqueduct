part of monadart;

/// A schema definition for a Model object.
///
/// All Models must have a ModelBacking. The backing is where database properties are declared.
///
/// Example of usage:
///     @ModelBacking(UserBacking) @proxy
///     class User extends Object with Model implements UserBacking {}
///
///     class UserBacking {
///       @Attributes(primaryKey: true)
///       int id;
///     }
class ModelBacking {
  /// A plain old Dart object type, where each property is a column/field in the database.
  final Type backingType;

  /// Metadata constructor.
  const ModelBacking(this.backingType);
}

/// A database row represented as an object.
///
/// Provides dynamic backing, serialization and deserialization capabilities.
/// Model types in an application must mixin Model. A Model must declare a ModelBacking type and be a proxy.
/// Model instances are used in an application, while ModelBackings define the properties the Model has that are persisted in the database.
/// See [ModelBacking] for more details.
class Model {
  /// Applied to each value when a Model is executing [readFromMap].
  ///
  /// Defaults to [_defaultValueDecoder], which simply converts ISO8601 strings to DateTimes.
  /// [typeMirror] is the type of the model object's property. [key] is the name of the property. [value] is the value being read and assigned to the property [key].
  Function get valueDecoder => _valueDecoder;
  void set valueDecoder(
      dynamic decode(TypeMirror typeMirror, String key, dynamic value)) {
    _valueDecoder = decode;
  }
  Function _valueDecoder = _defaultValueDecoder;

  /// Applied to each value when a Model is executing [asMap].
  ///
  /// Defaults to [_defaultValueEncoder], which converts DateTime objects to ISO8601 strings.
  /// [key] is the name of the property. [value] is the value of that property.
  Function get valueEncoder => _valueEncoder;
  void set valueEncoder(dynamic encode(String key, dynamic value)) {
    _valueEncoder = encode;
  }
  Function _valueEncoder = _defaultValueEncoder;

  /// A model object's data.
  ///
  /// Model objects may be sparsely populated; when values have not been assigned to a property, the key will not exist in [dynamicBacking].
  /// A value (including null) in [dynamicBacking] for a key means the property has been set on model instance.
  Map<String, dynamic> dynamicBacking = {};

  /// A class mirror on the backing type of the Model.
  ///
  /// Defined by the Model's [ModelBacking] metadata.
  ClassMirror get backingType {
    var modelBacking = reflect(this)
        .type
        .metadata
        .firstWhere((m) => m.type.isSubtypeOf(reflectType(ModelBacking)))
        .reflectee as ModelBacking;
    return reflectClass(modelBacking.backingType);
  }

  String get primaryKey {
    var sym = backingType.declarations.values.firstWhere((dm) {
      var attr = dm.metadata.firstWhere((md) => md.reflectee is Attributes, orElse: () => null);
      if (attr == null) {
        return false;
      }

      return attr.reflectee.isPrimaryKey;
    }, orElse: () => null)?.simpleName;

    if (sym == null) {
      return null;
    }

    return MirrorSystem.getName(sym);
  }

  noSuchMethod(Invocation invocation) {
    var backingTypeDecls = this.backingType.declarations;

    if (invocation.isGetter) {
      var propertyName = MirrorSystem.getName(invocation.memberName);
      if (backingTypeDecls[invocation.memberName] == null) {
        throw new QueryException(
            500,
            "Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $propertyName.",
            -1);
      }

      if (!dynamicBacking.containsKey(propertyName)) {
        throw new QueryException(
            500,
            "Accessing property $propertyName on ${MirrorSystem.getName(reflect(this).type.simpleName)}, but is currently undefined for this instance.",
            -1);
      }

      return dynamicBacking[propertyName];
    } else if (invocation.isSetter) {
      var name = MirrorSystem.getName(invocation.memberName);
      name = name.substring(0, name.length - 1);

      var ivarDeclaration = backingTypeDecls[new Symbol(name)];
      if (ivarDeclaration == null) {
        throw new QueryException(
            500,
            "Model type ${MirrorSystem.getName(reflect(this).type.simpleName)} has no property $name.",
            -1);
      }

      var value = invocation.positionalArguments.first;
      if (value != null) {
        var ivarType = (ivarDeclaration as VariableMirror).type;
        var valueType = reflect(value).type;
        if (!valueType.isSubtypeOf(ivarType)) {
          var ivarTypeName = MirrorSystem.getName(ivarType.simpleName);
          var valueTypeName = MirrorSystem.getName(valueType.simpleName);

          throw new QueryException(
              500,
              "Type mismatch for property $name on ${MirrorSystem.getName(reflect(this).type.simpleName)}, expected $ivarTypeName but got $valueTypeName.",
              -1);
        }
      }

      dynamicBacking[name] = value;
      return null;
    }

    throw new NoSuchMethodError(this, invocation.memberName,
        invocation.positionalArguments, invocation.namedArguments);

    return null;
  }

  /// Populates the properties of a Model object from a map.
  ///
  /// Usage:
  ///     var values = JSON.decode(requestBody);
  ///     var model = new UserModel()
  ///       ..readFromMap(values);
  void readMap(Map<String, dynamic> keyValues) {
    if (dynamicBacking == null) {
      dynamicBacking = {};
    }

    keyValues.forEach((k, v) {
      var variableMirror =
          this.backingType.declarations[new Symbol(k)] as VariableMirror;

      if (variableMirror == null) {
        var reflectedThis = reflect(this);
        var sym = new Symbol(k);
        DeclarationMirror decl = reflectedThis.type.declarations[sym];

        if(decl != null && _declarationMirrorIsTransientForInput(decl)) {
          reflectedThis.setField(sym, v);
        } else {
          throw new QueryException(
            400, "Key $k does not exist for ${MirrorSystem.getName(
              reflect(this).type.simpleName)}",
            -1);
        }
      } else {
        var fieldType = variableMirror.type as ClassMirror;
        dynamicBacking[k] = _valueDecoder(fieldType, k, v);
      }
    });
  }


  bool _declarationMirrorIsTransientForInput(DeclarationMirror dm) {
    Mappable transientMetadata =  dm.metadata.firstWhere((im) => im.reflectee is Mappable, orElse: () => null)?.reflectee;

    if (transientMetadata == null || !transientMetadata.isAvailableAsInput) {
      return false;
    }

    return true;
  }

  bool _declarationMirrorIsTransientForOutput(DeclarationMirror dm) {
    Mappable transientMetadata =  dm.metadata.firstWhere((im) => im.reflectee is Mappable, orElse: () => null)?.reflectee;

    if (transientMetadata == null || !transientMetadata.isAvailableAsOutput) {
      return false;
    }

    return true;
  }


  /// Converts a model object into a serializable map.
  ///
  /// This method returns a map of the key-values pairs represented by the model object, typically then converted into a transmission format like JSON.
  ///
  /// Usage:
  ///     var json = JSON.encode(model.asMap());
  Map<String, dynamic> asMap() {
    var outputMap = {};

    dynamicBacking.forEach((k, v) {
      outputMap[k] = _valueEncoder(k, v);
    });

    var reflectedThis = reflect(this);
    reflectedThis.type.declarations.forEach((sym, decl) {
      if (_declarationMirrorIsTransientForOutput(decl)) {
        var value = reflectedThis.getField(sym).reflectee;
        if (value != null) {
          outputMap[MirrorSystem.getName(sym)] = reflectedThis.getField(sym).reflectee;
        }
      }
    });

    return outputMap;
  }

  /// The default encoder for values when converting them to a map.
  ///
  /// Embedded model objects and lists of embedded model objects will also be sent asMap().
  /// DateTime instances are converted to ISO8601 strings.
  static dynamic _defaultValueEncoder(String key, dynamic value) {
    if (value is List) {
      return (value as List)
          .map((Model innerValue) => innerValue.asMap())
          .toList();
    } else if (value is Model) {
      return (value as Model).asMap();
    }

    if (value is DateTime) {
      return (value as DateTime).toIso8601String();
    }

    return value;
  }

  /// The default decoder for values when reading from a map.
  ///
  /// ISO8601 strings are converted to DateTime instances of the type of the property as defined by [key] is DateTime.
  static dynamic _defaultValueDecoder(
      TypeMirror typeMirror, String key, dynamic value) {
    if (typeMirror.isSubtypeOf(reflectType(Model))) {
      if (value is! Map) {
        throw new QueryException(
            400,
            "Expecting a map for ${MirrorSystem.getName(typeMirror.simpleName)} in the $key field, got $value instead.",
            -1);

      }
      Model instance =
          (typeMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
      instance.readMap(value);
      return instance;
    }

    if (typeMirror.isSubtypeOf(reflectType(DateTime))) {
      return DateTime.parse(value);
    }

    return value;
  }
}

/// Possible values for a delete rule in a [RelationshipAttribute]
///
/// * [restrict] will prevent a delete operation if there is a reference to the would-be deleted object.
/// * [cascade] will delete all objects with references to this relationship.
/// * [nullify] will nullify the relationship from the related object.
/// * [setDefault] will set the relationship to its default value (if one exists) upon deletion.
enum RelationshipDeleteRule {
  restrict,
  cascade,
  nullify,
  setDefault
}

/// The different types of relationships.
///
/// In SQL terminology, the model with the [belongsTo] relationship will hold the foreign key to the inverse relationship.
/// * [hasOne] prevents the relationship from having more than one foreign key reference.
/// * [hasMany] establishes a to-many relationship to the related model.
/// * [belongsTo] is the inverse of [hasOne] and [hasMany].
enum RelationshipType {
  hasOne,
  hasMany,
  belongsTo // foreign key goes on this entity
}

/// An annotation for a Model property to indicate the values are instances of one or more Models.
///
/// To be used as metadata on a property declaration in a [ModelBacking].
class RelationshipAttribute {
  /// The type of relationship.
  ///
  /// If the type is [hasOne] or [hasMany], the inverse relationship must be [belongsTo]. Likewise, a [belongsTo] relationship must have a [hasOne] or [hasMany]
  /// inverse relationship.
  final RelationshipType type;

  /// The delete rule for this relationship.
  ///
  /// See [RelationshipDeleteRule] for possible values.
  final RelationshipDeleteRule deleteRule;

  /// The name of the property on the related object that this relationship ensures referential integrity through.
  ///
  /// By default, this will be the primary key of the related object.
  final String referenceKey;

  /// The required name of the inverse property in the related model.
  ///
  /// For example, a social network 'Post' model object
  /// would have a 'creator' property, related to the user that created it. Likewise, the User would have a 'posts' property
  /// of posts it has created. The inverseName of 'posts' on the User would be 'creator' and the inverseName of 'creator'
  /// on the Post would be 'posts'. All relationships must have an inverse.
  final String inverseKey;

  /// Constructor for relationship to be used as metadata for a model property.
  ///
  /// [type] and [inverseName] are required. All Relationships must have an inverse in the corresponding model.
  const RelationshipAttribute(RelationshipType type, String inverseKey,
      {RelationshipDeleteRule deleteRule: RelationshipDeleteRule.nullify,
      String referenceKey: null})
      : this.type = type,
        this.inverseKey = inverseKey,
        this.deleteRule = deleteRule,
        this.referenceKey = referenceKey;
}

/// A declaration annotation for the options on a property in a [ModelBacking].
///
/// By default, simply declaring a a property in a [ModelBacking] will make it a database field
/// and its persistence information will be derived from its type.
/// If, however, the property needs any of the attributes defined by this class, it should be annotated.
class Attributes {
  /// When true, indicates that this model property is the primary key.
  ///
  /// Only one property of a [ModelBacking] may have primaryKey equal to true.
  final bool isPrimaryKey;

  /// The type of the field in the database.
  ///
  /// By default, the inquirer adapter will use the appropriate type for Dart type, e.g. a Dart String is a PostgreSQL text type.
  /// This allows you to override the default type mapping for the annotated property.
  final String databaseType;

  /// Indicates whether or not the property can be null or not.
  ///
  /// By default, properties are not nullable.
  final bool isNullable;

  /// The default value of the property.
  ///
  /// By default, a property does not have a default property. This is a String to be interpreted by the adapter. Most
  /// adapters will use this string to further define the type of the database column with a default value, thus it must
  /// be flexible.
  final String defaultValue;

  /// Whether or not the property is unique among all instances.
  ///
  /// By default, properties are not unique.
  final bool isUnique;

  /// Whether or not the backing database should generate an index for this property.
  ///
  /// By default, properties are not indexed. Properties that are used often in database queries should be indexed.
  final bool isIndexed;

  /// Whether or not fetching an instance of this type should include this property.
  ///
  /// By default, all properties on a Model are returned if not specified (unless they are to-many relationship properties).
  /// This flag will remove the associated property from the result set unless it is explicitly specified by [resultKeys].
  final bool shouldOmitByDefault;

  /// The metadata constructor.
  const Attributes(
      {bool primaryKey: false,
      String databaseType,
      bool nullable: false,
      dynamic defaultValue,
      bool unique: false,
      bool indexed: false,
      bool omitByDefault: false})
      : this.isPrimaryKey = primaryKey,
        this.databaseType = databaseType,
        this.isNullable = nullable,
        this.defaultValue = defaultValue,
        this.isUnique = unique,
        this.isIndexed = indexed,
        this.shouldOmitByDefault = omitByDefault;

  /// A supporting constructor to support modifying Attributes.
  Attributes.fromAttributes(Attributes source, String databaseType)
      : this.databaseType = databaseType,
        this.isPrimaryKey = source.isPrimaryKey,
        this.isNullable = source.isNullable,
        this.defaultValue = source.defaultValue,
        this.isUnique = source.isUnique,
        this.isIndexed = source.isIndexed,
        this.shouldOmitByDefault = source.shouldOmitByDefault;
}

const Mappable mappable = const Mappable(availableAsInput: true, availableAsOutput: true);
const Mappable mappableInput = const Mappable(availableAsInput: true, availableAsOutput: false);
const Mappable mappableOutput = const Mappable(availableAsInput: false, availableAsOutput: true);

/// Metadata to associate with a property to indicate it is not a column, but is part of the Model object.
///
///
class Mappable {
  final bool isAvailableAsInput;
  final bool isAvailableAsOutput;
  const Mappable({bool availableAsInput: true, bool availableAsOutput: true}) :
    isAvailableAsInput = availableAsInput, isAvailableAsOutput = availableAsOutput;
}
