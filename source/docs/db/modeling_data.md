# Modeling Data

In this guide, you will learn how to create `ManagedObject<T>` subclasses that can be stored in and retrieved from a database.

## Defining a Table

In your application, you define types whose instances can be stored in a database. Each type you create for this purpose corresponds to a database table. The properties of these types are columns of the corresponding table. Instances of these types represent a row in that table.

For example, consider a `Article` type. When you create articles and store them in a database, they are inserted into an 'article' table. That table has a column to store the properties of the article, like its category and contents. Each individual article is a row in this table.

A type that can be stored in a database is created by declaring two classes. The first class is a *table definition*. A table definition is a plain Dart type that represents a table in the database. Each property of a table definition type is a column in that database. These properties often have annotations to further define the behavior of the column. An example looks like this:

```dart
// This is a table definition of an 'article'
class _Article {
  @primaryKey
  int id;

  String contents;

  @Column(indexed: true)
  String category;
}
```

This class declares a table named `_Article` with three columns:

- `id`: an integer column that is the primary key of the table
- `contents`: a text column
- `category`: a text column that has an index so that it can more efficiently be searched

A property's type determines the type of column in the table.

| Dart Type | General Column Type | PostgreSQL Column Type |
|-----------|---------------|------|
| `int` | integer number | `INT` or `SERIAL` |
| `double` | floating point number | `DOUBLE PRECISION` |
| `String` | text | `TEXT` |
| `DateTime` | timestamp | `TIMESTAMP` |
| `bool` | boolean | `BOOLEAN` |
| `Document` | a JSON object or array | `JSONB` |
| Any `enum` | text, restricted to enum cases | `TEXT` |

Some types can be represented by many database types; for example, an integer can be stored as 2, 4 or 8 bytes. The `Column` annotation can be applied to a table definition's property to further specify the type. This same annotation allows for the customization of indices, uniqueness and other column behavior. Available options are optional arguments to the `Column` constructor and shown in the following table:

| Option | Type | Behavior | Default |
| ------ | ---- | -------- | ------- |
| primaryKey | `bool` | sets primary key column | false (not primary key) |
| databaseType | `ManagedPropertyType` | sets underlying column type | inferred from Dart type |
| nullable | `bool` | toggles whether column can be null | false (not nullable) |
| unique | `bool` | toggles whether column is unique across all rows | false (not unique) |
| defaultValue | `String` | provides default value for new rows when value is undefined | null |
| indexed | `bool` | whether an index should be created for the column | false (no index) |
| omitByDefault | `bool` | whether this column should be fetched by default | true (fetch column value) |
| autoincrement | `bool` | whether this column's value is automatically generated from a series | false (not generated) |

Exactly one property per table definition must have a `Column` annotation with the 'primary key' option. That property's column is the primary key of the database table. It is common for primary keys to be 64-bit, auto-incrementing integers; therefore, the `primaryKey` constant exists as a convenience for a `Column` with these options. The `_Article` type from above is equivalent to:

```dart
// This is a table definition of an 'article'
class _Article {
  @Column(primaryKey: true, databaseType: ManagedPropertyType.bigInteger, autoincrement: true)
  int id;

  String contents;

  @Column(indexed: true)
  String category;
}
```

!!! note "Creating Tables"
    Tables are created in a database by using the `aqueduct` command line tool to generate and execute migration scripts. The tool inspects your database types and automatically synchronizes a databases schema to match your them.

The ORM assumes that a database table has the same name as a table definition, i.e. the `_Article` table definition instructs the ORM that there is a table named `_Article`. You may provide another name with the `@Table` annotation on the table definition.


```dart
@Table(name: "ArticleTable")
class _Article {
  @primaryKey
  int id;

  String contents;

  @Column(indexed: true)
  String category;
}
```

## Defining an Instance Type

