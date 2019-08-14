import '../http/request.dart';
import 'auth.dart';

/// Represents an OAuth 2.0 client ID and secret pair.
///
/// See the aqueduct/managed_auth library for a concrete implementation of this type.
///
/// Use the command line tool `aqueduct auth` to create instances of this type and store them to a database.
class AuthClient {
  /// Creates an instance of [AuthClient].
  ///
  /// [id] must not be null. [hashedSecret] and [salt] must either both be null or both be valid values. If [hashedSecret] and [salt]
  /// are valid values, this client is a confidential client. Otherwise, the client is public. The terms 'confidential' and 'public'
  /// are described by the OAuth 2.0 specification.
  ///
  /// If this client supports scopes, [allowedScopes] must contain a list of scopes that tokens may request when authorized
  /// by this client.
  AuthClient(String id, String hashedSecret, String salt,
      {List<AuthScope> allowedScopes})
      : this.withRedirectURI(id, hashedSecret, salt, null,
            allowedScopes: allowedScopes);

  /// Creates an instance of a public [AuthClient].
  AuthClient.public(String id, {List<AuthScope> allowedScopes})
      : this.withRedirectURI(id, null, null, null,
            allowedScopes: allowedScopes);

  /// Creates an instance of [AuthClient] that uses the authorization code grant flow.
  ///
  /// All values must be non-null. This is confidential client.
  AuthClient.withRedirectURI(
      this.id, this.hashedSecret, this.salt, this.redirectURI,
      {List<AuthScope> allowedScopes}) {
    this.allowedScopes = allowedScopes;
  }

  List<AuthScope> _allowedScopes;

  /// The ID of the client.
  String id;

  /// The hashed secret of the client.
  ///
  /// This value may be null if the client is public. See [isPublic].
  String hashedSecret;

  /// The salt [hashedSecret] was hashed with.
  ///
  /// This value may be null if the client is public. See [isPublic].
  String salt;

  /// The redirection URI for authorization codes and/or tokens.
  ///
  /// This value may be null if the client doesn't support the authorization code flow.
  String redirectURI;

  /// The list of scopes available when authorizing with this client.
  ///
  /// Scoping is determined by this instance; i.e. the authorizing client determines which scopes a token
  /// has. This list contains all valid scopes for this client. If null, client does not support scopes
  /// and all access tokens have same authorization.
  List<AuthScope> get allowedScopes => _allowedScopes;
  set allowedScopes(List<AuthScope> scopes) {
    _allowedScopes = scopes?.where((s) {
      return !scopes.any((otherScope) =>
          s.isSubsetOrEqualTo(otherScope) && !s.isExactlyScope(otherScope));
    })?.toList();
  }

  /// Whether or not this instance allows scoping or not.
  ///
  /// In application's that do not use authorization scopes, this will return false.
  /// Otherwise, will return true.
  bool get supportsScopes => allowedScopes != null;

  /// Whether or not this client can issue tokens for the provided [scope].
  bool allowsScope(AuthScope scope) {
    return allowedScopes
            ?.any((clientScope) => scope.isSubsetOrEqualTo(clientScope)) ??
        false;
  }

  /// Whether or not this is a public or confidential client.
  ///
  /// Public clients do not have a client secret and are used for clients that can't store
  /// their secret confidentially, i.e. JavaScript browser applications.
  bool get isPublic => hashedSecret == null;

  /// Whether or not this is a public or confidential client.
  ///
  /// Confidential clients have a client secret that must be used when authenticating with
  /// a client-authenticated request. Confidential clients are used when you can
  /// be sure that the client secret cannot be viewed by anyone outside of the developer.
  bool get isConfidential => hashedSecret != null;

  @override
  String toString() {
    return "AuthClient (${isPublic ? "public" : "confidental"}): $id $redirectURI";
  }
}

/// Represents an OAuth 2.0 token.
///
/// [AuthServerDelegate] and [AuthServer] will exchange OAuth 2.0
/// tokens through instances of this type.
///
/// See the `package:aqueduct/managed_auth` library for a concrete implementation of this type.
class AuthToken {
  /// The value to be passed as a Bearer Authorization header.
  String accessToken;

  /// The value to be passed for refreshing a token.
  String refreshToken;

