import 'auth.dart';

/// Represents a Client ID and secret pair.
class AuthClient {
  /// Creates an instance of [AuthClient].
  AuthClient(this.id, this.hashedSecret, this.salt);

  // Creates an instance of [Client] that uses the authorization code grant flow.
  AuthClient.withRedirectURI(
      this.id, this.hashedSecret, this.salt, this.redirectURI);

  /// The ID of the client.
  String id;

  /// The hashed secret of the client.
  String hashedSecret;

  /// The salt the hashed secret was hashed with.
  String salt;

  /// The redirection URI for authorization codes and/or tokens.
  String redirectURI;

  bool get isPublic => hashedSecret == null;
  bool get isConfidential => hashedSecret != null;

  String toString() {
    return "AuthClient (${isPublic ? "public" : "confidental"}): $id $redirectURI";
  }
}

/// An interface to represent [AuthServer.TokenType].
///
/// Requires that all fields be set... except refreshToken which may be null. And scopes
/// which may be null if scopes are unsupported.
/// In order to use authentication tokens, an [AuthServer] requires
/// that its [AuthServer.TokenType] implement this interface. You will likely use
/// this interface to define a [ManagedObject] that represents the concrete implementation of a authentication
/// token in your application. All of these properties are expected to be persisted.
class AuthToken {
  /// The value to be passed as a Bearer Authorization header.
  String accessToken;

  /// The value to be passed for refreshing an expired (or not yet expired) token.
  String refreshToken;

  /// The timestamp this token was issued on.
  DateTime issueDate;

  /// When this token expires.
  DateTime expirationDate;

  /// The type of token, currently only 'bearer' is valid.
  String type;

  /// The identifier of the resource owner.
  ///
  /// Tokens are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The clientID this token was issued under.
  String clientID;

//  List<AuthScope> scope;

  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }

  Map<String, dynamic> asMap() {
    var map = {
      "access_token": accessToken,
      "token_type": type,
      "expires_in": expirationDate.difference(new DateTime.now().toUtc()).inSeconds,
    };

    if (refreshToken != null) {
      map["refresh_token"] = refreshToken;
    }

    return map;
  }
}

/// An interface for implementing [AuthServer.AuthCodeType].
///
/// In order to use authorization codes, an [AuthServer] requires
/// that its [AuthServer.AuthCodeType] implement this interface. You will likely use
/// this interface to define a [ManagedObject] that represents a concrete implementation
/// of a authorization code in your application. All of these properties are expected to be persisted.
class AuthCode {
  /// The actual one-time code used to exchange for tokens.
  String code;

  /// The clientID the authorization code was issued under.
  String clientID;

  /// The identifier of the resource owner.
  ///
  /// Authorization codes are owned by a resource owner, typically a User, Profile or Account
  /// in an application. This value is the primary key or identifying value of those
  /// instances.
  dynamic resourceOwnerIdentifier;

  /// The timestamp this authorization code was issued on.
  DateTime issueDate;

  /// When this authorization code expires, recommended for 10 minutes after issue date.
  DateTime expirationDate;

  bool hasBeenExchanged;

  bool get isExpired {
    return expirationDate.difference(new DateTime.now().toUtc()).inSeconds <= 0;
  }
}

/// Authorization information to be attached to a [Request].
///
/// When a [Request] passes through an [Authorizer] and is validated,
/// the [Authorizer] attaches an instance of [Authorization] to its [Request.authorization].
/// Subsequent [RequestController]s are able to use this information to determine access scope.
class Authorization {
  /// Creates an instance of a [Authorization].
  Authorization(
      this.clientID, this.resourceOwnerIdentifier, this.validator);

  /// The client ID the permission was granted under.
  final String clientID;

  /// The identifier for the owner of the resource.
  ///
  /// If a [Request] has a Bearer token, this will be the primary key value of the [ManagedObject]
  /// for which the Bearer token was associated with. If the [Request] was signed with
  /// a Client ID and secret, this value will be [null].
  final dynamic resourceOwnerIdentifier;

  /// The [AuthValidator] that granted this permission.
  final AuthValidator validator;
}

class AuthScope {
  AuthScope(String scopeString) {
    _segments = _parse(scopeString);
    _lastModifier = _segments.last.modifier;
  }

  List<_AuthScopeSegment> _segments;
  String _lastModifier;

  List<_AuthScopeSegment> _parse(String scopeString) {
    if (scopeString == null || scopeString == "") {
      throw new FormatException("Invalid AuthScope. May not be null or empty string.", scopeString);
    }

    var elements = scopeString
       .split(":")
       .map((seg) => new _AuthScopeSegment(seg))
       .toList();

    var scannedOffset = 0;
    for (var i = 0; i < elements.length - 1; i++) {
      if (elements[i].modifier != null) {
        throw new FormatException("Invalid AuthScope. May only contain modifiers on the last segment.", scopeString, scannedOffset);
      }

      if (elements[i].name == "") {
        throw new FormatException("Invalid AuthScope. May not contain empty segments or, leading or trailing colons.", scopeString, scannedOffset);
      }

      scannedOffset += elements[i].toString().length + 1;
    }

    if (elements.last.name == "") {
      throw new FormatException("Invalid AuthScope. May not contain empty segments.", scopeString, scannedOffset);
    }

    return elements;
  }

  bool allowsScope(AuthScope incomingScope) {
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
    var thisIterator = _segments.iterator;
    for (var incomingSegment in incomingScope._segments) {
      thisIterator.moveNext();
      var current = thisIterator.current;

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

  bool allows(String scopeString) {
    return allowsScope(new AuthScope(scopeString));
  }

  bool isExactlyScope(AuthScope scope) {
    var incomingIterator = scope._segments.iterator;
    for (var segment in _segments) {
      incomingIterator.moveNext();
      var incomingSegment = incomingIterator.current;
      if (incomingSegment == null) {
        return false;
      }

      if (incomingSegment.name != segment.name
      || incomingSegment.modifier != segment.modifier) {
        return false;
      }
    }

    return true;
  }

  bool isExactly(String scopeString) {
    return isExactlyScope(new AuthScope(scopeString));
  }
}

class _AuthScopeSegment {
  _AuthScopeSegment(String segment) {
    var split = segment.split(".");
    if (split.length == 2) {
      name = split.first;
      modifier = split.last;
    } else {
      name = segment;
    }
  }

  String name;
  String modifier;

  String toString() {
    if (modifier == null) {
      return name;
    }
    return "$name.$modifier";
  }
}