Alongside the table definition, you must create an *instance type*. An instance type is used in your application code. It must be a subclass of `ManagedObject<T>` *and* implement `T`, where `T` is your table definition. The instance type for `_Article` is declared like so:

```dart
class Article extends ManagedObject<_Article> implements _Article {}
```

This `Article` instance type inherits all of the properties from the `_Article` table definition; i.e., an `Article` has an `id`, `contents` and `category`. You create instances of an instance type like any other type.

```dart
final article = new Article();
article.id = 1;
article.category = "Baseball";
```

When you fetch rows from a database, you will be returned instances of your instance type that are automatically created for you by the ORM.

!!! warning "Instance Type Constructors"
    You can add new constructors to an instance type, but you must always have a default, no-argument constructor that properly instantiates your object. This default constructor is used when the ORM creates instances from rows in your database.

### Transient Properties

An instance type can declare additional properties and methods. Any property declared in the instance type is *not* stored in the database, and are often used for computed or derived values for an object. Properties declared on the instance type are called *transient properties*.

For example, consider an `Author` type whose table definition stores first and last name as separate columns. Instead of redundantly storing a 'full name' in the database, a transient property can be derived from properties stored in the database:

```dart
class Author extends ManagedObject<_Author> implements _Author {
  String get name => "$firstName $lastName";
  set name(String fullName) {
    firstName = fullName.split(" ").first;
    lastName = fullName.split(" ").last;
  }
}
class _Author {
  @primaryKey
  int id;

  String firstName;
  String lastName;
}
```

Transient properties don't necessarily have to access columns of the underlying table, but note that if an object has a transient property, that value is not available on another object that represents the same row.

By default, a transient property is ignored when reading an object from a request body or writing the object to a response body. You can annotate a transient property with `Serialize` so that it is able to be read from a request body, written to a response body, or both. The following allows `name` to be both read and written over HTTP:

```dart
class Author extends ManagedObject<_Author> implements _Author {
  @Serialize()
  String get name => "$firstName $lastName";

  @Serialize()
  set name(String fullName) {
    firstName = fullName.split(" ").first;
    lastName = fullName.split(" ").last;
  }
}
```

## Project Structure

The combination of an instance type and its table definition is called an *entity*. Each entity should be declared in the same file, and the table definition should be prefixed with an `_` to prevent it from being used elsewhere in the project. It is preferable to declare one entity per file, and store all entities in the `lib/model/` directory of your project.

The files your model definitions are declared in must be visible to Aqueduct tooling. In normal circumstances, this happens automatically because of the following:

1. Aqueduct tooling can find any file that is imported (directly or transitively) from your library file.
2. Your library file, by default, can see the file your `ApplicationChannel` is declared in.
3. Your application channel file must import any controller that it links.
4. Your controllers must import any model file they use.

When you use the `aqueduct` CLI to generate database migration scripts, it will report all of the `ManagedObject`s in your application that it was able to find. If a particular type is not listed, it may reveal that you aren't using that type. If you need to ensure that the tooling can see a particular model file that it is not locating, you may import it in your `channel.dart` file.

## Modeling Relationships

So far, we've shown that table definitions can declare scalar properties like integers and strings, and that those properties are backed by a column in a database table. These types of properties are called *attributes*. Table definitions may also contain *relationship* properties that are references to another entity in your application.

For example, an `Author` can have a property that holds all of the `Article`s they have written. There are two types of relationships: *has-many* and *has-one*. A has-one relationship restricts a relationship to a single object (e.g., an author may have one article), whereas a has-many relationship allows for any number of related objects (e.g., an author has multiple articles).

Relationship properties are also declared in a table definition. The type of the property must either be a `ManagedSet<T>` or a `T`, where `T` is another instance type. If the type is `ManagedSet<T>`, the relationship is a has-many relationship, otherwise, it is a has-one relationship. The following shows an `articles` relationship that allows an author to have many `Article`s:

