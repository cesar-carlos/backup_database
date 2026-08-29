import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/theme/app_theme.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/presentation/widgets/destinations/destination_dialog.dart';
import 'package:backup_database/presentation/widgets/organisms/app_dialog_shell.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../../unit/helpers/mock_repositories.dart';

void main() {
  late MockLicenseValidationService mockLicenseValidation;
  late MockLicenseRepository mockLicenseRepo;
  late MockDeviceKeyService mockDeviceKey;
  late MockLicenseGenerationService mockLicenseGeneration;

  setUp(() {
    mockLicenseValidation = MockLicenseValidationService();
    mockLicenseRepo = MockLicenseRepository();
    mockDeviceKey = MockDeviceKeyService();
    mockLicenseGeneration = MockLicenseGenerationService();

    when(() => mockLicenseValidation.getStoredLicense()).thenAnswer(
      (_) async => const rd.Failure(
        NotFoundFailure(message: 'No license'),
      ),
    );
    when(() => mockLicenseValidation.getCurrentLicense()).thenAnswer(
      (_) async => const rd.Failure(
        NotFoundFailure(message: 'No license'),
      ),
    );
    when(() => mockDeviceKey.getDeviceKey()).thenAnswer(
      (_) async => const rd.Success('test-device-key'),
    );
  });

  testWidgets(
    'DestinationDialog shows title and destination type dropdown',
    (WidgetTester tester) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final licenseProvider = LicenseProvider(
        validationService: mockLicenseValidation,
        generationService: mockLicenseGeneration,
        licenseRepository: mockLicenseRepo,
        deviceKeyService: mockDeviceKey,
      );

      await tester.pumpWidget(
        FluentApp(
          locale: const Locale('pt'),
          theme: AppTheme.lightFluentTheme,
          home: ChangeNotifierProvider<LicenseProvider>.value(
            value: licenseProvider,
            child: const DestinationDialog(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppDialogShell), findsOneWidget);
      expect(find.text('Novo destino'), findsOneWidget);
      expect(find.text('Tipo de destino'), findsWidgets);
      expect(find.text('Caminho da pasta'), findsOneWidget);

      await tester.tap(find.byType(ComboBox<DestinationType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Servidor FTP').last);
      await tester.pumpAndSettle();
      expect(find.text('Configuracao FTP'), findsOneWidget);

      await tester.tap(find.byType(ComboBox<DestinationType>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pasta local').last);
      await tester.pumpAndSettle();
      expect(find.text('Caminho da pasta'), findsOneWidget);
    },
  );
}
