// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_history.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupHistory {

 String get id; String get databaseName; String get databaseType; String get backupPath; int get fileSize; BackupStatus get status; DateTime get startedAt; String? get runId; String? get scheduleId; String get backupType; String? get errorMessage; DateTime? get finishedAt; int? get durationSeconds; BackupMetrics? get metrics;
/// Create a copy of BackupHistory
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupHistoryCopyWith<BackupHistory> get copyWith => _$BackupHistoryCopyWithImpl<BackupHistory>(this as BackupHistory, _$identity);





@override
String toString() {
  return 'BackupHistory(id: $id, databaseName: $databaseName, databaseType: $databaseType, backupPath: $backupPath, fileSize: $fileSize, status: $status, startedAt: $startedAt, runId: $runId, scheduleId: $scheduleId, backupType: $backupType, errorMessage: $errorMessage, finishedAt: $finishedAt, durationSeconds: $durationSeconds, metrics: $metrics)';
}


}

/// @nodoc
abstract mixin class $BackupHistoryCopyWith<$Res>  {
  factory $BackupHistoryCopyWith(BackupHistory value, $Res Function(BackupHistory) _then) = _$BackupHistoryCopyWithImpl;
@useResult
$Res call({
 String id, String databaseName, String databaseType, String backupPath, int fileSize, BackupStatus status, DateTime startedAt, String? runId, String? scheduleId, String backupType, String? errorMessage, DateTime? finishedAt, int? durationSeconds, BackupMetrics? metrics
});




}
/// @nodoc
class _$BackupHistoryCopyWithImpl<$Res>
    implements $BackupHistoryCopyWith<$Res> {
  _$BackupHistoryCopyWithImpl(this._self, this._then);

  final BackupHistory _self;
  final $Res Function(BackupHistory) _then;

/// Create a copy of BackupHistory
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? databaseName = null,Object? databaseType = null,Object? backupPath = null,Object? fileSize = null,Object? status = null,Object? startedAt = null,Object? runId = freezed,Object? scheduleId = freezed,Object? backupType = null,Object? errorMessage = freezed,Object? finishedAt = freezed,Object? durationSeconds = freezed,Object? metrics = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,databaseName: null == databaseName ? _self.databaseName : databaseName // ignore: cast_nullable_to_non_nullable
as String,databaseType: null == databaseType ? _self.databaseType : databaseType // ignore: cast_nullable_to_non_nullable
as String,backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BackupStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,runId: freezed == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String?,scheduleId: freezed == scheduleId ? _self.scheduleId : scheduleId // ignore: cast_nullable_to_non_nullable
as String?,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,metrics: freezed == metrics ? _self.metrics : metrics // ignore: cast_nullable_to_non_nullable
as BackupMetrics?,
  ));
}

}


/// Adds pattern-matching-related methods to [BackupHistory].
extension BackupHistoryPatterns on BackupHistory {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _BackupHistory value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackupHistory() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _BackupHistory value)  raw,}){
final _that = this;
switch (_that) {
case _BackupHistory():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _BackupHistory value)?  raw,}){
final _that = this;
switch (_that) {
case _BackupHistory() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String databaseName,  String databaseType,  String backupPath,  int fileSize,  BackupStatus status,  DateTime startedAt,  String? runId,  String? scheduleId,  String backupType,  String? errorMessage,  DateTime? finishedAt,  int? durationSeconds,  BackupMetrics? metrics)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackupHistory() when raw != null:
return raw(_that.id,_that.databaseName,_that.databaseType,_that.backupPath,_that.fileSize,_that.status,_that.startedAt,_that.runId,_that.scheduleId,_that.backupType,_that.errorMessage,_that.finishedAt,_that.durationSeconds,_that.metrics);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String databaseName,  String databaseType,  String backupPath,  int fileSize,  BackupStatus status,  DateTime startedAt,  String? runId,  String? scheduleId,  String backupType,  String? errorMessage,  DateTime? finishedAt,  int? durationSeconds,  BackupMetrics? metrics)  raw,}) {final _that = this;
switch (_that) {
case _BackupHistory():
return raw(_that.id,_that.databaseName,_that.databaseType,_that.backupPath,_that.fileSize,_that.status,_that.startedAt,_that.runId,_that.scheduleId,_that.backupType,_that.errorMessage,_that.finishedAt,_that.durationSeconds,_that.metrics);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String databaseName,  String databaseType,  String backupPath,  int fileSize,  BackupStatus status,  DateTime startedAt,  String? runId,  String? scheduleId,  String backupType,  String? errorMessage,  DateTime? finishedAt,  int? durationSeconds,  BackupMetrics? metrics)?  raw,}) {final _that = this;
switch (_that) {
case _BackupHistory() when raw != null:
return raw(_that.id,_that.databaseName,_that.databaseType,_that.backupPath,_that.fileSize,_that.status,_that.startedAt,_that.runId,_that.scheduleId,_that.backupType,_that.errorMessage,_that.finishedAt,_that.durationSeconds,_that.metrics);case _:
  return null;

}
}

}

