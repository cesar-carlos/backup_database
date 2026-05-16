import 'package:backup_database/core/theme/tokens/app_palette.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppPalette', () {
    test('database brand colors are compile-time constants', () {
      const sql = AppPalette.databaseSqlServer;
      const sybase = AppPalette.databaseSybase;
      const pg = AppPalette.databasePostgresql;
      const fb = AppPalette.databaseFirebird;
      expect(sql, const Color(0xFFCC2927));
      expect(sybase, const Color(0xFF009688));
      expect(pg, const Color(0xFF336791));
      expect(fb, const Color(0xFFF40F02));
    });

    test('primary accent is stable', () {
      const p = AppPalette.primary;
      expect(p, const Color(0xFF1565C0));
    });
  });
}
