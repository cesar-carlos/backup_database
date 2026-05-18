// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'postgres_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$PostgresConfig {

 String get id; String get name; String get host; DatabaseName get database; String get username; String get password; PortNumber get port; bool get enabled; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of PostgresConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$PostgresConfigCopyWith<PostgresConfig> get copyWith => _$PostgresConfigCopyWithImpl<PostgresConfig>(this as PostgresConfig, _$identity);





@override
String toString() {
  return 'PostgresConfig(id: $id, name: $name, host: $host, database: $database, username: $username, password: $password, port: $port, enabled: $enabled, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $PostgresConfigCopyWith<$Res>  {
  factory $PostgresConfigCopyWith(PostgresConfig value, $Res Function(PostgresConfig) _then) = _$PostgresConfigCopyWithImpl;
@useResult
$Res call({
 String id, String name, String host, DatabaseName database, String username, String password, PortNumber port, bool enabled, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$PostgresConfigCopyWithImpl<$Res>
    implements $PostgresConfigCopyWith<$Res> {
  _$PostgresConfigCopyWithImpl(this._self, this._then);

  final PostgresConfig _self;
  final $Res Function(PostgresConfig) _then;

/// Create a copy of PostgresConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? host = null,Object? database = null,Object? username = null,Object? password = null,Object? port = null,Object? enabled = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [PostgresConfig].
extension PostgresConfigPatterns on PostgresConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _PostgresConfig value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _PostgresConfig() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _PostgresConfig value)  raw,}){
final _that = this;
switch (_that) {
case _PostgresConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _PostgresConfig value)?  raw,}){
final _that = this;
switch (_that) {
case _PostgresConfig() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String host,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  DateTime createdAt,  DateTime updatedAt)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _PostgresConfig() when raw != null:
return raw(_that.id,_that.name,_that.host,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String host,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  DateTime createdAt,  DateTime updatedAt)  raw,}) {final _that = this;
switch (_that) {
case _PostgresConfig():
return raw(_that.id,_that.name,_that.host,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String host,  DatabaseName database,  String username,  String password,  PortNumber port,  bool enabled,  DateTime createdAt,  DateTime updatedAt)?  raw,}) {final _that = this;
switch (_that) {
case _PostgresConfig() when raw != null:
return raw(_that.id,_that.name,_that.host,_that.database,_that.username,_that.password,_that.port,_that.enabled,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _PostgresConfig extends PostgresConfig {
  const _PostgresConfig({required this.id, required this.name, required this.host, required this.database, required this.username, required this.password, required this.port, this.enabled = true, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String host;
@override final  DatabaseName database;
@override final  String username;
@override final  String password;
@override final  PortNumber port;
@override@JsonKey() final  bool enabled;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of PostgresConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$PostgresConfigCopyWith<_PostgresConfig> get copyWith => __$PostgresConfigCopyWithImpl<_PostgresConfig>(this, _$identity);





@override
String toString() {
  return 'PostgresConfig.raw(id: $id, name: $name, host: $host, database: $database, username: $username, password: $password, port: $port, enabled: $enabled, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$PostgresConfigCopyWith<$Res> implements $PostgresConfigCopyWith<$Res> {
  factory _$PostgresConfigCopyWith(_PostgresConfig value, $Res Function(_PostgresConfig) _then) = __$PostgresConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String host, DatabaseName database, String username, String password, PortNumber port, bool enabled, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$PostgresConfigCopyWithImpl<$Res>
    implements _$PostgresConfigCopyWith<$Res> {
  __$PostgresConfigCopyWithImpl(this._self, this._then);

  final _PostgresConfig _self;
  final $Res Function(_PostgresConfig) _then;

/// Create a copy of PostgresConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? host = null,Object? database = null,Object? username = null,Object? password = null,Object? port = null,Object? enabled = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_PostgresConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,host: null == host ? _self.host : host // ignore: cast_nullable_to_non_nullable
as String,database: null == database ? _self.database : database // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
