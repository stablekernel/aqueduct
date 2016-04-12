part of monadart;

abstract class ConfigurationItem {
  void loadConfigurationFromString(String contents) {
    var config = loadYaml(contents);
    _setItemsFromYaml(config);
  }

  void loadConfigurationFile(String name) {
    var yamlContents = new File(name).readAsStringSync();
    loadConfigurationFromString(yamlContents);
  }

  void set subItem(dynamic item) {
    _setItemsFromYaml(item);
  }

  void _setItemsFromYaml(dynamic items) {
    var reflectedThis = reflect(this);
    reflectedThis.type.declarations.forEach((sym, decl) {
      if (decl is! VariableMirror) {
        return;
      }

      VariableMirror variableMirror = decl;
      var value = items[MirrorSystem.getName(sym)];

      if (value == null && isVariableRequired(sym, variableMirror)) {
        throw new ConfigurationException("${MirrorSystem.getName(sym)} is required but was not found in configuration.");
      }

      _readConfigurationItem(sym, variableMirror, value);
    });
  }

  bool isVariableRequired(Symbol symbol, VariableMirror m) {
    ConfigurationItemAttribute attribute = m.metadata
        .firstWhere((im) => im.type.isSubtypeOf(reflectType(ConfigurationItemAttribute)), orElse: () => null)
        ?.reflectee;

    return attribute == null || attribute.type == ConfigurationItemAttributeType.required;
  }

  void _readConfigurationItem(Symbol symbol, VariableMirror mirror, dynamic value) {
    var reflectedThis = reflect(this);

    var decodedValue = null;
    if (mirror.type.isSubtypeOf(reflectType(ConfigurationItem))) {
      decodedValue = _decodedConfigurationItem(mirror.type, value);
    } else if (mirror.type.isSubtypeOf(reflectType(List))) {
      decodedValue = _decodedConfigurationList(mirror.type, value);
    } else if (mirror.type.isSubtypeOf(reflectType(Map))) {
      decodedValue = _decodedConfigurationMap(mirror.type, value);
    } else {
      decodedValue = value;
    }

    reflectedThis.setField(symbol, decodedValue);
  }

  dynamic _decodedConfigurationItem(TypeMirror typeMirror, dynamic value) {
    ConfigurationItem newInstance = (typeMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
    newInstance.subItem = value;
    return newInstance;
  }

  List<dynamic> _decodedConfigurationList(TypeMirror typeMirror, YamlList value) {
    var decoder = (v) {
      return v;
    };

    if (typeMirror.typeArguments.first.isSubtypeOf(reflectType(ConfigurationItem))) {
      var innerClassMirror = typeMirror.typeArguments.first as ClassMirror;
      decoder = (v) {
        ConfigurationItem newInstance = (innerClassMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
        newInstance.subItem = v;
        return newInstance;
      };
    }

    return value.map(decoder).toList();
  }

  Map<String, dynamic> _decodedConfigurationMap(TypeMirror typeMirror, YamlMap value) {
    var decoder = (v) {
      return v;
    };

    if (typeMirror.typeArguments.last.isSubtypeOf(reflectType(ConfigurationItem))) {
      var innerClassMirror = typeMirror.typeArguments.last as ClassMirror;
      decoder = (v) {
        ConfigurationItem newInstance = (innerClassMirror as ClassMirror).newInstance(new Symbol(""), []).reflectee;
        newInstance.subItem = v;
        return newInstance;
      };
    }

    var map = {};
    value.keys.forEach((k) {
      map[k] = decoder(value[k]);
    });
    return map;
  }

  dynamic noSuchMethod(Invocation i) {
    return null;
  }
}

enum ConfigurationItemAttributeType {
  required, // Default
  optional
}
class ConfigurationItemAttribute {
  const ConfigurationItemAttribute(this.type);

  final ConfigurationItemAttributeType type;
}

const ConfigurationItemAttribute requiredConfiguration = const ConfigurationItemAttribute(ConfigurationItemAttributeType.required);
const ConfigurationItemAttribute optionalConfiguration = const ConfigurationItemAttribute(ConfigurationItemAttributeType.optional);

class ConfigurationException {
  ConfigurationException(this.message);

  String message;

  String toString() {
    return "ConfigurationException: $message";
  }
}

class DatabaseConnectionConfiguration extends ConfigurationItem {
  DatabaseConnectionConfiguration();
  DatabaseConnectionConfiguration.withConnectionInfo(this.username, this.password, this.host, this.port, this.databaseName, {bool temporary: false}) {
    isTemporary = temporary;
  }
  String host;
  int port;
  String databaseName;

  @optionalConfiguration
  String username;
  @optionalConfiguration
  String password;
  @optionalConfiguration
  bool isTemporary;

}

class APIConfiguration extends ConfigurationItem {
  String baseURL;

  @optionalConfiguration
  String clientID;

  @optionalConfiguration
  String clientSecret;
}