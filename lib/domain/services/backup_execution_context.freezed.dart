// GENERATED CODE - DO NOT MODIFY BY HAND
// coverage:ignore-file
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'backup_execution_context.dart';

// **************************************************************************
// FreezedGenerator
// **************************************************************************

// dart format off
T _$identity<T>(T value) => value;
/// @nodoc
mixin _$BackupExecutionContext {

 String get outputDirectory; String get scheduleId; BackupType get backupType; String? get customFileName; bool get truncateLog; bool get enableChecksum; bool get verifyAfterBackup; VerifyPolicy get verifyPolicy; SqlServerBackupOptions? get sqlServerBackupOptions; Duration? get backupTimeout; Duration? get verifyTimeout; String? get cancelTag; String? get pgBasebackupPath; String? get dbbackupPath; SybaseBackupOptions? get sybaseBackupOptions; int? get firebirdNbackupPhysicalLevel;
/// Create a copy of BackupExecutionContext
/// with the given fields replaced by the non-null parameter values.
@JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
$BackupExecutionContextCopyWith<BackupExecutionContext> get copyWith => _$BackupExecutionContextCopyWithImpl<BackupExecutionContext>(this as BackupExecutionContext, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is BackupExecutionContext&&(identical(other.outputDirectory, outputDirectory) || other.outputDirectory == outputDirectory)&&(identical(other.scheduleId, scheduleId) || other.scheduleId == scheduleId)&&(identical(other.backupType, backupType) || other.backupType == backupType)&&(identical(other.customFileName, customFileName) || other.customFileName == customFileName)&&(identical(other.truncateLog, truncateLog) || other.truncateLog == truncateLog)&&(identical(other.enableChecksum, enableChecksum) || other.enableChecksum == enableChecksum)&&(identical(other.verifyAfterBackup, verifyAfterBackup) || other.verifyAfterBackup == verifyAfterBackup)&&(identical(other.verifyPolicy, verifyPolicy) || other.verifyPolicy == verifyPolicy)&&(identical(other.sqlServerBackupOptions, sqlServerBackupOptions) || other.sqlServerBackupOptions == sqlServerBackupOptions)&&(identical(other.backupTimeout, backupTimeout) || other.backupTimeout == backupTimeout)&&(identical(other.verifyTimeout, verifyTimeout) || other.verifyTimeout == verifyTimeout)&&(identical(other.cancelTag, cancelTag) || other.cancelTag == cancelTag)&&(identical(other.pgBasebackupPath, pgBasebackupPath) || other.pgBasebackupPath == pgBasebackupPath)&&(identical(other.dbbackupPath, dbbackupPath) || other.dbbackupPath == dbbackupPath)&&(identical(other.sybaseBackupOptions, sybaseBackupOptions) || other.sybaseBackupOptions == sybaseBackupOptions)&&(identical(other.firebirdNbackupPhysicalLevel, firebirdNbackupPhysicalLevel) || other.firebirdNbackupPhysicalLevel == firebirdNbackupPhysicalLevel));
}


@override
int get hashCode => Object.hash(runtimeType,outputDirectory,scheduleId,backupType,customFileName,truncateLog,enableChecksum,verifyAfterBackup,verifyPolicy,sqlServerBackupOptions,backupTimeout,verifyTimeout,cancelTag,pgBasebackupPath,dbbackupPath,sybaseBackupOptions,firebirdNbackupPhysicalLevel);

@override
String toString() {
  return 'BackupExecutionContext(outputDirectory: $outputDirectory, scheduleId: $scheduleId, backupType: $backupType, customFileName: $customFileName, truncateLog: $truncateLog, enableChecksum: $enableChecksum, verifyAfterBackup: $verifyAfterBackup, verifyPolicy: $verifyPolicy, sqlServerBackupOptions: $sqlServerBackupOptions, backupTimeout: $backupTimeout, verifyTimeout: $verifyTimeout, cancelTag: $cancelTag, pgBasebackupPath: $pgBasebackupPath, dbbackupPath: $dbbackupPath, sybaseBackupOptions: $sybaseBackupOptions, firebirdNbackupPhysicalLevel: $firebirdNbackupPhysicalLevel)';
}


}

