import 'dart:io';

class Config {
  Config(this.values);
  final Map<String, String> values;

  factory Config.load([String filename = '.env.local']) {
    final file = File(filename);
    return Config({
      if (file.existsSync())
        for (final line in file.readAsLinesSync())
          if (line.contains('=') && !line.trimLeft().startsWith('#'))
            line.substring(0, line.indexOf('=')).trim(): line
                .substring(line.indexOf('=') + 1)
                .trim(),
      ...Platform.environment,
    });
  }

  String get(String key, [String? fallback]) =>
      values[key] ??
      fallback ??
      (throw StateError('Missing configuration: $key'));
}
