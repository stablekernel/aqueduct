# Aqueduct IntellIJ IDEA Templates

For convenience in creating files and writing common code, the following IntelliJ IDEA templates are available:

## File Templates

- Aqueduct HTTPController
    - Creates a new file with the skeleton of an `HTTPController`.
- Aqueduct ManagedObject
    - Creates a new file with the skeleton of a `ManagedObject` subclass
- Aqueduct Test
    - Creates a new file that imports a test harness and implementations for setting up and tearing down a `TestApplication`.

After [installation](#installation), file templates are available through any IntellIJ IDEA interface for creating files when the project has been enabled to use the Dart plugin.

## Live Templates

- 'bindmethod'
    - Enters a skeleton of an `HTTPController` operation method - after insertion, enter the HTTP method to finish the method declaration.
- 'bindheader'  
    - Enters an `@Bind.header` binding - after insertion, enter the name of the header.
- 'bindquery'
    - Enters an `@Bind.query` binding - after insertion, enter the name of the query parameter.

## Installation

Download the [this file](https://s3.amazonaws.com/aqueduct-intellij/aqueduct.jar) and import it into IntelliJ by selecting `Import Settings...` from the `File` menu.
