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
      if (decl is VariableMirror) {
        VariableMirror variableMirror = decl;
        var value = items[MirrorSystem.getName(sym)];

        if (value == null) {
          ConfigurationItemAttribute attribute = variableMirror.metadata
              .firstWhere((im) => im.type.isSubtypeOf(reflectType(ConfigurationItemAttribute)), orElse: () => null)
              ?.reflectee;

          if (attribute == null || attribute.type == ConfigurationItemAttributeType.required) {
            throw new ConfigurationException("${MirrorSystem.getName(sym)} is required but was not found in configuration.");
          }
        } else {
          if (variableMirror.type.isSubtypeOf(reflectType(ConfigurationItem))) {
            var decodedValue = (variableMirror.type as ClassMirror).newInstance(new Symbol(""), []).reflectee;
            decodedValue.subItem = value;
            reflectedThis.setField(sym, decodedValue);
          } else {
            reflectedThis.setField(sym, value);
          }
        }
      }
    });
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
}