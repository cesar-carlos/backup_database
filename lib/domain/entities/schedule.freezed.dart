// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'schedule.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$Schedule {

 String get id; String get name; String get databaseConfigId; DatabaseType get databaseType; String get scheduleType; String get scheduleConfig; List<String> get destinationIds; String get backupFolder; BackupType get backupType; bool get truncateLog; bool get compressBackup; CompressionFormat get compressionFormat; bool get enabled; bool get enableChecksum; bool get verifyAfterBackup; VerifyPolicy get verifyPolicy; String? get postBackupScript; Duration get backupTimeout; Duration get verifyTimeout; DateTime? get lastRunAt; DateTime? get nextRunAt; DateTime? get createdAt; DateTime? get updatedAt; bool get isConvertedDifferential; int? get firebirdNbackupPhysicalLevel; SqlServerBackupOptions? get sqlServerBackupOptions; SybaseBackupOptions? get sybaseBackupOptions;
/// Create a copy of Schedule
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$ScheduleCopyWith<Schedule> get copyWith => _$ScheduleCopyWithImpl<Schedule>(this as Schedule, _$identity);





@override
String toString() {
  return 'Schedule(id: $id, name: $name, databaseConfigId: $databaseConfigId, databaseType: $databaseType, scheduleType: $scheduleType, scheduleConfig: $scheduleConfig, destinationIds: $destinationIds, backupFolder: $backupFolder, backupType: $backupType, truncateLog: $truncateLog, compressBackup: $compressBackup, compressionFormat: $compressionFormat, enabled: $enabled, enableChecksum: $enableChecksum, verifyAfterBackup: $verifyAfterBackup, verifyPolicy: $verifyPolicy, postBackupScript: $postBackupScript, backupTimeout: $backupTimeout, verifyTimeout: $verifyTimeout, lastRunAt: $lastRunAt, nextRunAt: $nextRunAt, createdAt: $createdAt, updatedAt: $updatedAt, isConvertedDifferential: $isConvertedDifferential, firebirdNbackupPhysicalLevel: $firebirdNbackupPhysicalLevel, sqlServerBackupOptions: $sqlServerBackupOptions, sybaseBackupOptions: $sybaseBackupOptions)';
}


}

