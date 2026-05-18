// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sybase_config.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$SybaseConfig {

 String get id; String get name; String get serverName; DatabaseName get databaseName; String get username; String get password; String get databaseFile; PortNumber get port; bool get enabled; bool get isReplicationEnvironment; DateTime get createdAt; DateTime get updatedAt;
/// Create a copy of SybaseConfig
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$SybaseConfigCopyWith<SybaseConfig> get copyWith => _$SybaseConfigCopyWithImpl<SybaseConfig>(this as SybaseConfig, _$identity);





@override
String toString() {
  return 'SybaseConfig(id: $id, name: $name, serverName: $serverName, databaseName: $databaseName, username: $username, password: $password, databaseFile: $databaseFile, port: $port, enabled: $enabled, isReplicationEnvironment: $isReplicationEnvironment, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class $SybaseConfigCopyWith<$Res>  {
  factory $SybaseConfigCopyWith(SybaseConfig value, $Res Function(SybaseConfig) _then) = _$SybaseConfigCopyWithImpl;
@useResult
$Res call({
 String id, String name, String serverName, DatabaseName databaseName, String username, String password, String databaseFile, PortNumber port, bool enabled, bool isReplicationEnvironment, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class _$SybaseConfigCopyWithImpl<$Res>
    implements $SybaseConfigCopyWith<$Res> {
  _$SybaseConfigCopyWithImpl(this._self, this._then);

  final SybaseConfig _self;
  final $Res Function(SybaseConfig) _then;

/// Create a copy of SybaseConfig
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? serverName = null,Object? databaseName = null,Object? username = null,Object? password = null,Object? databaseFile = null,Object? port = null,Object? enabled = null,Object? isReplicationEnvironment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,serverName: null == serverName ? _self.serverName : serverName // ignore: cast_nullable_to_non_nullable
as String,databaseName: null == databaseName ? _self.databaseName : databaseName // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,databaseFile: null == databaseFile ? _self.databaseFile : databaseFile // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,isReplicationEnvironment: null == isReplicationEnvironment ? _self.isReplicationEnvironment : isReplicationEnvironment // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}

}


/// Adds pattern-matching-related methods to [SybaseConfig].
extension SybaseConfigPatterns on SybaseConfig {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _SybaseConfig value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _SybaseConfig() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _SybaseConfig value)  raw,}){
final _that = this;
switch (_that) {
case _SybaseConfig():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _SybaseConfig value)?  raw,}){
final _that = this;
switch (_that) {
case _SybaseConfig() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String serverName,  DatabaseName databaseName,  String username,  String password,  String databaseFile,  PortNumber port,  bool enabled,  bool isReplicationEnvironment,  DateTime createdAt,  DateTime updatedAt)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _SybaseConfig() when raw != null:
return raw(_that.id,_that.name,_that.serverName,_that.databaseName,_that.username,_that.password,_that.databaseFile,_that.port,_that.enabled,_that.isReplicationEnvironment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String serverName,  DatabaseName databaseName,  String username,  String password,  String databaseFile,  PortNumber port,  bool enabled,  bool isReplicationEnvironment,  DateTime createdAt,  DateTime updatedAt)  raw,}) {final _that = this;
switch (_that) {
case _SybaseConfig():
return raw(_that.id,_that.name,_that.serverName,_that.databaseName,_that.username,_that.password,_that.databaseFile,_that.port,_that.enabled,_that.isReplicationEnvironment,_that.createdAt,_that.updatedAt);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String serverName,  DatabaseName databaseName,  String username,  String password,  String databaseFile,  PortNumber port,  bool enabled,  bool isReplicationEnvironment,  DateTime createdAt,  DateTime updatedAt)?  raw,}) {final _that = this;
switch (_that) {
case _SybaseConfig() when raw != null:
return raw(_that.id,_that.name,_that.serverName,_that.databaseName,_that.username,_that.password,_that.databaseFile,_that.port,_that.enabled,_that.isReplicationEnvironment,_that.createdAt,_that.updatedAt);case _:
  return null;

}
}

}

/// @nodoc


class _SybaseConfig extends SybaseConfig {
  const _SybaseConfig({required this.id, required this.name, required this.serverName, required this.databaseName, required this.username, required this.password, this.databaseFile = '', required this.port, this.enabled = true, this.isReplicationEnvironment = false, required this.createdAt, required this.updatedAt}): super._();
  

@override final  String id;
@override final  String name;
@override final  String serverName;
@override final  DatabaseName databaseName;
@override final  String username;
@override final  String password;
@override@JsonKey() final  String databaseFile;
@override final  PortNumber port;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool isReplicationEnvironment;
@override final  DateTime createdAt;
@override final  DateTime updatedAt;

/// Create a copy of SybaseConfig
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$SybaseConfigCopyWith<_SybaseConfig> get copyWith => __$SybaseConfigCopyWithImpl<_SybaseConfig>(this, _$identity);





@override
String toString() {
  return 'SybaseConfig.raw(id: $id, name: $name, serverName: $serverName, databaseName: $databaseName, username: $username, password: $password, databaseFile: $databaseFile, port: $port, enabled: $enabled, isReplicationEnvironment: $isReplicationEnvironment, createdAt: $createdAt, updatedAt: $updatedAt)';
}


}

/// @nodoc
abstract mixin class _$SybaseConfigCopyWith<$Res> implements $SybaseConfigCopyWith<$Res> {
  factory _$SybaseConfigCopyWith(_SybaseConfig value, $Res Function(_SybaseConfig) _then) = __$SybaseConfigCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String serverName, DatabaseName databaseName, String username, String password, String databaseFile, PortNumber port, bool enabled, bool isReplicationEnvironment, DateTime createdAt, DateTime updatedAt
});




}
/// @nodoc
class __$SybaseConfigCopyWithImpl<$Res>
    implements _$SybaseConfigCopyWith<$Res> {
  __$SybaseConfigCopyWithImpl(this._self, this._then);

  final _SybaseConfig _self;
  final $Res Function(_SybaseConfig) _then;

/// Create a copy of SybaseConfig
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? serverName = null,Object? databaseName = null,Object? username = null,Object? password = null,Object? databaseFile = null,Object? port = null,Object? enabled = null,Object? isReplicationEnvironment = null,Object? createdAt = null,Object? updatedAt = null,}) {
  return _then(_SybaseConfig(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,serverName: null == serverName ? _self.serverName : serverName // ignore: cast_nullable_to_non_nullable
as String,databaseName: null == databaseName ? _self.databaseName : databaseName // ignore: cast_nullable_to_non_nullable
as DatabaseName,username: null == username ? _self.username : username // ignore: cast_nullable_to_non_nullable
as String,password: null == password ? _self.password : password // ignore: cast_nullable_to_non_nullable
as String,databaseFile: null == databaseFile ? _self.databaseFile : databaseFile // ignore: cast_nullable_to_non_nullable
as String,port: null == port ? _self.port : port // ignore: cast_nullable_to_non_nullable
as PortNumber,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,isReplicationEnvironment: null == isReplicationEnvironment ? _self.isReplicationEnvironment : isReplicationEnvironment // ignore: cast_nullable_to_non_nullable
as bool,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,updatedAt: null == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime,
  ));
}


}

// dart format on
