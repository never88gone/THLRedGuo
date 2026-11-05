import 'dart:io';

Future<void> main(List<String> arguments) async {
  try {
    String option(String name) => arguments
        .singleWhere((argument) => argument.startsWith('--$name='))
        .substring(name.length + 3);

    final input = File(option('input'));
    final output = File(option('output'));
    final environment = Platform.environment;
    final ci = ['CI', 'GITHUB_ACTIONS'].any(
      (name) => ['true', '1', 'yes'].contains(environment[name]?.toLowerCase()),
    );
    final data = await input.readAsBytes();
    final template = String.fromCharCodes(data);
    if (environment['FLUTTER_BUILD_MODE'] != 'debug' ||
        ci ||
        !template.contains('__THL_HONGGUO_SIGNING_')) {
      await output.parent.create(recursive: true);
      await output.writeAsBytes(data);
      return;
    }
    final helper = File.fromUri(
      Platform.script.resolve('prepare_local_debug_source.py'),
    );
    try {
      final result = await Process.run(
        Platform.isWindows ? 'python' : 'python3',
        [helper.path, '--input', input.path, '--output', output.path],
      );
      stdout.write(result.stdout);
      stderr.write(result.stderr);
      if (result.exitCode == 0 &&
          await output.exists() &&
          await output.length() > 0) {
        return;
      }
    } on ProcessException {
      stderr.writeln('Local debug source preparation requires Python 3.');
    }
    await output.parent.create(recursive: true);
    await output.writeAsBytes(data);
    stderr.writeln(
      'Local signing is unavailable; the public source template was preserved.',
    );
  } on FileSystemException {
    stderr.writeln('Local debug source input or output is unavailable.');
    exitCode = 1;
  } on StateError {
    stderr.writeln('Local debug source requires --input and --output.');
    exitCode = 1;
  }
}