/// @nodoc
abstract mixin class $BackupExecutionContextCopyWith<$Res>  {
  factory $BackupExecutionContextCopyWith(BackupExecutionContext value, $Res Function(BackupExecutionContext) _then) = _$BackupExecutionContextCopyWithImpl;
@useResult
$Res call({
 String outputDirectory, String scheduleId, BackupType backupType, String? customFileName, bool truncateLog, bool enableChecksum, bool verifyAfterBackup, VerifyPolicy verifyPolicy, SqlServerBackupOptions? sqlServerBackupOptions, Duration? backupTimeout, Duration? verifyTimeout, String? cancelTag, String? pgBasebackupPath, String? dbbackupPath, SybaseBackupOptions? sybaseBackupOptions, int? firebirdNbackupPhysicalLevel
});




}
/// @nodoc
class _$BackupExecutionContextCopyWithImpl<$Res>
    implements $BackupExecutionContextCopyWith<$Res> {
  _$BackupExecutionContextCopyWithImpl(this._self, this._then);

  final BackupExecutionContext _self;
  final $Res Function(BackupExecutionContext) _then;

/// Create a copy of BackupExecutionContext
/// with the given fields replaced by the non-null parameter values.
@pragma('vm:prefer-inline') @override $Res call({Object? outputDirectory = null,Object? scheduleId = null,Object? backupType = null,Object? customFileName = freezed,Object? truncateLog = null,Object? enableChecksum = null,Object? verifyAfterBackup = null,Object? verifyPolicy = null,Object? sqlServerBackupOptions = freezed,Object? backupTimeout = freezed,Object? verifyTimeout = freezed,Object? cancelTag = freezed,Object? pgBasebackupPath = freezed,Object? dbbackupPath = freezed,Object? sybaseBackupOptions = freezed,Object? firebirdNbackupPhysicalLevel = freezed,}) {
  return _then(_self.copyWith(
outputDirectory: null == outputDirectory ? _self.outputDirectory : outputDirectory // ignore: cast_nullable_to_non_nullable
as String,scheduleId: null == scheduleId ? _self.scheduleId : scheduleId // ignore: cast_nullable_to_non_nullable
as String,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as BackupType,customFileName: freezed == customFileName ? _self.customFileName : customFileName // ignore: cast_nullable_to_non_nullable
as String?,truncateLog: null == truncateLog ? _self.truncateLog : truncateLog // ignore: cast_nullable_to_non_nullable
as bool,enableChecksum: null == enableChecksum ? _self.enableChecksum : enableChecksum // ignore: cast_nullable_to_non_nullable
as bool,verifyAfterBackup: null == verifyAfterBackup ? _self.verifyAfterBackup : verifyAfterBackup // ignore: cast_nullable_to_non_nullable
as bool,verifyPolicy: null == verifyPolicy ? _self.verifyPolicy : verifyPolicy // ignore: cast_nullable_to_non_nullable
as VerifyPolicy,sqlServerBackupOptions: freezed == sqlServerBackupOptions ? _self.sqlServerBackupOptions : sqlServerBackupOptions // ignore: cast_nullable_to_non_nullable
as SqlServerBackupOptions?,backupTimeout: freezed == backupTimeout ? _self.backupTimeout : backupTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,verifyTimeout: freezed == verifyTimeout ? _self.verifyTimeout : verifyTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,cancelTag: freezed == cancelTag ? _self.cancelTag : cancelTag // ignore: cast_nullable_to_non_nullable
as String?,pgBasebackupPath: freezed == pgBasebackupPath ? _self.pgBasebackupPath : pgBasebackupPath // ignore: cast_nullable_to_non_nullable
as String?,dbbackupPath: freezed == dbbackupPath ? _self.dbbackupPath : dbbackupPath // ignore: cast_nullable_to_non_nullable
as String?,sybaseBackupOptions: freezed == sybaseBackupOptions ? _self.sybaseBackupOptions : sybaseBackupOptions // ignore: cast_nullable_to_non_nullable
as SybaseBackupOptions?,firebirdNbackupPhysicalLevel: freezed == firebirdNbackupPhysicalLevel ? _self.firebirdNbackupPhysicalLevel : firebirdNbackupPhysicalLevel // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}

}


/// Adds pattern-matching-related methods to [BackupExecutionContext].
extension BackupExecutionContextPatterns on BackupExecutionContext {
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

@optionalTypeArgs TResult maybeMap<TResult extends Object?>(TResult Function( _BackupExecutionContext value)?  $default,{required TResult orElse(),}){
final _that = this;
switch (_that) {
case _BackupExecutionContext() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult map<TResult extends Object?>(TResult Function( _BackupExecutionContext value)  $default,){
final _that = this;
switch (_that) {
case _BackupExecutionContext():
return $default(_that);case _:
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

@optionalTypeArgs TResult? mapOrNull<TResult extends Object?>(TResult? Function( _BackupExecutionContext value)?  $default,){
final _that = this;
switch (_that) {
case _BackupExecutionContext() when $default != null:
return $default(_that);case _:
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

@optionalTypeArgs TResult maybeWhen<TResult extends Object?>(TResult Function( String outputDirectory,  String scheduleId,  BackupType backupType,  String? customFileName,  bool truncateLog,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  SqlServerBackupOptions? sqlServerBackupOptions,  Duration? backupTimeout,  Duration? verifyTimeout,  String? cancelTag,  String? pgBasebackupPath,  String? dbbackupPath,  SybaseBackupOptions? sybaseBackupOptions,  int? firebirdNbackupPhysicalLevel)?  $default,{required TResult orElse(),}) {final _that = this;
switch (_that) {
case _BackupExecutionContext() when $default != null:
return $default(_that.outputDirectory,_that.scheduleId,_that.backupType,_that.customFileName,_that.truncateLog,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.sqlServerBackupOptions,_that.backupTimeout,_that.verifyTimeout,_that.cancelTag,_that.pgBasebackupPath,_that.dbbackupPath,_that.sybaseBackupOptions,_that.firebirdNbackupPhysicalLevel);case _:
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

@optionalTypeArgs TResult when<TResult extends Object?>(TResult Function( String outputDirectory,  String scheduleId,  BackupType backupType,  String? customFileName,  bool truncateLog,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  SqlServerBackupOptions? sqlServerBackupOptions,  Duration? backupTimeout,  Duration? verifyTimeout,  String? cancelTag,  String? pgBasebackupPath,  String? dbbackupPath,  SybaseBackupOptions? sybaseBackupOptions,  int? firebirdNbackupPhysicalLevel)  $default,) {final _that = this;
switch (_that) {
case _BackupExecutionContext():
return $default(_that.outputDirectory,_that.scheduleId,_that.backupType,_that.customFileName,_that.truncateLog,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.sqlServerBackupOptions,_that.backupTimeout,_that.verifyTimeout,_that.cancelTag,_that.pgBasebackupPath,_that.dbbackupPath,_that.sybaseBackupOptions,_that.firebirdNbackupPhysicalLevel);case _:
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

@optionalTypeArgs TResult? whenOrNull<TResult extends Object?>(TResult? Function( String outputDirectory,  String scheduleId,  BackupType backupType,  String? customFileName,  bool truncateLog,  bool enableChecksum,  bool verifyAfterBackup,  VerifyPolicy verifyPolicy,  SqlServerBackupOptions? sqlServerBackupOptions,  Duration? backupTimeout,  Duration? verifyTimeout,  String? cancelTag,  String? pgBasebackupPath,  String? dbbackupPath,  SybaseBackupOptions? sybaseBackupOptions,  int? firebirdNbackupPhysicalLevel)?  $default,) {final _that = this;
switch (_that) {
case _BackupExecutionContext() when $default != null:
return $default(_that.outputDirectory,_that.scheduleId,_that.backupType,_that.customFileName,_that.truncateLog,_that.enableChecksum,_that.verifyAfterBackup,_that.verifyPolicy,_that.sqlServerBackupOptions,_that.backupTimeout,_that.verifyTimeout,_that.cancelTag,_that.pgBasebackupPath,_that.dbbackupPath,_that.sybaseBackupOptions,_that.firebirdNbackupPhysicalLevel);case _:
  return null;

}
}

}

/// @nodoc


class _BackupExecutionContext implements BackupExecutionContext {
  const _BackupExecutionContext({required this.outputDirectory, required this.scheduleId, this.backupType = BackupType.full, this.customFileName, this.truncateLog = true, this.enableChecksum = false, this.verifyAfterBackup = false, this.verifyPolicy = VerifyPolicy.bestEffort, this.sqlServerBackupOptions, this.backupTimeout, this.verifyTimeout, this.cancelTag, this.pgBasebackupPath, this.dbbackupPath, this.sybaseBackupOptions, this.firebirdNbackupPhysicalLevel});
  

@override final  String outputDirectory;
@override final  String scheduleId;
@override@JsonKey() final  BackupType backupType;
@override final  String? customFileName;
@override@JsonKey() final  bool truncateLog;
@override@JsonKey() final  bool enableChecksum;
@override@JsonKey() final  bool verifyAfterBackup;
@override@JsonKey() final  VerifyPolicy verifyPolicy;
@override final  SqlServerBackupOptions? sqlServerBackupOptions;
@override final  Duration? backupTimeout;
@override final  Duration? verifyTimeout;
@override final  String? cancelTag;
@override final  String? pgBasebackupPath;
@override final  String? dbbackupPath;
@override final  SybaseBackupOptions? sybaseBackupOptions;
@override final  int? firebirdNbackupPhysicalLevel;

/// Create a copy of BackupExecutionContext
/// with the given fields replaced by the non-null parameter values.
@override @JsonKey(includeFromJson: false, includeToJson: false)
@pragma('vm:prefer-inline')
_$BackupExecutionContextCopyWith<_BackupExecutionContext> get copyWith => __$BackupExecutionContextCopyWithImpl<_BackupExecutionContext>(this, _$identity);



@override
bool operator ==(Object other) {
  return identical(this, other) || (other.runtimeType == runtimeType&&other is _BackupExecutionContext&&(identical(other.outputDirectory, outputDirectory) || other.outputDirectory == outputDirectory)&&(identical(other.scheduleId, scheduleId) || other.scheduleId == scheduleId)&&(identical(other.backupType, backupType) || other.backupType == backupType)&&(identical(other.customFileName, customFileName) || other.customFileName == customFileName)&&(identical(other.truncateLog, truncateLog) || other.truncateLog == truncateLog)&&(identical(other.enableChecksum, enableChecksum) || other.enableChecksum == enableChecksum)&&(identical(other.verifyAfterBackup, verifyAfterBackup) || other.verifyAfterBackup == verifyAfterBackup)&&(identical(other.verifyPolicy, verifyPolicy) || other.verifyPolicy == verifyPolicy)&&(identical(other.sqlServerBackupOptions, sqlServerBackupOptions) || other.sqlServerBackupOptions == sqlServerBackupOptions)&&(identical(other.backupTimeout, backupTimeout) || other.backupTimeout == backupTimeout)&&(identical(other.verifyTimeout, verifyTimeout) || other.verifyTimeout == verifyTimeout)&&(identical(other.cancelTag, cancelTag) || other.cancelTag == cancelTag)&&(identical(other.pgBasebackupPath, pgBasebackupPath) || other.pgBasebackupPath == pgBasebackupPath)&&(identical(other.dbbackupPath, dbbackupPath) || other.dbbackupPath == dbbackupPath)&&(identical(other.sybaseBackupOptions, sybaseBackupOptions) || other.sybaseBackupOptions == sybaseBackupOptions)&&(identical(other.firebirdNbackupPhysicalLevel, firebirdNbackupPhysicalLevel) || other.firebirdNbackupPhysicalLevel == firebirdNbackupPhysicalLevel));
}


@override
int get hashCode => Object.hash(runtimeType,outputDirectory,scheduleId,backupType,customFileName,truncateLog,enableChecksum,verifyAfterBackup,verifyPolicy,sqlServerBackupOptions,backupTimeout,verifyTimeout,cancelTag,pgBasebackupPath,dbbackupPath,sybaseBackupOptions,firebirdNbackupPhysicalLevel);

@override
String toString() {
  return 'BackupExecutionContext(outputDirectory: $outputDirectory, scheduleId: $scheduleId, backupType: $backupType, customFileName: $customFileName, truncateLog: $truncateLog, enableChecksum: $enableChecksum, verifyAfterBackup: $verifyAfterBackup, verifyPolicy: $verifyPolicy, sqlServerBackupOptions: $sqlServerBackupOptions, backupTimeout: $backupTimeout, verifyTimeout: $verifyTimeout, cancelTag: $cancelTag, pgBasebackupPath: $pgBasebackupPath, dbbackupPath: $dbbackupPath, sybaseBackupOptions: $sybaseBackupOptions, firebirdNbackupPhysicalLevel: $firebirdNbackupPhysicalLevel)';
}


}

/// @nodoc
abstract mixin class _$BackupExecutionContextCopyWith<$Res> implements $BackupExecutionContextCopyWith<$Res> {
  factory _$BackupExecutionContextCopyWith(_BackupExecutionContext value, $Res Function(_BackupExecutionContext) _then) = __$BackupExecutionContextCopyWithImpl;
@override @useResult
$Res call({
 String outputDirectory, String scheduleId, BackupType backupType, String? customFileName, bool truncateLog, bool enableChecksum, bool verifyAfterBackup, VerifyPolicy verifyPolicy, SqlServerBackupOptions? sqlServerBackupOptions, Duration? backupTimeout, Duration? verifyTimeout, String? cancelTag, String? pgBasebackupPath, String? dbbackupPath, SybaseBackupOptions? sybaseBackupOptions, int? firebirdNbackupPhysicalLevel
});




}
/// @nodoc
class __$BackupExecutionContextCopyWithImpl<$Res>
    implements _$BackupExecutionContextCopyWith<$Res> {
  __$BackupExecutionContextCopyWithImpl(this._self, this._then);

  final _BackupExecutionContext _self;
  final $Res Function(_BackupExecutionContext) _then;

/// Create a copy of BackupExecutionContext
/// with the given fields replaced by the non-null parameter values.
@override @pragma('vm:prefer-inline') $Res call({Object? outputDirectory = null,Object? scheduleId = null,Object? backupType = null,Object? customFileName = freezed,Object? truncateLog = null,Object? enableChecksum = null,Object? verifyAfterBackup = null,Object? verifyPolicy = null,Object? sqlServerBackupOptions = freezed,Object? backupTimeout = freezed,Object? verifyTimeout = freezed,Object? cancelTag = freezed,Object? pgBasebackupPath = freezed,Object? dbbackupPath = freezed,Object? sybaseBackupOptions = freezed,Object? firebirdNbackupPhysicalLevel = freezed,}) {
  return _then(_BackupExecutionContext(
outputDirectory: null == outputDirectory ? _self.outputDirectory : outputDirectory // ignore: cast_nullable_to_non_nullable
as String,scheduleId: null == scheduleId ? _self.scheduleId : scheduleId // ignore: cast_nullable_to_non_nullable
as String,backupType: null == backupType ? _self.backupType : backupType // ignore: cast_nullable_to_non_nullable
as BackupType,customFileName: freezed == customFileName ? _self.customFileName : customFileName // ignore: cast_nullable_to_non_nullable
as String?,truncateLog: null == truncateLog ? _self.truncateLog : truncateLog // ignore: cast_nullable_to_non_nullable
as bool,enableChecksum: null == enableChecksum ? _self.enableChecksum : enableChecksum // ignore: cast_nullable_to_non_nullable
as bool,verifyAfterBackup: null == verifyAfterBackup ? _self.verifyAfterBackup : verifyAfterBackup // ignore: cast_nullable_to_non_nullable
as bool,verifyPolicy: null == verifyPolicy ? _self.verifyPolicy : verifyPolicy // ignore: cast_nullable_to_non_nullable
as VerifyPolicy,sqlServerBackupOptions: freezed == sqlServerBackupOptions ? _self.sqlServerBackupOptions : sqlServerBackupOptions // ignore: cast_nullable_to_non_nullable
as SqlServerBackupOptions?,backupTimeout: freezed == backupTimeout ? _self.backupTimeout : backupTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,verifyTimeout: freezed == verifyTimeout ? _self.verifyTimeout : verifyTimeout // ignore: cast_nullable_to_non_nullable
as Duration?,cancelTag: freezed == cancelTag ? _self.cancelTag : cancelTag // ignore: cast_nullable_to_non_nullable
as String?,pgBasebackupPath: freezed == pgBasebackupPath ? _self.pgBasebackupPath : pgBasebackupPath // ignore: cast_nullable_to_non_nullable
as String?,dbbackupPath: freezed == dbbackupPath ? _self.dbbackupPath : dbbackupPath // ignore: cast_nullable_to_non_nullable
as String?,sybaseBackupOptions: freezed == sybaseBackupOptions ? _self.sybaseBackupOptions : sybaseBackupOptions // ignore: cast_nullable_to_non_nullable
as SybaseBackupOptions?,firebirdNbackupPhysicalLevel: freezed == firebirdNbackupPhysicalLevel ? _self.firebirdNbackupPhysicalLevel : firebirdNbackupPhysicalLevel // ignore: cast_nullable_to_non_nullable
as int?,
  ));
}


}

// dart format on
