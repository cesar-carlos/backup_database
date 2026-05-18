// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_log.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupLog {

 String get id; LogLevel get level; LogCategory get category; String get message; DateTime get createdAt; String? get backupHistoryId; String? get details;
/// Create a copy of BackupLog
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupLogCopyWith<BackupLog> get copyWith => _$BackupLogCopyWithImpl<BackupLog>(this as BackupLog, _$identity);





@override
String toString() {
  return 'BackupLog(id: $id, level: $level, category: $category, message: $message, createdAt: $createdAt, backupHistoryId: $backupHistoryId, details: $details)';
}


}

/// @nodoc
abstract mixin class $BackupLogCopyWith<$Res>  {
  factory $BackupLogCopyWith(BackupLog value, $Res Function(BackupLog) _then) = _$BackupLogCopyWithImpl;
@useResult
$Res call({
 String id, LogLevel level, LogCategory category, String message, DateTime createdAt, String? backupHistoryId, String? details
});




}
/// @nodoc
class _$BackupLogCopyWithImpl<$Res>
    implements $BackupLogCopyWith<$Res> {
  _$BackupLogCopyWithImpl(this._self, this._then);

  final BackupLog _self;
  final $Res Function(BackupLog) _then;

/// Create a copy of BackupLog
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? level = null,Object? category = null,Object? message = null,Object? createdAt = null,Object? backupHistoryId = freezed,Object? details = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as LogLevel,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as LogCategory,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,backupHistoryId: freezed == backupHistoryId ? _self.backupHistoryId : backupHistoryId // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}

}


/// Adds pattern-matching-related methods to [BackupLog].
extension BackupLogPatterns on BackupLog {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _BackupLog value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackupLog() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _BackupLog value)  raw,}){
final _that = this;
switch (_that) {
case _BackupLog():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _BackupLog value)?  raw,}){
final _that = this;
switch (_that) {
case _BackupLog() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  LogLevel level,  LogCategory category,  String message,  DateTime createdAt,  String? backupHistoryId,  String? details)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackupLog() when raw != null:
return raw(_that.id,_that.level,_that.category,_that.message,_that.createdAt,_that.backupHistoryId,_that.details);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  LogLevel level,  LogCategory category,  String message,  DateTime createdAt,  String? backupHistoryId,  String? details)  raw,}) {final _that = this;
switch (_that) {
case _BackupLog():
return raw(_that.id,_that.level,_that.category,_that.message,_that.createdAt,_that.backupHistoryId,_that.details);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  LogLevel level,  LogCategory category,  String message,  DateTime createdAt,  String? backupHistoryId,  String? details)?  raw,}) {final _that = this;
switch (_that) {
case _BackupLog() when raw != null:
return raw(_that.id,_that.level,_that.category,_that.message,_that.createdAt,_that.backupHistoryId,_that.details);case _:
  return null;

}
}

}

/// @nodoc


class _BackupLog extends BackupLog {
  const _BackupLog({required this.id, required this.level, required this.category, required this.message, required this.createdAt, this.backupHistoryId, this.details}): super._();
  

@override final  String id;
@override final  LogLevel level;
@override final  LogCategory category;
@override final  String message;
@override final  DateTime createdAt;
@override final  String? backupHistoryId;
@override final  String? details;

/// Create a copy of BackupLog
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupLogCopyWith<_BackupLog> get copyWith => __$BackupLogCopyWithImpl<_BackupLog>(this, _$identity);





@override
String toString() {
  return 'BackupLog.raw(id: $id, level: $level, category: $category, message: $message, createdAt: $createdAt, backupHistoryId: $backupHistoryId, details: $details)';
}


}

/// @nodoc
abstract mixin class _$BackupLogCopyWith<$Res> implements $BackupLogCopyWith<$Res> {
  factory _$BackupLogCopyWith(_BackupLog value, $Res Function(_BackupLog) _then) = __$BackupLogCopyWithImpl;
@override @useResult
$Res call({
 String id, LogLevel level, LogCategory category, String message, DateTime createdAt, String? backupHistoryId, String? details
});




}
/// @nodoc
class __$BackupLogCopyWithImpl<$Res>
    implements _$BackupLogCopyWith<$Res> {
  __$BackupLogCopyWithImpl(this._self, this._then);

  final _BackupLog _self;
  final $Res Function(_BackupLog) _then;

/// Create a copy of BackupLog
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? level = null,Object? category = null,Object? message = null,Object? createdAt = null,Object? backupHistoryId = freezed,Object? details = freezed,}) {
  return _then(_BackupLog(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,level: null == level ? _self.level : level // ignore: cast_nullable_to_non_nullable
as LogLevel,category: null == category ? _self.category : category // ignore: cast_nullable_to_non_nullable
as LogCategory,message: null == message ? _self.message : message // ignore: cast_nullable_to_non_nullable
as String,createdAt: null == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime,backupHistoryId: freezed == backupHistoryId ? _self.backupHistoryId : backupHistoryId // ignore: cast_nullable_to_non_nullable
as String?,details: freezed == details ? _self.details : details // ignore: cast_nullable_to_non_nullable
as String?,
  ));
}


}

// dart format on