/// @nodoc
abstract mixin class $ScheduleCopyWith<$Res>  {
  factory $ScheduleCopyWith(Schedule value, $Res Function(Schedule) _then) = _$ScheduleCopyWithImpl;
@useResult
$Res call({
 String id, String name, String databaseConfigId, DatabaseType databaseType, String scheduleType, String scheduleConfig, List<String> destinationIds, String backupFolder, BackupType backupType, bool truncateLog, bool compressBackup, CompressionFormat compressionFormat, bool enabled, bool enableChecksum, bool verifyAfterBackup, VerifyPolicy verifyPolicy, String? postBackupScript, Duration backupTimeout, Duration verifyTimeout, DateTime? lastRunAt, DateTime? nextRunAt, DateTime? createdAt, DateTime? updatedAt, bool isConvertedDifferential, int? firebirdNbackupPhysicalLevel, SqlServerBackupOptions? sqlServerBackupOptions, SybaseBackupOptions? sybaseBackupOptions
});




}
/// @nodoc
class _$ScheduleCopyWithImpl<$Res>
    implements $ScheduleCopyWith<$Res> {
  _$ScheduleCopyWithImpl(this._self, this._then);

  final Schedule _self;
  final $Res Function(Schedule) _then;

/// Create a copy of Schedule
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? id = null,Object? name = null,Object? databaseConfigId = null,Object? databaseType = null,Object? scheduleType = null,Object? scheduleConfig = null,Object? destinationIds = null,Object? backupFolder = null,Object? backupType = null,Object? truncateLog = null,Object? compressBackup = null,Object? compressionFormat = null,Object? enabled = null,Object? enableChecksum = null,Object? verifyAfterBackup = null,Object? verifyPolicy = null,Object? postBackupScript = freezed,Object? backupTimeout = null,Object? verifyTimeout = null,Object? lastRunAt = freezed,Object? nextRunAt = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? isConvertedDifferential = null,Object? firebirdNbackupPhysicalLevel = freezed,Object? sqlServerBackupOptions = freezed,Object? sybaseBackupOptions = freezed,}) {
  return _then(_self.copyWith(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,databaseConfigId: null == databaseConfigId ? _self.databaseConfigId : databaseConfigId // ignore: cast_nullable_to_non_nullable
as String,databaseType: null == databaseType ? _self.databaseType : databaseType // ignore: cast_nullable_to_non_nullable
as DatabaseType,scheduleType: null == scheduleType ? _self.scheduleType : scheduleType // ignore: cast_nullable_to_non_nullable
as String,scheduleConfig: null == scheduleConfig ? _self.scheduleConfig : scheduleConfig // ignore: cast_nullable_to_non_nullable
as String,destinationIds: null == destinationIds ? _self.destinationIds : destinationIds // ignore: cast_nullable_to_non_nullable
as List<String>,backupFolder: null == backupFolder ? _self.backupFolder : backupFolder // ignore: cast_nullable_to_non_nullable
as String,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as BackupType,truncateLog: null == truncateLog ? _self.truncateLog : truncateLog // ignore: cast_nullable_to_non_nullable
as bool,compressBackup: null == compressBackup ? _self.compressBackup : compressBackup // ignore: cast_nullable_to_non_nullable
as bool,compressionFormat: null == compressionFormat ? _self.compressionFormat : compressionFormat // ignore: cast_nullable_to_non_nullable
as CompressionFormat,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,enableChecksum: null == enableChecksum ? _self.enableChecksum : enableChecksum // ignore: cast_nullable_to_non_nullable
as bool,verifyAfterBackup: null == verifyAfterBackup ? _self.verifyAfterBackup : verifyAfterBackup // ignore: cast_nullable_to_non_nullable
as bool,verifyPolicy: null == verifyPolicy ? _self.verifyPolicy : verifyPolicy // ignore: cast_nullable_to_non_nullable
as VerifyPolicy,postBackupScript: freezed == postBackupScript ? _self.postBackupScript : postBackupScript // ignore: cast_nullable_to_non_nullable
as String?,backupTimeout: null == backupTimeout ? _self.backupTimeout : backupTimeout // ignore: cast_nullable_to_non_nullable
as Duration,verifyTimeout: null == verifyTimeout ? _self.verifyTimeout : verifyTimeout // ignore: cast_nullable_to_non_nullable
as Duration,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isConvertedDifferential: null == isConvertedDifferential ? _self.isConvertedDifferential : isConvertedDifferential // ignore: cast_nullable_to_non_nullable
as bool,firebirdNbackupPhysicalLevel: freezed == firebirdNbackupPhysicalLevel ? _self.firebirdNbackupPhysicalLevel : firebirdNbackupPhysicalLevel // ignore: cast_nullable_to_non_nullable
as int?,sqlServerBackupOptions: freezed == sqlServerBackupOptions ? _self.sqlServerBackupOptions : sqlServerBackupOptions // ignore: cast_nullable_to_non_nullable
as SqlServerBackupOptions?,sybaseBackupOptions: freezed == sybaseBackupOptions ? _self.sybaseBackupOptions : sybaseBackupOptions // ignore: cast_nullable_to_non_nullable
as SybaseBackupOptions?,
  ));
}

}