```dart
class _Author {
  @primaryKey
  int id;

  String name;

  // a has-many relationship to Article
  ManagedSet<Article> articles;

  // If we were declaring a has-one relationship:
  // Article article;
}
```

A `ManagedSet` is a special type of `List` used in the Aqueduct ORM. It can do everything a list can do, but adds some additional behavior for the ORM.

All relationships must have an inverse. For example, if an author has articles, an article must have an author. This is true regardless of whether or not the relationship is has-many or has-one. An inverse is declared in the related table definition with a `Relate` annotation:

```dart
class _Article {
  @primaryKey
  int id;

  @Relate(#articles)
  Author author;

  ...
}
```

A relationship property with this annotation is neither has-one or has-many; it *belongs to* the related entity. The argument to `Relate` is the symbolic name of the property on the 'has' side of the relationship. In our examples, an author has many articles, and an article belongs to an author.

!!! note "Symbols"
    A symbol is a name identifier in Dart; a symbol can refer to a class, method, or property. Symbols are objects can be instantiated like all objects, but the `#` identifier is shorthand for creating a symbol.

Only one side of a relationship may have the `Relate` annotation on its relationship property. The property with this annotation is a *foreign key column* on the table definition it is defined in. In this example, the `_Article` table has a foreign key reference to the `id` of the `_Author` table.

Choosing which side of the relationship has the `Relate` annotation depends on how you wish to model your data. In has-many relationships, this is easy - a `ManagedSet<T>` may *not* have the `Relate` annotation. In a has-one relationship, you must determine which side of the relationship should have the foreign key reference.

When making this decision, it is important to understand how objects are fetched with `Query`s. In a default query, the objects that are returned will contain 'null' for every 'has' relationship, and only contain the foreign key of any 'belongs to' relationships. To fetch a related object in its entirety, you must use `Query.join`.

!!! note "Foreign Keys"
    The foreign key column always references the primary key of the related table, and its name is derived by combining the name of the relationship property and the primary key of the related table. For example, the above definitions would add a column named `author_id` to the `_Article` table.

The `Relate` annotation has optional arguments to further define the relationship.

A relationship may be be required or optional. For example, if `Article.author` were required, than an `Article` must always have an `Author`. By default, relationships are optional.

A relationship has a delete rule. When an object is deleted, any objects that belong to its relationships are subject to this rule. The following table shows the rules and their behavior:

| Rule | Behavior | Example |
| ---- | -------- | ------- |
| nullify (default) | inverse is set to null | When deleting an author, its articles' author becomes null |
| cascade | related objects are also deleted | When deleting an author, its articles are deleted |
| restrict | delete fails | When attempting to delete an author with articles, the delete operation fails |
| default | inverse set to a default value | When deleting an author, its articles author is set to the default value of the column |

### Example: One-to-Many Relationship

An author has many books:

```dart
class Author extends ManagedObject<_Author> implements _Author {}
class _Author {
  @primaryKey
  int id;

  String name;

  ManagedSet<Book> books;
}

class Book extends ManagedObject<_Book> implements _Book {}
class _Book {
  @primaryKey
  int id;

  String name;

  @Relate(#books)
  Author author;
}
```

To insert an author and a book associated with that author:

```dart
final authorQuery = Query<Author>(context)
  ..values.name = "Fred";
final author = await authorQuery.insert();

final bookQuery = Query<Author>(context)
  ..values.name = "Title"
  ..values.author.id = author.id;
final book = await bookQuery.insert();  
```

To fetch authors and their books:

```dart
final query = Query<Author>(context)
  ..join(set: (a) => a.books);
final authors = await query.fetch();
```

To fetch a book and their full author object:

```dart
final query = Query<Book>(context)
  ..where((b) => b.id).equalTo(1)
  ..join(object: (a) => a.author);
final books = await query.fetch();
```

### Example: One-to-One Relationship

