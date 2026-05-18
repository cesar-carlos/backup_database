// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'firebird_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$FirebirdConfig {

 String get id; String get name; String get host; String get databaseFile; String get username; String get password; PortNumber get port; String? get aliasName; bool get useEmbedded; String? get clientLibraryPath; FirebirdServerVersionHint get serverVersionHint; FirebirdServiceManagerMode get serviceManagerMode; String get cryptKey; bool get enabled; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of FirebirdConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$FirebirdConfigCopyWith<FirebirdConfig> get copyWith => _$FirebirdConfigCopyWithImpl<FirebirdConfig>(this as FirebirdConfig, _$identity);





@override
String toString() {
  return 'FirebirdConfig(id: $id, name: $name, host: $host, databaseFile: $databaseFile, username: $username, password: $password, port: $port, aliasName: $aliasName, useEmbedded: $useEmbedded, clientLibraryPath: $clientLibraryPath, serverVersionHint: $serverVersionHint, serviceManagerMode: $serviceManagerMode, cryptKey: $cryptKey, enabled: $enabled, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $FirebirdConfigCopyWith<$Res>  {
  factory $FirebirdConfigCopyWith(FirebirdConfig value, $Res Function(FirebirdConfig) _then) = _$FirebirdConfigCopyWithImpl;
@useResult
$Res call({
 String id, String name, String host, String databaseFile, String username, String password, PortNumber port, String? aliasName, bool useEmbedded, String? clientLibraryPath, FirebirdServerVersionHint serverVersionHint, FirebirdServiceManagerMode serviceManagerMode, String cryptKey, bool enabled, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$FirebirdConfigCopyWithImpl<$Res>
    implements $FirebirdConfigCopyWith<$Res> {
  _$FirebirdConfigCopyWithImpl(this._self, this._then);

  final FirebirdConfig _self;
  final $Res Function(FirebirdConfig) _then;

/// Create a copy of FirebirdConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? host = null,Object? databaseFile = null,Object? username = null,Object? password = null,Object? port = null,Object? aliasName = freezed,Object? useEmbedded = null,Object? clientLibraryPath = freezed,Object? serverVersionHint = null,Object? serviceManagerMode = null,Object? cryptKey = null,Object? enabled = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,databaseFile: null == databaseFile ? _self.databaseFile : databaseFile // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,aliasName: freezed == aliasName ? _self.aliasName : aliasName // ignore: cast_nullable_to_non_nullable
as String?,useEmbedded: null == useEmbedded ? _self.useEmbedded : useEmbedded // ignore: cast_nullable_to_non_nullable
as bool,clientLibraryPath: freezed == clientLibraryPath ? _self.clientLibraryPath : clientLibraryPath // ignore: cast_nullable_to_non_nullable
as String?,serverVersionHint: null == serverVersionHint ? _self.serverVersionHint : serverVersionHint // ignore: cast_nullable_to_non_nullable
as FirebirdServerVersionHint,serviceManagerMode: null == serviceManagerMode ? _self.serviceManagerMode : serviceManagerMode // ignore: cast_nullable_to_non_nullable
as FirebirdServiceManagerMode,cryptKey: null == cryptKey ? _self.cryptKey : cryptKey // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [FirebirdConfig].
extension FirebirdConfigPatterns on FirebirdConfig {
/// A variant of `map` that fallback to returning `orElse`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _FirebirdConfig value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _FirebirdConfig() when raw != null:
return raw(_that);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// Callbacks receives the raw object, upcasted.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case final Subclass2 value:
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _FirebirdConfig value)  raw,}){
final _that = this;
switch (_that) {
case _FirebirdConfig():
return raw(_that);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `map` that fallback to returning `null`.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case final Subclass value:
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _FirebirdConfig value)?  raw,}){
final _that = this;
switch (_that) {
case _FirebirdConfig() when raw != null:
return raw(_that);case _:
  return null;

}
}
/// A variant of `when` that fallback to an `orElse` callback.
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return orElse();
/// }
/// ```

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String host,  String databaseFile,  String username,  String password,  PortNumber port,  String? aliasName,  bool useEmbedded,  String? clientLibraryPath,  FirebirdServerVersionHint serverVersionHint,  FirebirdServiceManagerMode serviceManagerMode,  String cryptKey,  bool enabled,  DateTime createdAt,  DateTime updatedAt)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _FirebirdConfig() when raw != null:
return raw(_that.id,_that.name,_that.host,_that.databaseFile,_that.username,_that.password,_that.port,_that.aliasName,_that.useEmbedded,_that.clientLibraryPath,_that.serverVersionHint,_that.serviceManagerMode,_that.cryptKey,_that.enabled,_that.createdAt,_that.updatedAt);case _:
  return orElse();

}
}
/// A `switch`-like method, using callbacks.
///
/// As opposed to `map`, this offers destructuring.
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case Subclass2(:final field2):
///     return ...;
/// }
/// ```

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String host,  String databaseFile,  String username,  String password,  PortNumber port,  String? aliasName,  bool useEmbedded,  String? clientLibraryPath,  FirebirdServerVersionHint serverVersionHint,  FirebirdServiceManagerMode serviceManagerMode,  String cryptKey,  bool enabled,  DateTime createdAt,  DateTime updatedAt)  raw,}) {final _that = this;
switch (_that) {
case _FirebirdConfig():
return raw(_that.id,_that.name,_that.host,_that.databaseFile,_that.username,_that.password,_that.port,_that.aliasName,_that.useEmbedded,_that.clientLibraryPath,_that.serverVersionHint,_that.serviceManagerMode,_that.cryptKey,_that.enabled,_that.createdAt,_that.updatedAt);case _:
  throw StateError('Unexpected subclass');

}
}
/// A variant of `when` that fallback to returning `null`
///
/// It is equivalent to doing:
/// ```dart
/// switch (sealedClass) {
///   case Subclass(:final field):
///     return ...;
///   case _:
///     return null;
/// }
/// ```

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String host,  String databaseFile,  String username,  String password,  PortNumber port,  String? aliasName,  bool useEmbedded,  String? clientLibraryPath,  FirebirdServerVersionHint serverVersionHint,  FirebirdServiceManagerMode serviceManagerMode,  String cryptKey,  bool enabled,  DateTime createdAt,  DateTime updatedAt)?  raw,}) {final _that = this;
switch (_that) {
case _FirebirdConfig() when raw != null:
return raw(_that.id,_that.name,_that.host,_that.databaseFile,_that.username,_that.password,_that.port,_that.aliasName,_that.useEmbedded,_that.clientLibraryPath,_that.serverVersionHint,_that.serviceManagerMode,_that.cryptKey,_that.enabled,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _FirebirdConfig extends FirebirdConfig {
  const _FirebirdConfig({required this.id, required this.name, required this.host, required this.databaseFile, required this.username, required this.password, required this.port, this.aliasName, this.useEmbedded = false, this.clientLibraryPath, this.serverVersionHint = FirebirdServerVersionHint.auto, this.serviceManagerMode = FirebirdServiceManagerMode.auto, this.cryptKey = '', this.enabled = true, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String host;
@override final  String databaseFile;
@override final  String username;
@override final  String password;
@override final  PortNumber port;
@override final  String? aliasName;
@override@JsonKey() final  bool useEmbedded;
@override final  String? clientLibraryPath;
@override@JsonKey() final  FirebirdServerVersionHint serverVersionHint;
@override@JsonKey() final  FirebirdServiceManagerMode serviceManagerMode;
@override@JsonKey() final  String cryptKey;
@override@JsonKey() final  bool enabled;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of FirebirdConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$FirebirdConfigCopyWith<_FirebirdConfig> get copyWith => __$FirebirdConfigCopyWithImpl<_FirebirdConfig>(this, _$identity);





@override
String toString() {
  return 'FirebirdConfig.raw(id: $id, name: $name, host: $host, databaseFile: $databaseFile, username: $username, password: $password, port: $port, aliasName: $aliasName, useEmbedded: $useEmbedded, clientLibraryPath: $clientLibraryPath, serverVersionHint: $serverVersionHint, serviceManagerMode: $serviceManagerMode, cryptKey: $cryptKey, enabled: $enabled, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$FirebirdConfigCopyWith<$Res> implements $FirebirdConfigCopyWith<$Res> {
  factory _$FirebirdConfigCopyWith(_FirebirdConfig value, $Res Function(_FirebirdConfig) _then) = __$FirebirdConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String host, String databaseFile, String username, String password, PortNumber port, String? aliasName, bool useEmbedded, String? clientLibraryPath, FirebirdServerVersionHint serverVersionHint, FirebirdServiceManagerMode serviceManagerMode, String cryptKey, bool enabled, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$FirebirdConfigCopyWithImpl<$Res>
    implements _$FirebirdConfigCopyWith<$Res> {
  __$FirebirdConfigCopyWithImpl(this._self, this._then);

  final _FirebirdConfig _self;
  final $Res Function(_FirebirdConfig) _then;

/// Create a copy of FirebirdConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? host = null,Object? databaseFile = null,Object? username = null,Object? password = null,Object? port = null,Object? aliasName = freezed,Object? useEmbedded = null,Object? clientLibraryPath = freezed,Object? serverVersionHint = null,Object? serviceManagerMode = null,Object? cryptKey = null,Object? enabled = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_FirebirdConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,databaseFile: null == databaseFile ? _self.databaseFile : databaseFile // ignore: cast_nullable_to_non_nullable
as String,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,aliasName: freezed == aliasName ? _self.aliasName : aliasName // ignore: cast_nullable_to_non_nullable
as String?,useEmbedded: null == useEmbedded ? _self.useEmbedded : useEmbedded // ignore: cast_nullable_to_non_nullable
as bool,clientLibraryPath: freezed == clientLibraryPath ? _self.clientLibraryPath : clientLibraryPath // ignore: cast_nullable_to_non_nullable
as String?,serverVersionHint: null == serverVersionHint ? _self.serverVersionHint : serverVersionHint // ignore: cast_nullable_to_non_nullable
as FirebirdServerVersionHint,serviceManagerMode: null == serviceManagerMode ? _self.serviceManagerMode : serviceManagerMode // ignore: cast_nullable_to_non_nullable
as FirebirdServiceManagerMode,cryptKey: null == cryptKey ? _self.cryptKey : cryptKey // ignore: cast_nullable_to_non_nullable
as String,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
