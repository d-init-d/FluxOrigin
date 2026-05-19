// Bug #4 Exploration Test: Hardcoded MSIX logo_path
//
// **Validates: Requirements 1.8, 2.8**
//
// Bug Condition (from design isBugCondition):
//   input is MsixBuildContext AND input.pubspec.msix_config.logo_path is absolutePath
//   AND NOT fileExists(input.pubspec.msix_config.logo_path) on input.machine
//
// EXPECTED OUTCOME on UNFIXED code:
//   Test FAILS — logoPath is "D:\FluxOrigin\assets\fluxorigin logo.png" which is
//   absolute AND does not exist on the test machine.

import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:yaml/yaml.dart';

void main() {
  group('Bug #4 — Hardcoded MSIX logo_path', () {
    late String repoRoot;
    late String pubspecContent;
    late YamlMap pubspec;

    setUp(() {
      // Resolve the repo root from the test file location.
      // Tests run from the project root, so Platform.environment or
      // Directory.current should point there.
      repoRoot = Directory.current.path;
      final pubspecFile = File(path.join(repoRoot, 'pubspec.yaml'));
      expect(pubspecFile.existsSync(), isTrue,
          reason: 'pubspec.yaml must exist at repo root: $repoRoot');
      pubspecContent = pubspecFile.readAsStringSync();
      pubspec = loadYaml(pubspecContent) as YamlMap;
    });

    test(
        'Property 1.4: msix_config.logo_path must be workspace-relative (not absolute)',
        () {
      // Extract msix_config.logo_path
      final msixConfig = pubspec['msix_config'] as YamlMap?;
      expect(msixConfig, isNotNull,
          reason: 'pubspec.yaml must contain msix_config section');

      final logoPath = msixConfig!['logo_path'] as String?;
      expect(logoPath, isNotNull,
          reason: 'msix_config must contain logo_path key');

      // Property 1: logo_path must NOT be absolute
      // On unfixed code this will be "D:\FluxOrigin\assets\fluxorigin logo.png"
      final isAbsolute = path.isAbsolute(logoPath!);
      expect(isAbsolute, isFalse,
          reason:
              'logo_path must be workspace-relative, but got absolute path: "$logoPath"');
    });

    test(
        'Property 1.4: resolved logo_path must point to a committed asset that exists',
        () {
      final msixConfig = pubspec['msix_config'] as YamlMap?;
      expect(msixConfig, isNotNull);

      final logoPath = msixConfig!['logo_path'] as String?;
      expect(logoPath, isNotNull);

      // Resolve the path relative to repo root
      final resolvedPath = path.join(repoRoot, logoPath!);
      final logoFile = File(resolvedPath);

      // Property 2: The resolved path must point to an existing file
      // On unfixed code, the absolute path "D:\FluxOrigin\assets\fluxorigin logo.png"
      // will not exist on any machine other than the original developer's.
      expect(logoFile.existsSync(), isTrue,
          reason:
              'Resolved logo_path "$resolvedPath" must exist on disk. '
              'If this fails, the MSIX build will fail with "logo not found".');
    });
  });
}
