import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// D03c-A.2 / C1 - automated non-coupling guard for `cbs_flutter_ux`.
///
/// The package must stay independent of its consumers (AMH-USR) and of
/// core-platform. This test enforces that statically, with `dart:io`, the
/// SDK `Uri` class and `flutter_test` only (no extra dependency):
///
/// 1. `pubspec.yaml` declares the Flutter SDK at runtime, `flutter_test` and
///    `flutter_lints` for development, and no dependency override.
/// 2. Every `import` / `export` / `part` directive of `lib/` and
///    `example/lib/` targets only `dart:*`, `package:flutter/*`,
///    `package:cbs_flutter_ux/*` or a relative file inside its own tree.
/// 3. Comments are removed and string literals are set aside before the
///    directives are searched, so documentation that mentions AMH-USR never
///    produces a false positive. A string literal that itself references
///    `package:amh_usr` or `package:core_platform` is reported.
/// 4. Anything that cannot be verified is reported, never skipped (fail
///    closed): unterminated comment or string, escape or interpolation in a
///    URI, directive without URI, unsupported pubspec syntax, symbolic link,
///    missing tree.
/// 5. The checker is proven on temporary fixture packages created outside
///    the repository: every injected violation must be reported.
///
/// This is deliberately not a Dart or YAML parser. Known limits: strings
/// containing a nested interpolation with the other quote character are not
/// understood; the `pubspec.yaml` reader accepts only the plain block layout
/// of the dependency sections; a consumer type merely re-declared in CBS
/// code, or a reference built at runtime, cannot be detected.

// ---------------------------------------------------------------------------
// Policy
// ---------------------------------------------------------------------------

/// Directory trees scanned, relative to the package root. A relative
/// directive must resolve inside the tree of the file that declares it.
const List<String> _perimeters = ['lib', 'example/lib'];

const Set<String> _allowedPackages = {'flutter', 'cbs_flutter_ux'};

/// Allowed dependencies per section: `true` = Flutter SDK dependency
/// (`sdk: flutter`), `false` = plain version constraint (`^6.0.0`).
const Map<String, Map<String, bool>> _allowedDependencies = {
  'dependencies': {'flutter': true},
  'dev_dependencies': {'flutter_test': true, 'flutter_lints': false},
};

/// Consumers known to the CBS repository: AMH-USR and core-platform, as a
/// package name (`amh_usr`) or as a directory name (`amh-usr`).
const String _consumers = r'amh[_-]?usr|core[_-]?platform';
final RegExp _consumerName = RegExp('^($_consumers)', caseSensitive: false);
final RegExp _consumerPackageReference = RegExp(
  'package:($_consumers)',
  caseSensitive: false,
);

typedef _Problem = ({String rule, String message});

// ---------------------------------------------------------------------------
// Dart sources
// ---------------------------------------------------------------------------

const String _mark = '\u0001';
final RegExp _wordChar = RegExp(r'[\w$]');
final RegExp _stringMarker = RegExp('$_mark(\\d+)$_mark');
final RegExp _uriForbiddenCharacter = RegExp(r'[\x00-\x1f\x7f\\%$]');

/// `import`, `export` or `part`, optionally followed by `augment` / `of`,
/// and the first character after it.
final RegExp _directiveKeyword = RegExp(
  r'(?<![\w$.])(import|export|part)(?![\w$])\s*'
  r'(?:(augment|of)(?![\w$])\s*)?(.?)',
);

int _lineOf(String text, int offset) =>
    '\n'.allMatches(text.substring(0, offset)).length + 1;