/// @nodoc


class _BackupHistory extends BackupHistory {
  const _BackupHistory({required this.id, required this.databaseName, required this.databaseType, required this.backupPath, required this.fileSize, required this.status, required this.startedAt, this.runId, this.scheduleId, this.backupType = 'full', this.errorMessage, this.finishedAt, this.durationSeconds, this.metrics}): super._();
  

@override final  String id;
@override final  String databaseName;
@override final  String databaseType;
@override final  String backupPath;
@override final  int fileSize;
@override final  BackupStatus status;
@override final  DateTime startedAt;
@override final  String? runId;
@override final  String? scheduleId;
@override@JsonKey() final  String backupType;
@override final  String? errorMessage;
@override final  DateTime? finishedAt;
@override final  int? durationSeconds;
@override final  BackupMetrics? metrics;

/// Create a copy of BackupHistory
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupHistoryCopyWith<_BackupHistory> get copyWith => __$BackupHistoryCopyWithImpl<_BackupHistory>(this, _$identity);





@override
String toString() {
  return 'BackupHistory.raw(id: $id, databaseName: $databaseName, databaseType: $databaseType, backupPath: $backupPath, fileSize: $fileSize, status: $status, startedAt: $startedAt, runId: $runId, scheduleId: $scheduleId, backupType: $backupType, errorMessage: $errorMessage, finishedAt: $finishedAt, durationSeconds: $durationSeconds, metrics: $metrics)';
}


}

/// @nodoc
abstract mixin class _$BackupHistoryCopyWith<$Res> implements $BackupHistoryCopyWith<$Res> {
  factory _$BackupHistoryCopyWith(_BackupHistory value, $Res Function(_BackupHistory) _then) = __$BackupHistoryCopyWithImpl;
@override @useResult
$Res call({
 String id, String databaseName, String databaseType, String backupPath, int fileSize, BackupStatus status, DateTime startedAt, String? runId, String? scheduleId, String backupType, String? errorMessage, DateTime? finishedAt, int? durationSeconds, BackupMetrics? metrics
});




}
/// @nodoc
class __$BackupHistoryCopyWithImpl<$Res>
    implements _$BackupHistoryCopyWith<$Res> {
  __$BackupHistoryCopyWithImpl(this._self, this._then);

  final _BackupHistory _self;
  final $Res Function(_BackupHistory) _then;

/// Create a copy of BackupHistory
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? databaseName = null,Object? databaseType = null,Object? backupPath = null,Object? fileSize = null,Object? status = null,Object? startedAt = null,Object? runId = freezed,Object? scheduleId = freezed,Object? backupType = null,Object? errorMessage = freezed,Object? finishedAt = freezed,Object? durationSeconds = freezed,Object? metrics = freezed,}) {
  return _then(_BackupHistory(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,databaseName: null == databaseName ? _self.databaseName : databaseName // ignore: cast_nullable_to_non_nullable
as String,databaseType: null == databaseType ? _self.databaseType : databaseType // ignore: cast_nullable_to_non_nullable
as String,backupPath: null == backupPath ? _self.backupPath : backupPath // ignore: cast_nullable_to_non_nullable
as String,fileSize: null == fileSize ? _self.fileSize : fileSize // ignore: cast_nullable_to_non_nullable
as int,status: null == status ? _self.status : status // ignore: cast_nullable_to_non_nullable
as BackupStatus,startedAt: null == startedAt ? _self.startedAt : startedAt // ignore: cast_nullable_to_non_nullable
as DateTime,runId: freezed == runId ? _self.runId : runId // ignore: cast_nullable_to_non_nullable
as String?,scheduleId: freezed == scheduleId ? _self.scheduleId : scheduleId // ignore: cast_nullable_to_non_nullable
as String?,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as String,errorMessage: freezed == errorMessage ? _self.errorMessage : errorMessage // ignore: cast_nullable_to_non_nullable
as String?,finishedAt: freezed == finishedAt ? _self.finishedAt : finishedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,durationSeconds: freezed == durationSeconds ? _self.durationSeconds : durationSeconds // ignore: cast_nullable_to_non_nullable
as int?,metrics: freezed == metrics ? _self.metrics : metrics // ignore: cast_nullable_to_non_nullable
as BackupMetrics?,
  ));
}


}

// dart format on
