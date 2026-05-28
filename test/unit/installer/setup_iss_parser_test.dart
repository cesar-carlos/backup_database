import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'setup_iss_parser.dart';

void main() {
  group('SetupIssParser', () {
    const sample = r'''
[Setup]
AppName=Sample

[Tasks]
Name: "checkedTask"; Description: "On"; Flags: checked
Name: "uncheckedTask"; Description: "Off"

[Icons]
Name: "{group}\App"; Filename: "{app}\app.exe"
Name: "{autodesktop}\App"; Filename: "{app}\app.exe"; Tasks: desktopicon

[Code]
procedure Hello(); forward;
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  AppExe: String;
begin
  Result := '';
  AppExe := 'app.exe';
  Log('hello world');
end;

procedure Hello();
begin
  Log('from hello');
end;
''';

    test('section returns body without the header line', () {
      final iss = SetupIssParser(sample);
      final tasks = iss.section('Tasks');
      expect(tasks, contains('checkedTask'));
      expect(tasks, contains('uncheckedTask'));
      expect(tasks, isNot(contains('[Tasks]')));
    });

    test('section returns empty string for missing section', () {
      final iss = SetupIssParser(sample);
      expect(iss.section('Registry'), isEmpty);
    });

    test('hasTask matches plain entries', () {
      final iss = SetupIssParser(sample);
      expect(iss.hasTask('checkedTask'), isTrue);
      expect(iss.hasTask('uncheckedTask'), isTrue);
      expect(iss.hasTask('missing'), isFalse);
    });

    test('hasTask with hasFlag requires the flag to be present', () {
      final iss = SetupIssParser(sample);
      expect(iss.hasTask('checkedTask', hasFlag: 'checked'), isTrue);
      expect(iss.hasTask('uncheckedTask', hasFlag: 'checked'), isFalse);
    });

    test('iconEntry returns the entry line or null', () {
      final iss = SetupIssParser(sample);
      final entry = iss.iconEntry(r'{autodesktop}\App');
      expect(entry, isNotNull);
      expect(entry, contains('Tasks: desktopicon'));
      expect(iss.iconEntry(r'{group}\Missing'), isNull);
    });

    test('hasForwardDeclaration detects the prelude declaration', () {
      final iss = SetupIssParser(sample);
      expect(iss.hasForwardDeclaration('Hello'), isTrue);
      expect(iss.hasForwardDeclaration('PrepareToInstall'), isFalse);
    });

    test('routineBody extracts the body up to end;', () {
      final iss = SetupIssParser(sample);
      final body = iss.routineBody('PrepareToInstall');
      expect(body, isNotNull);
      expect(body, contains('Result :='));
      expect(body, contains("Log('hello world')"));
      expect(body, contains('end;'));
    });

    test('routineContains scopes the contains check to the routine', () {
      final iss = SetupIssParser(sample);
      expect(
        iss.routineContains('PrepareToInstall', "Log('hello world')"),
        isTrue,
      );
      // String exists ONLY in the other routine — must not bleed.
      expect(
        iss.routineContains('PrepareToInstall', "Log('from hello')"),
        isFalse,
      );
      expect(
        iss.routineContains('Hello', "Log('from hello')"),
        isTrue,
      );
    });

    test('routineBody returns null when routine is missing', () {
      final iss = SetupIssParser(sample);
      expect(iss.routineBody('Missing'), isNull);
      expect(iss.routineContains('Missing', 'anything'), isFalse);
    });

    test('fromFile expands #include directives recursively', () async {
      final tempDir = await Directory.systemTemp.createTemp('iss_include_test');
      try {
        final mainPath = p.join(tempDir.path, 'main.iss');
        final subDir = Directory(p.join(tempDir.path, 'code'))
          ..createSync(recursive: true);
        final iconsPath = p.join(subDir.path, 'icons.iss');
        final nestedPath = p.join(subDir.path, 'nested.iss');

        File(nestedPath).writeAsStringSync('''
procedure NestedHelper();
begin
  Log('nested');
end;
''');
        File(iconsPath).writeAsStringSync('''
#include "nested.iss"

procedure IconHelper();
begin
  Log('icon');
end;
''');
        File(mainPath).writeAsStringSync('''
[Setup]
AppName=Test

[Code]
#include "code/icons.iss"

procedure Main();
begin
  IconHelper();
end;
''');

        final iss = SetupIssParser.fromFile(File(mainPath));
        expect(iss.routineContains('IconHelper', "Log('icon')"), isTrue);
        expect(iss.routineContains('NestedHelper', "Log('nested')"), isTrue);
        expect(iss.routineContains('Main', 'IconHelper()'), isTrue);
      } finally {
        await tempDir.delete(recursive: true);
      }
    });
  });
}