/// Removes the comments of [source] (Dart block comments nest) and replaces
/// every string literal by a marker `\u0001<index>\u0001`, keeping the line
/// count. The literal text, as written, is returned in `strings`. A
/// directive-looking text inside a comment or a string is therefore never
/// seen as code. Throws a [FormatException] on an unterminated comment or
/// string literal.
({String code, List<String> strings}) _splitCode(String source) {
  final code = StringBuffer();
  final strings = <String>[];
  var i = 0;
  while (i < source.length) {
    final c = source[i];
    if (source.startsWith('//', i)) {
      while (i < source.length && source[i] != '\n') {
        i++;
      }
      code.write(' ');
    } else if (source.startsWith('/*', i)) {
      final start = i;
      var depth = 0;
      do {
        if (i >= source.length) {
          throw FormatException('Unterminated block comment.', source, start);
        }
        if (source.startsWith('/*', i)) {
          depth++;
          i += 2;
        } else if (source.startsWith('*/', i)) {
          depth--;
          i += 2;
        } else {
          if (source[i] == '\n') code.write('\n');
          i++;
        }
      } while (depth > 0);
      code.write(' ');
    } else if (c == "'" || c == '"') {
      final raw =
          i > 0 &&
          source[i - 1] == 'r' &&
          (i == 1 || !_wordChar.hasMatch(source[i - 2]));
      final triple = source.startsWith(c * 3, i);
      final close = triple ? c * 3 : c;
      var j = i + close.length;
      while (true) {
        if (j >= source.length ||
            (!triple && (source[j] == '\n' || source[j] == '\r'))) {
          throw FormatException('Unterminated string literal.', source, i);
        }
        if (source.startsWith(close, j)) break;
        j += (!raw && source[j] == r'\') ? 2 : 1;
      }
      final text = source.substring(i + close.length, j);
      code.write(
        '$_mark${strings.length}$_mark${'\n' * '\n'.allMatches(text).length}',
      );
      strings.add(text);
      i = j + close.length;
    } else {
      code.write(c);
      i++;
    }
  }
  return (code: code.toString(), strings: strings);
}

/// Returns why [uri] is forbidden for a file located in [fileDirectory]
/// (package-relative, e.g. `lib/src`) inside [perimeter], or null.
_Problem? _uriProblem(String uri, String fileDirectory, String perimeter) {
  _Problem unverifiable() => (
    rule: 'uri-unverifiable',
    message:
        'URI "$uri" is empty or contains an escape, interpolation, '
        'percent-encoding or control character; it cannot be verified.',
  );
  if (uri.isEmpty || _uriForbiddenCharacter.hasMatch(uri)) {
    return unverifiable();
  }
  final Uri parsed;
  try {
    parsed = Uri.parse(uri);
  } on FormatException {
    return unverifiable();
  }
  if (parsed.scheme == 'dart') return null;
  if (parsed.scheme == 'package') {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    final name = slash < 0 ? rest : rest.substring(0, slash);
    final path = slash < 0 ? '' : rest.substring(slash + 1);
    if (_consumerName.hasMatch(name)) {
      return (
        rule: 'consumer-import',
        message:
            'Import of consumer package "$name" ($uri) is forbidden. '
            'CBS must not depend on AMH-USR or core-platform.',
      );
    }
    if (!_allowedPackages.contains(name)) {
      return (
        rule: 'package-not-allowed',
        message:
            'Package "$name" ($uri) is not allowed. Only package:flutter/ '
            'and package:cbs_flutter_ux/ may be imported.',
      );
    }
    if (path.split('/').any((s) => s.isEmpty || s == '.' || s == '..')) {
      return (
        rule: 'uri-malformed',
        message: 'Package URI "$uri" is malformed.',
      );
    }
    return null;
  }
  if (parsed.hasScheme || parsed.hasAuthority || uri.startsWith('/')) {
    return (
      rule: 'uri-not-allowed',
      message:
          '"$uri" is not allowed. Allowed: dart:*, package:flutter/*, '
          'package:cbs_flutter_ux/* and relative paths inside "$perimeter/".',
    );
  }
  final resolved = Uri.parse('$fileDirectory/$uri')
      .normalizePath()
      .pathSegments;
  if (resolved.isNotEmpty &&
      resolved.first != '..' &&
      resolved.join('/').startsWith('$perimeter/')) {
    return null;
  }
  final where = resolved.isEmpty || resolved.first == '..'
      ? 'leaves the package directory'
      : 'resolves to "${resolved.join('/')}", outside "$perimeter/"';
  final consumer = uri.split('/').any(_consumerName.hasMatch)
      ? ' It points into a consumer (AMH-USR / core-platform).'
      : '';
  return (
    rule: 'relative-outside-perimeter',
    message:
        'Relative URI "$uri" $where.$consumer '
        'Use package:cbs_flutter_ux/ to cross trees.',
  );
}

/// Checks the directives and string literals of one Dart file.
///
/// [relativePath] is package-relative (`lib/src/a.dart`); [perimeter] is the
/// tree the file belongs to. `checkedStrings` lists every string literal
/// verified as a directive URI, including the `'true'` of a conditional
/// configuration.
({List<String> diagnostics, List<String> checkedStrings}) _checkDartSource(
  String source,
  String relativePath,
  String perimeter,
) {
  final ({String code, List<String> strings}) split;
  try {
    split = _splitCode(source);
  } on FormatException catch (e) {
    return (
      diagnostics: [
        '$relativePath:${_lineOf(source, e.offset ?? 0)}: [dart-unreadable] '
            '${e.message} Directives cannot be verified.',
      ],
      checkedStrings: const [],
    );
  }
  final (:code, :strings) = split;
  final fileDirectory = relativePath.substring(
    0,
    relativePath.lastIndexOf('/'),
  );
  final found = <(int, String)>[];
  void add(int offset, String rule, String message) => found.add((
    offset,
    '$relativePath:${_lineOf(code, offset)}: [$rule] $message',
  ));
  int markerAt(int index) => code.indexOf('$_mark$index$_mark');

  final directiveStrings = <int>{};
  final checkedStrings = <String>[];
  for (final match in _directiveKeyword.allMatches(code)) {
    final keyword = match[1]!;
    final next = match[3]!;
    if (next == _mark) {
      // Every string up to the ";" is a URI, including those of
      // `if (...) 'uri'` clauses and adjacent literals.
      final end = code.indexOf(';', match.start);
      if (end < 0) {
        add(
          match.start,
          'directive-unterminated',
          'The "$keyword" directive is not terminated by ";".',
        );
      }
      final window = code.substring(match.end - 1, end < 0 ? code.length : end);
      for (final marker in _stringMarker.allMatches(window)) {
        final index = int.parse(marker[1]!);
        if (!directiveStrings.add(index)) continue;
        checkedStrings.add(strings[index]);
        final problem = _uriProblem(strings[index], fileDirectory, perimeter);
        if (problem != null) {
          add(markerAt(index), problem.rule, problem.message);
        }
      }
    } else if (keyword != 'part' &&
        !(match[2] == null && next.isNotEmpty && ':=,.)]}'.contains(next))) {
      // `part of name;` has no URI; `import:` or `export = 1` are
      // identifiers. Any other `import` / `export` must name a URI.
      add(
        match.start,
        'directive-unreadable',
        'The "$keyword" directive has no readable URI literal; it cannot be '
            'verified.',
      );
    }
  }
  for (var index = 0; index < strings.length; index++) {
    if (!directiveStrings.contains(index) &&
        _consumerPackageReference.hasMatch(strings[index])) {
      add(
        markerAt(index),
        'consumer-reference',
        'String literal references a consumer package: "${strings[index]}".',
      );
    }
  }
  found.sort(
    (a, b) => a.$1 != b.$1 ? a.$1.compareTo(b.$1) : a.$2.compareTo(b.$2),
  );
  return (
    diagnostics: [for (final entry in found) entry.$2],
    checkedStrings: checkedStrings,
  );
}

// ---------------------------------------------------------------------------
// pubspec.yaml
// ---------------------------------------------------------------------------

final RegExp _yamlTopLevelKey = RegExp(r'^([A-Za-z_][\w.-]*):(?:\s+(.*))?$');
final RegExp _yamlPlainKey = RegExp(r'^([A-Za-z_]\w*):(?:\s+(.*))?$');

/// Returns the value of a YAML scalar written on one line. Flow collections,
/// anchors, aliases, tags and block scalars cannot be verified.
String _yamlScalar(String raw, String where) {
  final value = raw.trim();
  if (value.isNotEmpty && '{[&*!|>%@`'.contains(value[0])) {
    throw FormatException('$where: unsupported YAML value "$value".');
  }
  if (value.length >= 2 &&
      '\'"'.contains(value[0]) &&
      value.endsWith(value[0])) {
    return value.substring(1, value.length - 1);
  }
  return value;
}

/// Reads `dependencies`, `dev_dependencies` and `dependency_overrides` as
/// `section -> entry -> attribute -> value` (the inline value of an entry
/// uses the attribute ``). Only the plain two-level block layout is
/// supported; everything else throws a [FormatException].
Map<String, Map<String, Map<String, String>>> _readDependencySections(
  String source,
) {
  const names = ['dependencies', 'dev_dependencies', 'dependency_overrides'];
  final sections = <String, Map<String, Map<String, String>>>{};
  Map<String, Map<String, String>>? section;
  Map<String, String>? entry;
  final lines = source.split(RegExp(r'\r\n|\n|\r'));
  for (var n = 0; n < lines.length; n++) {
    final line = lines[n].replaceFirst(RegExp(r'(^|\s)#.*$'), '').trimRight();
    if (line.trim().isEmpty || line == '---') continue;
    final where = 'Line ${n + 1}';
    if (line.contains('\t')) {
      throw FormatException('$where: tab characters are not valid YAML.');
    }
    if (!line.startsWith(' ')) {
      final key = _yamlTopLevelKey.firstMatch(line);
      if (key == null) {
        throw FormatException('$where: unsupported top-level line "$line".');
      }
      section = null;
      entry = null;
      final name = key[1]!;
      if (!names.contains(name)) continue;
      if (sections.containsKey(name)) {
        throw FormatException('$where: duplicate key "$name".');
      }
      if ((key[2] ?? '').isNotEmpty) {
        throw FormatException(
          '$where: "$name" must be a block mapping; inline or flow syntax '
          'cannot be verified.',
        );
      }
      section = sections[name] = {};
      continue;
    }
    if (section == null) continue; // Indented content of another key.
    final indent = line.length - line.trimLeft().length;
    final pair = _yamlPlainKey.firstMatch(line.trim());
    if ((indent != 2 && indent != 4) || pair == null) {
      throw FormatException('$where: unsupported dependency syntax "$line".');
    }
    final value = _yamlScalar(pair[2] ?? '', where);
    if (indent == 2) {
      if (section.containsKey(pair[1])) {
        throw FormatException('$where: duplicate key "${pair[1]}".');
      }
      entry = section[pair[1]!] = {if (value.isNotEmpty) '': value};
    } else if (entry == null || value.isEmpty || entry.containsKey(pair[1])) {
      throw FormatException('$where: unsupported dependency syntax "$line".');
    } else {
      entry[pair[1]!] = value;
    }
  }
  return sections;
}

String _describeDependency(Map<String, String> attributes) => attributes.isEmpty
    ? '(empty)'
    : attributes.entries
          .map((e) => e.key.isEmpty ? e.value : '${e.key}: ${e.value}')
          .join(', ');

/// Checks the dependencies declared by a `pubspec.yaml` source.
List<String> _checkPubspec(String source) {
  final Map<String, Map<String, Map<String, String>>> sections;
  try {
    sections = _readDependencySections(source);
  } on FormatException catch (e) {
    return [
      'pubspec.yaml: [pubspec-unreadable] ${e.message} '
          'Dependencies cannot be verified.',
    ];
  }
  final diagnostics = <String>[];
  void report(String rule, String message) =>
      diagnostics.add('pubspec.yaml: [$rule] $message');

  for (final MapEntry(key: section, value: allowed)
      in _allowedDependencies.entries) {
    final entries = sections[section];
    if (entries == null) {
      report('pubspec-section-missing', 'Section "$section" is missing.');
      continue;
    }
    for (final entry in entries.entries) {
      if (allowed.containsKey(entry.key)) continue;
      final consumer = _consumerName.hasMatch(entry.key)
          ? ' This is a consumer package: CBS must not depend on it.'
          : '';
      report(
        'pubspec-dependency-not-allowed',
        'Unexpected "$section" entry "${entry.key}" '
            '(${_describeDependency(entry.value)}). '
            'Allowed: ${allowed.keys.join(', ')}.$consumer',
      );
    }
    for (final expected in allowed.entries) {
      final attributes = entries[expected.key];
      if (attributes == null) {
        report(
          'pubspec-dependency-missing',
          'Expected "$section" entry "${expected.key}" is missing.',
        );
        continue;
      }
      final valid = expected.value
          ? attributes.length == 1 && attributes['sdk'] == 'flutter'
          : attributes.length == 1 && (attributes['']?.isNotEmpty ?? false);
      if (!valid) {
        final rule = expected.value
            ? 'exactly "sdk: flutter"'
            : 'a plain version constraint (no path, git or other source)';
        report(
          'pubspec-dependency-source',
          '"$section.${expected.key}" must be $rule, '
              'found "${_describeDependency(attributes)}".',
        );
      }
    }
  }
  final overrides = sections['dependency_overrides'];
  if (overrides != null && overrides.isNotEmpty) {
    final found = [
      for (final e in overrides.entries)
        '"${e.key}" (${_describeDependency(e.value)})',
    ];
    report(
      'pubspec-overrides-not-allowed',
      '"dependency_overrides" must be absent or empty, '
          'found ${found.join(', ')}.',
    );
  }
  return diagnostics;
}

// ---------------------------------------------------------------------------
// Package
// ---------------------------------------------------------------------------

class _PackageReport {
  final List<String> diagnostics = [];
  final Map<String, int> dartFilesByTree = {};
  int checkedStrings = 0;
}

_PackageReport _checkPackage(Directory packageRoot) {
  final report = _PackageReport();
  final rootPath = packageRoot.path;

  final pubspec = File('$rootPath/pubspec.yaml');
  if (pubspec.existsSync()) {
    report.diagnostics.addAll(_checkPubspec(pubspec.readAsStringSync()));
  } else {
    report.diagnostics.add(
      'pubspec.yaml: [pubspec-missing] No pubspec.yaml in $rootPath.',
    );
  }

  for (final tree in _perimeters) {
    report.dartFilesByTree[tree] = 0;
    final directory = Directory('$rootPath/$tree');
    if (!directory.existsSync()) {
      report.diagnostics.add(
        '$tree/: [tree-missing] Directory not found; it cannot be verified.',
      );
      continue;
    }
    final entities = directory.listSync(recursive: true, followLinks: false)
      ..sort((a, b) => a.path.compareTo(b.path));
    for (final entity in entities) {
      final relativePath = entity.path
          .substring(rootPath.length + 1)
          .replaceAll(r'\', '/');
      if (entity is Link) {
        report.diagnostics.add(
          '$relativePath: [symlink-not-allowed] Symbolic links can point '
          'outside the verified tree.',
        );
      } else if (entity is File && relativePath.endsWith('.dart')) {
        report.dartFilesByTree[tree] = report.dartFilesByTree[tree]! + 1;
        try {
          final result = _checkDartSource(
            entity.readAsStringSync(),
            relativePath,
            tree,
          );
          report.diagnostics.addAll(result.diagnostics);
          report.checkedStrings += result.checkedStrings.length;
        } on FormatException catch (e) {
          report.diagnostics.add(
            '$relativePath: [dart-unreadable] File is not valid UTF-8 '
            '(${e.message}). Directives cannot be verified.',
          );
        }
      }
    }
  }
  return report;
}

void _expectNoViolations(List<String> diagnostics, String subject) {
  if (diagnostics.isEmpty) return;
  fail(
    '$subject breaks the CBS non-coupling contract '
    '(${diagnostics.length} violation(s)):\n'
    '${diagnostics.map((d) => '  - $d').join('\n')}\n'
    'cbs_flutter_ux must stay independent of AMH-USR, core-platform and any '
    'other consumer.',
  );
}

// ---------------------------------------------------------------------------
// Fixtures (temporary packages outside the repository)
// ---------------------------------------------------------------------------

final Directory _realPackageRoot = Directory.current.absolute;

const String _validPubspec = '''
name: cbs_flutter_ux
description: Fixture package.
version: 0.1.0
publish_to: none

environment:
  sdk: ^3.13.5

dependencies:
  flutter:
    sdk: flutter

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^6.0.0
''';

/// Creates a minimal valid package in the system temporary directory, which
/// is deleted after the test. The repository is never written.
Directory _createFixturePackage({String pubspec = _validPubspec}) {
  final fixture = Directory.systemTemp.createTempSync('cbs_non_coupling_');
  addTearDown(() {
    if (fixture.existsSync()) fixture.deleteSync(recursive: true);
  });
  File('${fixture.path}/pubspec.yaml').writeAsStringSync(pubspec);
  _writeFixtureFile(
    fixture,
    'lib/ok.dart',
    "import 'package:flutter/material.dart';\n",
  );
  _writeFixtureFile(
    fixture,
    'example/lib/main.dart',
    "import 'package:cbs_flutter_ux/ok.dart';\n",
  );
  return fixture;
}

void _writeFixtureFile(Directory fixture, String relativePath, String content) {
  final file = File('${fixture.path}/$relativePath');
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(content);
}

List<String> _checkedStringsOf(String source) =>
    _checkDartSource(source, 'lib/src/a.dart', 'lib').checkedStrings;

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('real package', () {
    test('tests run from the cbs_flutter_ux package root', () {
      final pubspec = File('${_realPackageRoot.path}/pubspec.yaml');
      expect(
        pubspec.existsSync(),
        isTrue,
        reason: 'Run flutter test from packages/cbs_flutter_ux.',
      );
      expect(
        pubspec.readAsStringSync(),
        matches(RegExp(r'^name:\s*cbs_flutter_ux\s*$', multiLine: true)),
      );
    });

    test('pubspec.yaml declares only the allowed dependencies', () {
      final source = File('${_realPackageRoot.path}/pubspec.yaml')
          .readAsStringSync();
      _expectNoViolations(_checkPubspec(source), 'pubspec.yaml');
    });

    test('lib/ and example/lib/ import only allowed targets', () {
      final report = _checkPackage(_realPackageRoot);
      _expectNoViolations(
        report.diagnostics.where((d) => !d.startsWith('pubspec.yaml')).toList(),
        'The Dart sources',
      );
    });

    test('the scan is not vacuous', () {
      final report = _checkPackage(_realPackageRoot);
      for (final tree in _perimeters) {
        expect(
          report.dartFilesByTree[tree],
          greaterThan(0),
          reason: 'No Dart file scanned in $tree/.',
        );
      }
      expect(report.checkedStrings, greaterThan(0));
    });
  });

  group('directive reader', () {
    test('ignores directives written in comments', () {
      const source = '''
// import 'package:amh_usr/home.dart';
/// import 'package:core_platform/api.dart';
/* export 'package:amh_usr/x.dart'; */
/* outer /* nested import 'package:amh_usr/y.dart'; */ still comment */
// Consumer: AMH-USR (documentation only).
import 'dart:async';
''';
      expect(_checkedStringsOf(source), ['dart:async']);
      expect(
        _checkDartSource(source, 'lib/src/a.dart', 'lib').diagnostics,
        isEmpty,
      );
    });

    test('ignores directive-like text inside string literals', () {
      const source = r'''
import 'package:flutter/widgets.dart';

const a = "import 'package:amh_usr/a.dart';";
const b = """
import 'package:amh_usr/b.dart';
export 'package:core_platform/c.dart';
""";
const c = r'import "package:amh_usr/d.dart";';
const d = 'AMH-USR / core-platform';
const e = 'x ${"nested 'quote'"} import ' 'y';
''';
      final report = _checkDartSource(source, 'lib/src/a.dart', 'lib');
      expect(report.checkedStrings, ['package:flutter/widgets.dart']);
      // The strings are never read as directives: the only diagnostics are
      // the string literals that mention a consumer package.
      expect(report.diagnostics, hasLength(3));
      expect(report.diagnostics.join('\n'), isNot(contains('consumer-import')));
      expect(
        report.diagnostics.every((d) => d.contains('[consumer-reference]')),
        isTrue,
      );
    });

    test('reads multi-line directives and their clauses', () {
      const source = '''
import
  'package:flutter/material.dart'
  as material
  show Widget,
       Text;
import 'dart:ui' deferred as ui hide Color;
export 'a.dart' show A;
''';
      expect(_checkedStringsOf(source), [
        'package:flutter/material.dart',
        'dart:ui',
        'a.dart',
      ]);
    });

    test('reads part, part of, library and annotations', () {
      const source = '''
@Deprecated('legacy')
library my.lib;

import 'a.dart';
part 'b.dart';
part of 'c.dart';
part of my.lib;
@pragma('vm:entry-point')
export 'd.dart';
''';
      expect(_checkedStringsOf(source), [
        'a.dart',
        'b.dart',
        'c.dart',
        'd.dart',
      ]);
    });

    test('reads every URI of a conditional directive', () {
      const source = '''
import 'a.dart'
    if (dart.library.io) 'b.dart'
    if (dart.library.js_interop == 'true') 'package:amh_usr/c.dart';
''';
      expect(_checkedStringsOf(source), [
        'a.dart',
        'b.dart',
        'true',
        'package:amh_usr/c.dart',
      ]);
    });

    test('rejects escapes and adjacent literals instead of decoding them', () {
      const source = r'''
import 'package:\u0061mh_usr/a.dart';
import 'package:amh' '_usr/b.dart';
import 'package:\x61mh_usr/c.dart';
''';
      final report = _checkDartSource(source, 'lib/a.dart', 'lib');
      final joined = report.diagnostics.join('\n');
      expect(report.diagnostics, hasLength(3));
      expect(joined, contains('lib/a.dart:1: [uri-unverifiable]'));
      expect(joined, contains('lib/a.dart:2: [package-not-allowed]'));
      expect(joined, contains('lib/a.dart:3: [uri-unverifiable]'));
    });

    test('reports unreadable sources instead of passing silently', () {
      final unterminatedComment = _checkDartSource(
        "import 'dart:io';\n/* never closed",
        'lib/a.dart',
        'lib',
      );
      expect(
        unterminatedComment.diagnostics.single,
        contains('dart-unreadable'),
      );
      expect(unterminatedComment.diagnostics.single, contains('lib/a.dart:2'));

      final unterminatedString = _checkDartSource(
        "import 'dart:io;\n",
        'lib/a.dart',
        'lib',
      );
      expect(
        unterminatedString.diagnostics.single,
        contains('dart-unreadable'),
      );
    });

    test('reports a directive without a readable URI', () {
      for (final source in ['import foo;', 'export;', 'import augment foo;']) {
        final report = _checkDartSource('$source\n', 'lib/a.dart', 'lib');
        expect(
          report.diagnostics.join(),
          contains('directive-unreadable'),
          reason: source,
        );
      }
    });
  });

  group('URI policy', () {
    const directory = 'lib/src/components';

    test(
      'allows dart:, flutter, cbs_flutter_ux and internal relative URIs',
      () {
        for (final uri in [
          'dart:async',
          'dart:ui',
          'package:flutter/material.dart',
          'package:flutter/src/widgets/framework.dart',
          'package:cbs_flutter_ux/cbs_flutter_ux.dart',
          'button.dart',
          './button.dart',
          'sub/button.dart',
          '../foundation/tokens/cbs_spacing.dart',
          // A directory merely named like a consumer, inside the perimeter,
          // is not a path leaving it.
          'amh-usr/x.dart',
        ]) {
          expect(_uriProblem(uri, directory, 'lib'), isNull, reason: uri);
        }
      },
    );

    test('forbids consumer, third-party and non-allowed targets', () {
      const expectations = <String, String>{
        'package:amh_usr/home.dart': 'consumer-import',
        'package:core_platform/api.dart': 'consumer-import',
        'package:AMH_USR/home.dart': 'consumer-import',
        'package:amh_usr_app/main.dart': 'consumer-import',
        'package:flutter_test/flutter_test.dart': 'package-not-allowed',
        'package:flutter_foo/x.dart': 'package-not-allowed',
        'package:http/http.dart': 'package-not-allowed',
        'package:cbs_flutter_ux_example/main.dart': 'package-not-allowed',
        'package:flutter': 'uri-malformed',
        'package:flutter/../amh_usr/x.dart': 'uri-malformed',
        'file:///home/user/amh-usr/lib/x.dart': 'uri-not-allowed',
        'https://example.com/x.dart': 'uri-not-allowed',
        'data:text/plain,x': 'uri-not-allowed',
        '/home/user/x.dart': 'uri-not-allowed',
        '../../../../amh-usr/lib/x.dart': 'relative-outside-perimeter',
        '../../../../../../outside.dart': 'relative-outside-perimeter',
        '../../../example/lib/main.dart': 'relative-outside-perimeter',
        '../../../outside.dart': 'relative-outside-perimeter',
        'a\\b.dart': 'uri-unverifiable',
        'a%2e%2e/b.dart': 'uri-unverifiable',
        '': 'uri-unverifiable',
      };
      expectations.forEach((uri, rule) {
        expect(
          _uriProblem(uri, directory, 'lib')?.rule,
          rule,
          reason: 'URI "$uri"',
        );
      });
    });

    test('keeps each tree inside itself', () {
      const directory = 'example/lib';
      expect(
        _uriProblem('catalog/demo.dart', directory, 'example/lib'),
        isNull,
      );
      expect(
        _uriProblem(
          '../../lib/cbs_flutter_ux.dart',
          directory,
          'example/lib',
        )?.rule,
        'relative-outside-perimeter',
      );
      expect(
        _uriProblem('../../../outside.dart', directory, 'example/lib')?.message,
        contains('leaves the package directory'),
      );
    });
  });

  group('false positives', () {
    test('documentation mentions of AMH-USR and core-platform pass', () {
      const source = '''
/// Reusable UX parts for CBS applications.
///
/// First consumer: AMH-USR (see package:amh_usr/home.dart for context).
/// Not coupled to core-platform or to any `HomeController`.
library;

// TODO(consumer): AMH-USR will adopt CbsSectionHeading after E08.
import 'package:flutter/material.dart'; // used by AMH-USR too
import 'package:cbs_flutter_ux/cbs_flutter_ux.dart';
import 'sibling.dart';

/* AMH-USR block comment, package:core_platform/x.dart */
class AmhUsrFriendlyLabel {
  static const String documentation = 'Designed with AMH-USR in mind.';
  static const String note = 'See core-platform docs.';
}
''';
      final report = _checkDartSource(source, 'lib/src/a.dart', 'lib');
      expect(report.diagnostics, isEmpty);
      expect(report.checkedStrings, hasLength(3));
    });

    test('a file without directives passes', () {
      final report = _checkDartSource(
        'class A {}\nvoid main() {}\n',
        'lib/a.dart',
        'lib',
      );
      expect(report.diagnostics, isEmpty);
      expect(report.checkedStrings, isEmpty);
    });

    test('import and export used as identifiers pass', () {
      const source = '''
void f({bool import = false, bool export = false}) {}
void g() {
  f(import: true, export: false);
  final export = 1;
  print(export.toString());
}
''';
      expect(
        _checkDartSource(source, 'lib/a.dart', 'lib').diagnostics,
        isEmpty,
      );
    });

    test('pubspec comments, quoting and block scalars are tolerated', () {
      const pubspec = '''
name: cbs_flutter_ux
description: >
  Wrapped description mentioning AMH-USR
  and core-platform.
dependencies:
  # runtime: Flutter SDK only
  flutter:
    sdk: "flutter"   # SDK dependency
dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: '^6.0.0'
dependency_overrides:
''';
      expect(_checkPubspec(pubspec), isEmpty);
    });
  });

  group('negative detection on temporary fixtures', () {
    test('the fixture is created outside the repository and is clean', () {
      final fixture = _createFixturePackage();
      expect(fixture.path, isNot(startsWith(_realPackageRoot.path)));
      _expectNoViolations(_checkPackage(fixture).diagnostics, 'The fixture');
    });

    final pubspecCases = <({String name, String pubspec, List<String> expected})>[
      (
        name: 'runtime dependency on amh_usr (path)',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  flutter:\n    sdk: flutter\n  amh_usr:\n    path: ../../amh-usr\n',
        ),
        expected: ['pubspec-dependency-not-allowed', 'amh_usr', 'consumer'],
      ),
      (
        name: 'runtime dependency on core_platform (git)',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  flutter:\n    sdk: flutter\n'
              '  core_platform:\n    git: https://example.com/core.git\n',
        ),
        expected: ['pubspec-dependency-not-allowed', 'core_platform'],
      ),
      (
        name: 'development dependency on amh_usr',
        pubspec: '$_validPubspec  amh_usr:\n    path: ../../amh-usr\n',
        expected: [
          'pubspec-dependency-not-allowed',
          'dev_dependencies',
          'amh_usr',
        ],
      ),
      (
        name: 'runtime third-party dependency',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  flutter:\n    sdk: flutter\n  http: ^1.2.0\n',
        ),
        expected: ['pubspec-dependency-not-allowed', 'http', '^1.2.0'],
      ),
      (
        name: 'extra development dependency',
        pubspec: '$_validPubspec  mockito: ^5.4.0\n',
        expected: ['pubspec-dependency-not-allowed', 'mockito'],
      ),
      (
        name: 'flutter declared from pub.dev instead of the SDK',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  flutter: ^1.0.0\n',
        ),
        expected: ['pubspec-dependency-source', 'dependencies.flutter'],
      ),
      (
        name: 'flutter_lints redirected to a path',
        pubspec: _validPubspec.replaceFirst(
          '  flutter_lints: ^6.0.0\n',
          '  flutter_lints:\n    path: ../lints\n',
        ),
        expected: ['pubspec-dependency-source', 'flutter_lints'],
      ),
      (
        name: 'flutter_lints missing',
        pubspec: _validPubspec.replaceFirst('  flutter_lints: ^6.0.0\n', ''),
        expected: ['pubspec-dependency-missing', 'flutter_lints'],
      ),
      (
        name: 'dependency_overrides targeting a consumer',
        pubspec:
            '$_validPubspec\ndependency_overrides:\n'
            '  amh_usr:\n    path: ../../amh-usr\n',
        expected: ['pubspec-overrides-not-allowed', 'amh_usr'],
      ),
      (
        name: 'dependency_overrides in flow style',
        pubspec:
            '$_validPubspec\ndependency_overrides: {amh_usr: {path: ../x}}\n',
        expected: ['pubspec-unreadable', 'block mapping'],
      ),
      (
        name: 'flow-style dependencies hiding a consumer',
        pubspec: _validPubspec.replaceFirst(
          'dependencies:\n  flutter:\n    sdk: flutter\n',
          'dependencies: {flutter: {sdk: flutter}, amh_usr: {path: ../x}}\n',
        ),
        expected: ['pubspec-unreadable', 'block mapping'],
      ),
      (
        name: 'duplicated dependencies section',
        pubspec: '$_validPubspec\ndependencies:\n  amh_usr:\n    path: ../x\n',
        expected: ['pubspec-unreadable', 'duplicate key'],
      ),
      (
        name: 'quoted consumer key',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  flutter:\n    sdk: flutter\n  "amh_usr": ^1.0.0\n',
        ),
        expected: ['pubspec-unreadable', 'amh_usr'],
      ),
      (
        name: 'YAML merge key',
        pubspec: _validPubspec.replaceFirst(
          '  flutter:\n    sdk: flutter\n',
          '  <<: *shared\n  flutter:\n    sdk: flutter\n',
        ),
        expected: ['pubspec-unreadable'],
      ),
      (
        name: 'tab indentation',
        pubspec: _validPubspec.replaceFirst(
          '  flutter_lints',
          '\tflutter_lints',
        ),
        expected: ['pubspec-unreadable', 'tab'],
      ),
    ];

    for (final c in pubspecCases) {
      test('fails on ${c.name}', () {
        expect(
          c.pubspec,
          isNot(_validPubspec),
          reason: 'The mutation did not change the pubspec.',
        );
        final diagnostics = _checkPackage(
          _createFixturePackage(pubspec: c.pubspec),
        ).diagnostics;
        expect(diagnostics, isNotEmpty);
        final joined = diagnostics.join('\n');
        for (final fragment in c.expected) {
          expect(joined, contains(fragment));
        }
      });
    }

    final sourceCases =
        <({String name, String path, String source, List<String> expected})>[
          (
            name: 'import of package:amh_usr in lib/',
            path: 'lib/src/intruder.dart',
            source: "import 'package:amh_usr/home.dart';\n",
            expected: ['lib/src/intruder.dart:1', 'consumer-import', 'amh_usr'],
          ),
          (
            name: 'import of package:core_platform in example/lib/',
            path: 'example/lib/intruder.dart',
            source:
                "import 'package:flutter/material.dart';\n"
                "import 'package:core_platform/api.dart';\n",
            expected: [
              'example/lib/intruder.dart:2',
              'consumer-import',
              'core_platform',
            ],
          ),
          (
            name: 'export of a consumer package',
            path: 'lib/intruder.dart',
            source: "export 'package:amh_usr/services.dart';\n",
            expected: ['consumer-import', 'amh_usr'],
          ),
          (
            name: 'relative import into the amh-usr directory',
            path: 'lib/src/intruder.dart',
            source: "import '../../../../amh-usr/lib/home_controller.dart';\n",
            expected: ['relative-outside-perimeter', 'amh-usr', 'consumer'],
          ),
          (
            name: 'relative import into the core-platform directory',
            path: 'example/lib/intruder.dart',
            source: "import '../../../core-platform/client.dart';\n",
            expected: ['relative-outside-perimeter', 'core-platform'],
          ),
          (
            name: 'relative import leaving lib/ for example/',
            path: 'lib/src/intruder.dart',
            source: "import '../../example/lib/main.dart';\n",
            expected: ['relative-outside-perimeter', 'example/lib/main.dart'],
          ),
          (
            name: 'relative import from example/lib/ into lib/',
            path: 'example/lib/intruder.dart',
            source: "import '../../lib/cbs_flutter_ux.dart';\n",
            expected: ['relative-outside-perimeter', 'package:cbs_flutter_ux/'],
          ),
          (
            name: 'relative import climbing above the package',
            path: 'lib/intruder.dart',
            source: "import '../../../outside.dart';\n",
            expected: ['relative-outside-perimeter', 'leaves the package'],
          ),
          (
            name: 'part file outside the perimeter',
            path: 'lib/src/intruder.dart',
            source: "part '../../pubspec.yaml.dart';\n",
            expected: ['relative-outside-perimeter'],
          ),
          (
            name: 'third-party package',
            path: 'lib/intruder.dart',
            source: "import 'package:http/http.dart' as http;\n",
            expected: ['package-not-allowed', 'http'],
          ),
          (
            name: 'flutter_test used by production code',
            path: 'lib/intruder.dart',
            source: "import 'package:flutter_test/flutter_test.dart';\n",
            expected: ['package-not-allowed', 'flutter_test'],
          ),
          (
            name: 'file: URI',
            path: 'lib/intruder.dart',
            source: "import 'file:///home/dev/amh-usr/lib/x.dart';\n",
            expected: ['uri-not-allowed', 'file:'],
          ),
          (
            name: 'consumer hidden in a conditional import',
            path: 'lib/intruder.dart',
            source:
                "import 'stub.dart'\n"
                "    if (dart.library.io) 'package:amh_usr/io.dart';\n",
            expected: ['consumer-import', 'amh_usr'],
          ),
          (
            name: 'consumer hidden behind unicode escapes',
            path: 'lib/intruder.dart',
            source: "import 'package:\\u0061mh_usr/home.dart';\n",
            expected: ['uri-unverifiable'],
          ),
          (
            name: 'consumer split by adjacent string literals',
            path: 'lib/intruder.dart',
            source: "import 'package:core_' 'platform/api.dart';\n",
            expected: ['package-not-allowed', 'core_'],
          ),
          (
            name: 'consumer import after a missing semicolon',
            path: 'lib/intruder.dart',
            source:
                "import 'dart:async'\n"
                "import 'package:amh_usr/home.dart';\n",
            expected: ['lib/intruder.dart:2', 'consumer-import'],
          ),
          (
            name: 'directive after a declaration',
            path: 'lib/intruder.dart',
            source:
                'class A {}\n'
                "import 'package:amh_usr/home.dart';\n",
            expected: ['lib/intruder.dart:2', 'consumer-import'],
          ),
          (
            name: 'interpolated directive URI',
            path: 'lib/intruder.dart',
            source: "import 'package:\${'amh'}_usr/home.dart';\n",
            expected: ['uri-unverifiable'],
          ),
          (
            name: 'directive without a readable URI',
            path: 'lib/intruder.dart',
            source: 'import amh_usr;\n',
            expected: ['directive-unreadable', 'lib/intruder.dart:1'],
          ),
          (
            name: 'consumer package referenced from a string literal',
            path: 'lib/intruder.dart',
            source:
                "import 'dart:core';\n"
                "const consumer = 'package:core_platform/api.dart';\n",
            expected: ['consumer-reference', 'core_platform'],
          ),
          (
            name: 'unreadable Dart source',
            path: 'lib/intruder.dart',
            source: "import 'package:amh_usr/home.dart';\n/* never closed",
            expected: ['dart-unreadable'],
          ),
        ];

    for (final c in sourceCases) {
      test('fails on ${c.name}', () {
        final fixture = _createFixturePackage();
        _writeFixtureFile(fixture, c.path, c.source);
        final diagnostics = _checkPackage(fixture).diagnostics;
        expect(diagnostics, isNotEmpty);
        final joined = diagnostics.join('\n');
        for (final fragment in c.expected) {
          expect(joined, contains(fragment));
        }
      });
    }

    test('fails on a symbolic link inside a verified tree', () {
      final fixture = _createFixturePackage();
      Link('${fixture.path}/lib/linked').createSync(Directory.systemTemp.path);
      final joined = _checkPackage(fixture).diagnostics.join('\n');
      expect(joined, contains('symlink-not-allowed'));
      expect(joined, contains('lib/linked'));
    }, skip: Platform.isWindows ? 'Symlinks need elevated rights.' : false);

    test('fails when a verified tree is missing', () {
      final fixture = _createFixturePackage();
      Directory('${fixture.path}/example/lib').deleteSync(recursive: true);
      final joined = _checkPackage(fixture).diagnostics.join('\n');
      expect(joined, contains('tree-missing'));
      expect(joined, contains('example/lib'));
    });

    test('fails when the pubspec is missing', () {
      final fixture = _createFixturePackage();
      File('${fixture.path}/pubspec.yaml').deleteSync();
      expect(
        _checkPackage(fixture).diagnostics.join('\n'),
        contains('pubspec-missing'),
      );
    });

    test('reports every violation, ordered and deterministic', () {
      final fixture = _createFixturePackage();
      _writeFixtureFile(
        fixture,
        'lib/intruder.dart',
        "import 'package:amh_usr/a.dart';\n"
            "import 'package:core_platform/b.dart';\n",
      );
      final first = _checkPackage(fixture).diagnostics;
      final second = _checkPackage(fixture).diagnostics;
      expect(first, second);
      expect(first, hasLength(2));
      expect(first[0], contains('intruder.dart:1'));
      expect(first[1], contains('intruder.dart:2'));
    });
  });
}