  /// The time this token was issued on.
  DateTime issueDate;

  /// The time when this token expires.
  DateTime expirationDate;

  /// The type of token, currently only 'bearer' is valid.
  String type;

  /// The identifier of the resource owner.
  ///
  /// Tokens are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  int resourceOwnerIdentifier;

  /// The client ID this token was issued from.
  String clientID;

  /// Scopes this token has access to.
  List<AuthScope> scopes;

  /// Whether or not this token is expired by evaluated [expirationDate].
  bool get isExpired {
    return expirationDate.difference(DateTime.now().toUtc()).inSeconds <= 0;
  }

  /// Emits this instance as a [Map] according to the OAuth 2.0 specification.
  Map<String, dynamic> asMap() {
    final map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in": expirationDate.difference(DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    if (scopes != null) {
      map["scope"] = scopes.map((s) => s.toString()).join(" ");
    }

    return map;
  }
}

/// Represents an OAuth 2.0 authorization code.
///
/// [AuthServerDelegate] and [AuthServer] will exchange OAuth 2.0
/// authorization codes through instances of this type.
///
/// See the aqueduct/managed_auth library for a concrete implementation of this type.
class AuthCode {
  /// The actual one-time code used to exchange for tokens.
  String code;

  /// The client ID the authorization code was issued under.
  String clientID;

  /// The identifier of the resource owner.
  ///
  /// Authorization codes are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  int resourceOwnerIdentifier;

  /// The timestamp this authorization code was issued on.
  DateTime issueDate;

  /// When this authorization code expires, recommended for 10 minutes after issue date.
  DateTime expirationDate;

  /// Whether or not this authorization code has already been exchanged for a token.
  bool hasBeenExchanged;

  /// Scopes the exchanged token will have.
  List<AuthScope> requestedScopes;

  /// Whether or not this code has expired yet, according to its [expirationDate].
  bool get isExpired {
    return expirationDate.difference(DateTime.now().toUtc()).inSeconds <= 0;
  }
}

/// Authorization information for a [Request] after it has passed through an [Authorizer].
///
/// After a request has passed through an [Authorizer], an instance of this type
/// is created and attached to the request (see [Request.authorization]). Instances of this type contain the information
/// that the [Authorizer] obtained from an [AuthValidator] (typically an [AuthServer])
/// about the validity of the credentials in a request.
class Authorization {
  /// Creates an instance of a [Authorization].
  Authorization(this.clientID, this.ownerID, this.validator,
      {this.credentials, this.scopes});

  /// The client ID the permission was granted under.
  final String clientID;

  /// The identifier for the owner of the resource, if provided.
  ///
  /// If this instance refers to the authorization of a resource owner, this value will
  /// be its identifying value. For example, in an application where a 'User' is stored in a database,
  /// this value would be the primary key of that user.
  ///
  /// If this authorization does not refer to a specific resource owner, this value will be null.
  final int ownerID;

  /// The [AuthValidator] that granted this permission.
  final AuthValidator validator;

  /// Basic authorization credentials, if provided.
  ///
  /// If this instance represents the authorization header of a request with basic authorization credentials,
  /// the parsed credentials will be available in this property. Otherwise, this value is null.
  final AuthBasicCredentials credentials;

  /// The list of scopes this authorization has access to.
  ///
  /// If the access token used to create this instance has scope,
  /// those scopes will be available here. Otherwise, null.
  List<AuthScope> scopes;

  /// Whether or not this instance has access to a specific scope.
  ///
  /// This method checks each element in [scopes] for any that gives privileges
  /// to access [scope].
  bool isAuthorizedForScope(String scope) {
    final asScope = AuthScope(scope);
    return scopes?.any(asScope.isSubsetOrEqualTo) ?? false;
  }
}

