# Creating an Aqueduct Executable

### Beta Notes and Known Issues:

This feature is currently in beta and there are known issues.

- Windows is not currently supported due to filesystem operations that have not been tested on the OS.
- Request body decoding methods, `RequestBody.as<T>` and `RequestBody.decode<T>`, have restrictions on the their type parameters when running as an executable. These types are limited to primitive types, such as `int`, `String`, `double`, `num`, `List` (of aforementioned primitives, or `Map<String, dynamic>`) and `Map` (keys must `String`, values may be any of the aforementioned primitive types).
- There are bugs! Please report them to [the Aqueduct repository](https://github.com/stablekernel/aqueduct/issues).

## Building and Running an Executable

By default, Aqueduct runs in the Dart VM. A VM application optimizes over time and is very convenient for machines that already have Dart installed. However, VM applications are slower to startup, consume significantly more memory, and aren't as portable. Therefore, Aqueduct offers an option to build an executable version of your application. This is done by running the following command in your Aqueduct app's project directory:

```
aqueduct build
```

The output of this command is an executable that contains your application without the expensive VM. The name of the executable defaults to 'XXXXX' and is run from the command-line like any other executable:

```
  ./my_app
```

Executable's can only be run on the platform that created them. For example, you cannot create an executable in macOS and run it on Windows.

### Building Cross-Platform with Docker

-------
TBD