```dart
class Country extends ManagedObject<_Country> implements _Country {}
class _Country {
  @primaryKey
  int id;

  String name;

  City capital;
}

class City extends ManagedObject<_City> implements _City {}
class _City {
  @primaryKey
  int id;

  String name;

  @Relate(#capital)
  Country country;
}
```

To fetch a country and its capital:

```dart
final query = Query<Country>(context)
  ..where((c) => c.id).equalTo(1)
  ..join(object: (a) => a.capital);
final countries = await query.fetch();
```

### Example: Many-to-Many Relationship

```dart
class Team extends ManagedObject<_Team> implements _Team {}
class _Team {
  @primaryKey
  int id;

  String name;

  ManagedSet<TeamPlayer> teamPlayers;
}

// This type is a join table
class _TeamPlayer extends ManagedObject<_TeamPlayer> implements _TeamPlayer {}
class _TeamPlayer {
  @primaryKey
  int id;  

  @Relate(#players)
  Team team;

  @Relate(#team)
  Player player;
}

class Player extends ManagedObject<_Player> implements _Player {}
class _Player {
  @primaryKey
  int id;

  String name;

  ManagedSet<TeamPlayer> teamPlayers;
}
```

To fetch a team and its players:

```dart
// Note that the final join is not cascaded from the Team query,
// but from the Query created by joining with TeamPlayer
final query = Query<Team>(context)
  ..where((t) => t.id).equalTo(1)
  ..join(set: (t) => t.teamPlayers).join(object: (tp) => tp.player);
final team = await query.fetchOne();
```

The structure of this object is:

```json
{
  "id": 1,
  "name": "Badgers",
  "teamPlayers": [
    {
      "id": 1,
      "team": {
        "id": 1
      },
      "player": {
        "id": 1,
        "name": "Fred"
      }
    }
  ]
}
```

You can flatten this structure in a number of ways. In the simplest form, add a `Serialize`-annotated transient property to the `ManagedObject` subclass, and each time you fetch, remove the join table from the object and place the players in the transient property.

```dart
class Team extends ManagedObject<_Team> implements _Team {
  @Serialize(input: false, output: true)
  List<Player> players;
}

final team = ...;
team.players = team.teamPlayers.map((t) => t.player).toList();
// Remove teamPlayers; it is redundant
team.backing.removeProperty("teamPlayers");
```

## Additional Data Modeling

This section covers additional features when defining your data model.

### Enum Types

When a table definition property is an `enum` type, the enumeration is stored as a string in the database. Consider the following definition where a user can be an admin or a normal user:

```dart
enum UserType {
  admin, user
}

class User extends ManagedObject<_User> implements _User {}
class _User {
  @primaryKey
  int id;

  String name;

  UserType type;
}
```

You may assign valid enumeration cases to the `User.type` property:

```dart
var query = Query<User>(context)
  ..values.name = "Bob"
  ..values.type = UserType.admin;
var bob = await query.insert();

query = Query<User>(context)
  ..where((u) => u.type).equalTo(UserType.admin);
var allAdmins = await query.fetch();
```

In the database, the `type` column is stored as a string. Its value is either "admin" or "user" - which is derived from the two enumeration case names. A enumerated type property has an implicit `Validate.oneOf` validator that asserts the value is one of the valid enumeration cases.

### Private Variables

A property of a table definition that is Dart private (prefixed with an `_`) will not be included when writing a `ManagedObject<T>` to an HTTP response. It also may not be read from an HTTP request body. This behavior differs slightly from the `omitByDefault` flag of `Column`. When omitting by default, the value is simply not fetched from the database. When a property is private, it is fetched, but it is just not accessible from outside the object. This can be useful when combined with transient accessors. For example, the following ensures that the `title` property is uppercased before storage:

```dart
class User extends ManagedObject<_User> implements _User {
  @Serialize()
  set title(String title) {
    _title = title.toUpperCase();
  }

  @Serialize()
  String get title => _title;
}

class _User {
  String _title;

  ...
}
```