/// Adds pattern-matching-related methods to [Schedule].
extension SchedulePatterns on Schedule {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>({TResult Function( _Schedule value)?  raw,required TResult orElse(),}){
final _that = this;
switch (_that) {
case _Schedule() when raw != null:
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

@optionalTypeArgs TResult map<TResult extends Object?>({required TResult Function( _Schedule value)  raw,}){
final _that = this;
switch (_that) {
case _Schedule():
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>({TResult? Function( _Schedule value)?  raw,}){
final _that = this;
switch (_that) {
case _Schedule() when raw != null:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>({TResult Function( String id,  String name,  String databaseConfigId,  DatabaseType databaseType,  String scheduleType,  String scheduleConfig,  List<String> destinationIds,  String backupFolder,  BackupType backupType,  bool truncateLog,  bool compressBackup,  CompressionFormat compressionFormat,  bool enabled,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  String? postBackupScript,  Duration backupTimeout,  Duration verifyTimeout,  DateTime? lastRunAt,  DateTime? nextRunAt,  DateTime? createdAt,  DateTime? updatedAt,  bool isConvertedDifferential,  int? firebirdNbackupPhysicalLevel,  SqlServerBackupOptions? sqlServerBackupOptions,  SybaseBackupOptions? sybaseBackupOptions)?  raw,required TResult orElse(),}) {final _that = this;
switch (_that) {
case _Schedule() when raw != null:
return raw(_that.id,_that.name,_that.databaseConfigId,_that.databaseType,_that.scheduleType,_that.scheduleConfig,_that.destinationIds,_that.backupFolder,_that.backupType,_that.truncateLog,_that.compressBackup,_that.compressionFormat,_that.enabled,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.postBackupScript,_that.backupTimeout,_that.verifyTimeout,_that.lastRunAt,_that.nextRunAt,_that.createdAt,_that.updatedAt,_that.isConvertedDifferential,_that.firebirdNbackupPhysicalLevel,_that.sqlServerBackupOptions,_that.sybaseBackupOptions);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>({required TResult Function( String id,  String name,  String databaseConfigId,  DatabaseType databaseType,  String scheduleType,  String scheduleConfig,  List<String> destinationIds,  String backupFolder,  BackupType backupType,  bool truncateLog,  bool compressBackup,  CompressionFormat compressionFormat,  bool enabled,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  String? postBackupScript,  Duration backupTimeout,  Duration verifyTimeout,  DateTime? lastRunAt,  DateTime? nextRunAt,  DateTime? createdAt,  DateTime? updatedAt,  bool isConvertedDifferential,  int? firebirdNbackupPhysicalLevel,  SqlServerBackupOptions? sqlServerBackupOptions,  SybaseBackupOptions? sybaseBackupOptions)  raw,}) {final _that = this;
switch (_that) {
case _Schedule():
return raw(_that.id,_that.name,_that.databaseConfigId,_that.databaseType,_that.scheduleType,_that.scheduleConfig,_that.destinationIds,_that.backupFolder,_that.backupType,_that.truncateLog,_that.compressBackup,_that.compressionFormat,_that.enabled,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.postBackupScript,_that.backupTimeout,_that.verifyTimeout,_that.lastRunAt,_that.nextRunAt,_that.createdAt,_that.updatedAt,_that.isConvertedDifferential,_that.firebirdNbackupPhysicalLevel,_that.sqlServerBackupOptions,_that.sybaseBackupOptions);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>({TResult? Function( String id,  String name,  String databaseConfigId,  DatabaseType databaseType,  String scheduleType,  String scheduleConfig,  List<String> destinationIds,  String backupFolder,  BackupType backupType,  bool truncateLog,  bool compressBackup,  CompressionFormat compressionFormat,  bool enabled,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  String? postBackupScript,  Duration backupTimeout,  Duration verifyTimeout,  DateTime? lastRunAt,  DateTime? nextRunAt,  DateTime? createdAt,  DateTime? updatedAt,  bool isConvertedDifferential,  int? firebirdNbackupPhysicalLevel,  SqlServerBackupOptions? sqlServerBackupOptions,  SybaseBackupOptions? sybaseBackupOptions)?  raw,}) {final _that = this;
switch (_that) {
case _Schedule() when raw != null:
return raw(_that.id,_that.name,_that.databaseConfigId,_that.databaseType,_that.scheduleType,_that.scheduleConfig,_that.destinationIds,_that.backupFolder,_that.backupType,_that.truncateLog,_that.compressBackup,_that.compressionFormat,_that.enabled,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.postBackupScript,_that.backupTimeout,_that.verifyTimeout,_that.lastRunAt,_that.nextRunAt,_that.createdAt,_that.updatedAt,_that.isConvertedDifferential,_that.firebirdNbackupPhysicalLevel,_that.sqlServerBackupOptions,_that.sybaseBackupOptions);case _:
  return null;

}
}

}

/// @nodoc


class _Schedule extends Schedule {
  const _Schedule({required this.id, required this.name, required this.databaseConfigId, required this.databaseType, required this.scheduleType, required this.scheduleConfig, required final  List<String> destinationIds, required this.backupFolder, this.backupType = BackupType.full, this.truncateLog = true, this.compressBackup = true, required this.compressionFormat, this.enabled = true, this.enableChecksum = false, this.verifyAfterBackup = false, this.verifyPolicy = VerifyPolicy.bestEffort, this.postBackupScript, this.backupTimeout = const Duration(hours: 2), this.verifyTimeout = const Duration(minutes: 30), this.lastRunAt, this.nextRunAt, this.createdAt, this.updatedAt, this.isConvertedDifferential = false, this.firebirdNbackupPhysicalLevel, this.sqlServerBackupOptions, this.sybaseBackupOptions}): _destinationIds = destinationIds,super._();
  

@override final  String id;
@override final  String name;
@override final  String databaseConfigId;
@override final  DatabaseType databaseType;
@override final  String scheduleType;
@override final  String scheduleConfig;
 final  List<String> _destinationIds;
@override List<String> get destinationIds {
  if (_destinationIds is EqualUnmodifiableListView) return _destinationIds;
  // ignore: implicit_dynamic_type
  return EqualUnmodifiableListView(_destinationIds);
}

@override final  String backupFolder;
@override@JsonKey() final  BackupType backupType;
@override@JsonKey() final  bool truncateLog;
@override@JsonKey() final  bool compressBackup;
@override final  CompressionFormat compressionFormat;
@override@JsonKey() final  bool enabled;
@override@JsonKey() final  bool enableChecksum;
@override@JsonKey() final  bool verifyAfterBackup;
@override@JsonKey() final  VerifyPolicy verifyPolicy;
@override final  String? postBackupScript;
@override@JsonKey() final  Duration backupTimeout;
@override@JsonKey() final  Duration verifyTimeout;
@override final  DateTime? lastRunAt;
@override final  DateTime? nextRunAt;
@override final  DateTime? createdAt;
@override final  DateTime? updatedAt;
@override@JsonKey() final  bool isConvertedDifferential;
@override final  int? firebirdNbackupPhysicalLevel;
@override final  SqlServerBackupOptions? sqlServerBackupOptions;
@override final  SybaseBackupOptions? sybaseBackupOptions;

/// Create a copy of Schedule
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$ScheduleCopyWith<_Schedule> get copyWith => __$ScheduleCopyWithImpl<_Schedule>(this, _$identity);





@override
String toString() {
  return 'Schedule.raw(id: $id, name: $name, databaseConfigId: $databaseConfigId, databaseType: $databaseType, scheduleType: $scheduleType, scheduleConfig: $scheduleConfig, destinationIds: $destinationIds, backupFolder: $backupFolder, backupType: $backupType, truncateLog: $truncateLog, compressBackup: $compressBackup, compressionFormat: $compressionFormat, enabled: $enabled, enableChecksum: $enableChecksum, verifyAfterBackup: $verifyAfterBackup, verifyPolicy: $verifyPolicy, postBackupScript: $postBackupScript, backupTimeout: $backupTimeout, verifyTimeout: $verifyTimeout, lastRunAt: $lastRunAt, nextRunAt: $nextRunAt, createdAt: $createdAt, updatedAt: $updatedAt, isConvertedDifferential: $isConvertedDifferential, firebirdNbackupPhysicalLevel: $firebirdNbackupPhysicalLevel, sqlServerBackupOptions: $sqlServerBackupOptions, sybaseBackupOptions: $sybaseBackupOptions)';
}


}

/// @nodoc
abstract mixin class _$ScheduleCopyWith<$Res> implements $ScheduleCopyWith<$Res> {
  factory _$ScheduleCopyWith(_Schedule value, $Res Function(_Schedule) _then) = __$ScheduleCopyWithImpl;
@override @useResult
$Res call({
 String id, String name, String databaseConfigId, DatabaseType databaseType, String scheduleType, String scheduleConfig, List<String> destinationIds, String backupFolder, BackupType backupType, bool truncateLog, bool compressBackup, CompressionFormat compressionFormat, bool enabled, bool enableChecksum, bool verifyAfterBackup, VerifyPolicy verifyPolicy, String? postBackupScript, Duration backupTimeout, Duration verifyTimeout, DateTime? lastRunAt, DateTime? nextRunAt, DateTime? createdAt, DateTime? updatedAt, bool isConvertedDifferential, int? firebirdNbackupPhysicalLevel, SqlServerBackupOptions? sqlServerBackupOptions, SybaseBackupOptions? sybaseBackupOptions
});




}
/// @nodoc
class __$ScheduleCopyWithImpl<$Res>
    implements _$ScheduleCopyWith<$Res> {
  __$ScheduleCopyWithImpl(this._self, this._then);

  final _Schedule _self;
  final $Res Function(_Schedule) _then;

/// Create a copy of Schedule
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? id = null,Object? name = null,Object? databaseConfigId = null,Object? databaseType = null,Object? scheduleType = null,Object? scheduleConfig = null,Object? destinationIds = null,Object? backupFolder = null,Object? backupType = null,Object? truncateLog = null,Object? compressBackup = null,Object? compressionFormat = null,Object? enabled = null,Object? enableChecksum = null,Object? verifyAfterBackup = null,Object? verifyPolicy = null,Object? postBackupScript = freezed,Object? backupTimeout = null,Object? verifyTimeout = null,Object? lastRunAt = freezed,Object? nextRunAt = freezed,Object? createdAt = freezed,Object? updatedAt = freezed,Object? isConvertedDifferential = null,Object? firebirdNbackupPhysicalLevel = freezed,Object? sqlServerBackupOptions = freezed,Object? sybaseBackupOptions = freezed,}) {
  return _then(_Schedule(
id: null == id ? _self.id : id // ignore: cast_nullable_to_non_nullable
as String,name: null == name ? _self.name : name // ignore: cast_nullable_to_non_nullable
as String,databaseConfigId: null == databaseConfigId ? _self.databaseConfigId : databaseConfigId // ignore: cast_nullable_to_non_nullable
as String,databaseType: null == databaseType ? _self.databaseType : databaseType // ignore: cast_nullable_to_non_nullable
as DatabaseType,scheduleType: null == scheduleType ? _self.scheduleType : scheduleType // ignore: cast_nullable_to_non_nullable
as String,scheduleConfig: null == scheduleConfig ? _self.scheduleConfig : scheduleConfig // ignore: cast_nullable_to_non_nullable
as String,destinationIds: null == destinationIds ? _self._destinationIds : destinationIds // ignore: cast_nullable_to_non_nullable
as List<String>,backupFolder: null == backupFolder ? _self.backupFolder : backupFolder // ignore: cast_nullable_to_non_nullable
as String,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as BackupType,truncateLog: null == truncateLog ? _self.truncateLog : truncateLog // ignore: cast_nullable_to_non_nullable
as bool,compressBackup: null == compressBackup ? _self.compressBackup : compressBackup // ignore: cast_nullable_to_non_nullable
as bool,compressionFormat: null == compressionFormat ? _self.compressionFormat : compressionFormat // ignore: cast_nullable_to_non_nullable
as CompressionFormat,enabled: null == enabled ? _self.enabled : enabled // ignore: cast_nullable_to_non_nullable
as bool,enableChecksum: null == enableChecksum ? _self.enableChecksum : enableChecksum // ignore: cast_nullable_to_non_nullable
as bool,verifyAfterBackup: null == verifyAfterBackup ? _self.verifyAfterBackup : verifyAfterBackup // ignore: cast_nullable_to_non_nullable
as bool,verifyPolicy: null == verifyPolicy ? _self.verifyPolicy : verifyPolicy // ignore: cast_nullable_to_non_nullable
as VerifyPolicy,postBackupScript: freezed == postBackupScript ? _self.postBackupScript : postBackupScript // ignore: cast_nullable_to_non_nullable
as String?,backupTimeout: null == backupTimeout ? _self.backupTimeout : backupTimeout // ignore: cast_nullable_to_non_nullable
as Duration,verifyTimeout: null == verifyTimeout ? _self.verifyTimeout : verifyTimeout // ignore: cast_nullable_to_non_nullable
as Duration,lastRunAt: freezed == lastRunAt ? _self.lastRunAt : lastRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,nextRunAt: freezed == nextRunAt ? _self.nextRunAt : nextRunAt // ignore: cast_nullable_to_non_nullable
as DateTime?,createdAt: freezed == createdAt ? _self.createdAt : createdAt // ignore: cast_nullable_to_non_nullable
as DateTime?,updatedAt: freezed == updatedAt ? _self.updatedAt : updatedAt // ignore: cast_nullable_to_non_nullable
as DateTime?,isConvertedDifferential: null == isConvertedDifferential ? _self.isConvertedDifferential : isConvertedDifferential // ignore: cast_nullable_to_non_nullable
as bool,firebirdNbackupPhysicalLevel: freezed == firebirdNbackupPhysicalLevel ? _self.firebirdNbackupPhysicalLevel : firebirdNbackupPhysicalLevel // ignore: cast_nullable_to_non_nullable
as int?,sqlServerBackupOptions: freezed == sqlServerBackupOptions ? _self.sqlServerBackupOptions : sqlServerBackupOptions // ignore: cast_nullable_to_non_nullable
as SqlServerBackupOptions?,sybaseBackupOptions: freezed == sybaseBackupOptions ? _self.sybaseBackupOptions : sybaseBackupOptions // ignore: cast_nullable_to_non_nullable
as SybaseBackupOptions?,
  ));
}


}

// dart format on