/// Instances represent OAuth 2.0 scope.
///
/// An OAuth 2.0 token may optionally have authorization scopes. An authorization scope provides more granular
/// authorization to protected resources. Without authorization scopes, any valid token can pass through an
/// [Authorizer.bearer]. Scopes allow [Authorizer]s to restrict access to routes that do not have the
/// appropriate scope values.
///
/// An [AuthClient] has a list of valid scopes (see `aqueduct auth` tool). An access token issued for an [AuthClient] may ask for
/// any of the scopes the client provides. Scopes are then granted to the access token. An [Authorizer] may specify
/// a one or more required scopes that a token must have to pass to the next controller.
class AuthScope {
  /// Creates an instance of this type from [scopeString].
  ///
  /// A simple authorization scope string is a single keyword. Valid characters are
  ///
  ///         A-Za-z0-9!#\$%&'`()*+,./:;<=>?@[]^_{|}-.
  ///
  /// For example, 'account' is a valid scope. An [Authorizer] can require an access token to have
  /// the 'account' scope to pass through it. Access tokens without the 'account' scope are unauthorized.
  ///
  /// More advanced scopes may contain multiple segments and a modifier. For example, the following are valid scopes:
  ///
  ///     user
  ///     user:settings
  ///     user:posts
  ///     user:posts.readonly
  ///
  /// Segments are delimited by the colon character (`:`). Segments allow more granular scoping options. Each segment adds a
  /// restriction to the segment prior to it. For example, the scope `user`
  /// would allow all user actions, whereas `user:settings` would only allow access to a user's settings. Routes that are secured
  /// to either `user:settings` or `user:posts.readonly` are accessible by an access token with `user` scope. A token with `user:settings`
  /// would not be able to access a route limited to `user:posts`.
  ///
  /// A modifier is an additional restrictive measure and follows scope segments and the dot character (`.`). A scope may only
  /// have one modifier at the very end of the scope. A modifier can be any string, as long as its characters are in the above
  /// list of valid characters. A modifier adds an additional restriction to a scope, without having to make up a new segment.
  /// An example is the 'readonly' modifier above. A route that requires `user:posts.readonly` would allow passage when the token
  /// has `user`, `user:posts` or `user:posts.readonly`. A route that required `user:posts` would not allow `user:posts.readonly`.
  factory AuthScope(String scopeString) {
    final cached = _cache[scopeString];
    if (cached != null) {
      return cached;
    }

    final scope = AuthScope._parse(scopeString);
    _cache[scopeString] = scope;
    return scope;
  }

  factory AuthScope._parse(String scopeString) {
    if (scopeString?.isEmpty ?? true) {
      throw FormatException(
          "Invalid AuthScope. May not be null or empty string.", scopeString);
    }

    for (var c in scopeString.codeUnits) {
      if (!(c == 33 || (c >= 35 && c <= 91) || (c >= 93 && c <= 126))) {
        throw FormatException(
            "Invalid authorization scope. May only contain "
            "the following characters: A-Za-z0-9!#\$%&'`()*+,./:;<=>?@[]^_{|}-",
            scopeString,
            scopeString.codeUnits.indexOf(c));
      }
    }

    final segments = _parseSegments(scopeString);
    final lastModifier = segments.last.modifier;

    return AuthScope._(scopeString, segments, lastModifier);
  }

  const AuthScope._(this._scopeString, this._segments, this._lastModifier);

  /// Signifies 'any' scope in [AuthServerDelegate.getAllowedScopes].
  ///
  /// See [AuthServerDelegate.getAllowedScopes] for more details.
  static const List<AuthScope> any = [
    AuthScope._("_scope:_constant:_marker", [], null)
  ];

  /// Returns true if that [providedScopes] fulfills [requiredScopes].
  ///
  /// For all [requiredScopes], there must be a scope in [requiredScopes] that meets or exceeds
  /// that scope for this method to return true. If [requiredScopes] is null, this method
  /// return true regardless of [providedScopes].
  static bool verify(
      List<AuthScope> requiredScopes, List<AuthScope> providedScopes) {
    if (requiredScopes == null) {
      return true;
    }

    return requiredScopes.every((requiredScope) {
      final tokenHasValidScope = providedScopes
          ?.any((tokenScope) => requiredScope.isSubsetOrEqualTo(tokenScope));

      return tokenHasValidScope ?? false;
    });
  }

  static final Map<String, AuthScope> _cache = {};

  final String _scopeString;

  /// Individual segments, separated by `:` character, of this instance.
  ///
  /// Will always have a length of at least 1.
  Iterable<String> get segments => _segments.map((s) => s.name);

