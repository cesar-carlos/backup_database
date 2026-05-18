// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sql_server_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SqlServerConfig {

 String get id; String get name; String get server; DatabaseName get database; String get username; String get password; PortNumber get port; bool get enabled; bool get useWindowsAuth; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of SqlServerConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SqlServerConfigCopyWith<SqlServerConfig> get copyWith => _$SqlServerConfigCopyWithImpl<SqlServerConfig>(this as SqlServerConfig, _$identity);





@override
String toString() {
  return 'SqlServerConfig(id: $id, name: $name, server: $server, database: $database, username: $username, password: $password, port: $port, enabled: $enabled, useWindowsAuth: $useWindowsAuth, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SqlServerConfigCopyWith<$Res>  {
  factory $SqlServerConfigCopyWith(SqlServerConfig value, $Res Function(SqlServerConfig) _then) = _$SqlServerConfigCopyWithImpl;
@useResult
$Res call({
 String id, String name, String server, DatabaseName database, String username, String password, PortNumber port, bool enabled, bool useWindowsAuth, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$SqlServerConfigCopyWithImpl<$Res>
    implements $SqlServerConfigCopyWith<$Res> {
  _$SqlServerConfigCopyWithImpl(this._self, this._then);

  final SqlServerConfig _self;
  final $Res Function(SqlServerConfig) _then;

/// Create a copy of SqlServerConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? server = null,Object? database = null,Object? username = null,Object? password = null,Object? port = null,Object? enabled = null,Object? useWindowsAuth = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,useWindowsAuth: null == useWindowsAuth ? _self.useWindowsAuth : useWindowsAuth // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SqlServerConfig].
extension SqlServerConfigPatterns on SqlServerConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _SqlServerConfig value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SqlServerConfig() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _SqlServerConfig value)  raw,}){
final _that = this;
switch (_that) {
case _SqlServerConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _SqlServerConfig value)?  raw,}){
final _that = this;
switch (_that) {
case _SqlServerConfig() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String server,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  bool useWindowsAuth,  DateTime createdAt,  DateTime updatedAt)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SqlServerConfig() when raw != null:
return raw(_that.id,_that.name,_that.server,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.useWindowsAuth,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String server,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  bool useWindowsAuth,  DateTime createdAt,  DateTime updatedAt)  raw,}) {final _that = this;
switch (_that) {
case _SqlServerConfig():
return raw(_that.id,_that.name,_that.server,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.useWindowsAuth,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String server,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  bool useWindowsAuth,  DateTime createdAt,  DateTime updatedAt)?  raw,}) {final _that = this;
switch (_that) {
case _SqlServerConfig() when raw != null:
return raw(_that.id,_that.name,_that.server,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.useWindowsAuth,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _SqlServerConfig extends SqlServerConfig {
  const _SqlServerConfig({required this.id, required this.name, required this.server, required this.database, required this.username, required this.password, required this.port, this.enabled = true, this.useWindowsAuth = false, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String server;
@override final  DatabaseName database;
@override final  String username;
@override final  String password;
@override final  PortNumber port;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool useWindowsAuth;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of SqlServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SqlServerConfigCopyWith<_SqlServerConfig> get copyWith => __$SqlServerConfigCopyWithImpl<_SqlServerConfig>(this, _$identity);





@override
String toString() {
  return 'SqlServerConfig.raw(id: $id, name: $name, server: $server, database: $database, username: $username, password: $password, port: $port, enabled: $enabled, useWindowsAuth: $useWindowsAuth, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SqlServerConfigCopyWith<$Res> implements $SqlServerConfigCopyWith<$Res> {
  factory _$SqlServerConfigCopyWith(_SqlServerConfig value, $Res Function(_SqlServerConfig) _then) = __$SqlServerConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String server, DatabaseName database, String username, String password, PortNumber port, bool enabled, bool useWindowsAuth, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$SqlServerConfigCopyWithImpl<$Res>
    implements _$SqlServerConfigCopyWith<$Res> {
  __$SqlServerConfigCopyWithImpl(this._self, this._then);

  final _SqlServerConfig _self;
  final $Res Function(_SqlServerConfig) _then;

/// Create a copy of SqlServerConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? server = null,Object? database = null,Object? username = null,Object? password = null,Object? port = null,Object? enabled = null,Object? useWindowsAuth = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_SqlServerConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,server: null == server ? _self.server : server // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,useWindowsAuth: null == useWindowsAuth ? _self.useWindowsAuth : useWindowsAuth // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