  /// The modifier of this scope, if it exists.
  ///
  /// If this instance does not have a modifier, returns null.
  String get modifier => _lastModifier;

  final List<_AuthScopeSegment> _segments;
  final String _lastModifier;

  static List<_AuthScopeSegment> _parseSegments(String scopeString) {
    if (scopeString == null || scopeString == "") {
      throw FormatException(
          "Invalid AuthScope. May not be null or empty string.", scopeString);
    }

    final elements =
        scopeString.split(":").map((seg) => _AuthScopeSegment(seg)).toList();

    var scannedOffset = 0;
    for (var i = 0; i < elements.length - 1; i++) {
      if (elements[i].modifier != null) {
        throw FormatException(
            "Invalid AuthScope. May only contain modifiers on the last segment.",
            scopeString,
            scannedOffset);
      }

      if (elements[i].name == "") {
        throw FormatException(
            "Invalid AuthScope. May not contain empty segments or, leading or trailing colons.",
            scopeString,
            scannedOffset);
      }

      scannedOffset += elements[i].toString().length + 1;
    }

    if (elements.last.name == "") {
      throw FormatException(
          "Invalid AuthScope. May not contain empty segments.",
          scopeString,
          scannedOffset);
    }

    return elements;
  }

  /// Whether or not this instance is a subset or equal to [incomingScope].
  ///
  /// The scope `users:posts` is a subset of `users`.
  ///
  /// This check is used to determine if an [Authorizer] can allow a [Request]
  /// to pass if the [Request]'s [Request.authorization] has a scope that has
  /// the same or more scope than the required scope of an [Authorizer].
  bool isSubsetOrEqualTo(AuthScope incomingScope) {
    if (incomingScope._lastModifier != null) {
      // If the modifier of the incoming scope is restrictive,
      // and this scope requires no restrictions, then it's not allowed.
      if (_lastModifier == null) {
        return false;
      }

      // If the incoming scope's modifier doesn't match this one,
      // then we also don't have access.
      if (_lastModifier != incomingScope._lastModifier) {
        return false;
      }
    }

    // If we aren't restricted by modifier, let's make sure we have access.
    final thisIterator = _segments.iterator;
    for (var incomingSegment in incomingScope._segments) {
      thisIterator.moveNext();
      final current = thisIterator.current;

      // If the incoming scope is more restrictive than this scope,
      // then it's not allowed.
      if (current == null) {
        return false;
      }

      // If we have a mismatch here, then we're going
      // down the wrong path.
      if (incomingSegment.name != current.name) {
        return false;
      }
    }

    return true;
  }

  /// Alias of [isSubsetOrEqualTo].
  @Deprecated('Use AuthScope.isSubsetOrEqualTo() instead')
  bool allowsScope(AuthScope incomingScope) => isSubsetOrEqualTo(incomingScope);

  /// String variant of [isSubsetOrEqualTo].
  ///
  /// Parses an instance of this type from [scopeString] and invokes
  /// [isSubsetOrEqualTo].
  bool allows(String scopeString) => isSubsetOrEqualTo(AuthScope(scopeString));

  /// Whether or not two scopes are exactly the same.
  bool isExactlyScope(AuthScope scope) {
    final incomingIterator = scope._segments.iterator;
    for (var segment in _segments) {
      incomingIterator.moveNext();
      final incomingSegment = incomingIterator.current;
      if (incomingSegment == null) {
        return false;
      }

      if (incomingSegment.name != segment.name ||
          incomingSegment.modifier != segment.modifier) {
        return false;
      }
    }

    return true;
  }

  /// String variant of [isExactlyScope].
  ///
  /// Parses an instance of this type from [scopeString] and invokes [isExactlyScope].
  bool isExactly(String scopeString) {
    return isExactlyScope(AuthScope(scopeString));
  }

  @override
  String toString() => _scopeString;
}

class _AuthScopeSegment {
  _AuthScopeSegment(String segment) {
    final split = segment.split(".");
    if (split.length == 2) {
      name = split.first;
      modifier = split.last;
    } else {
      name = segment;
    }
  }

  String name;
  String modifier;

  @override
  String toString() {
    if (modifier == null) {
      return name;
    }
    return "$name.$modifier";
  }
}
