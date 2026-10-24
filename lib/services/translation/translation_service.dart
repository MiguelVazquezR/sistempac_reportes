import 'translation_dictionary.dart';

/// Resultado de traducir un texto.
class TranslationOutcome {
  const TranslationOutcome({
    required this.text,
    required this.changed,
    this.untranslatedCjk = false,
  });

  final String text;
  final bool changed;

  /// `true` cuando el texto aún contiene caracteres chinos tras traducir.
  final bool untranslatedCjk;
}

class _Phrase {
  _Phrase({
    required this.source,
    required this.target,
    required this.isCjk,
    this.pattern,
  });

  final String source;
  final String target;
  final bool isCjk;
  final RegExp? pattern;
}

/// Traduce etiquetas de reportes conservando números, unidades y formato.
///
/// Estrategia (de la más específica a la más general):
/// 1. Coincidencia exacta con el diccionario (ignorando mayúsculas y espacios).
/// 2. Etiqueta + valor (`测试日期: 2024-05-01`), numeración (`1.`) y unidades
///    entre paréntesis (`Max Force (N)`).
/// 3. Reemplazo de términos conocidos dentro de frases más largas.
class TranslationService {
  TranslationService({Map<String, String>? extraTerms})
    : _extraTerms = extraTerms ?? const {} {
    final phrases = _buildPhrases();
    _asciiPhrases = phrases.where((phrase) => !phrase.isCjk).toList();
    _cjkPhrases = phrases.where((phrase) => phrase.isCjk).toList();
  }

  final Map<String, String> _extraTerms;
  late final List<_Phrase> _asciiPhrases;
  late final List<_Phrase> _cjkPhrases;

  static final RegExp _cjkCharacters = RegExp(
    r'[\u3400-\u4DBF\u4E00-\u9FFF\uF900-\uFAFF\u3005]',
  );
  static final RegExp _separator = RegExp(r'[:：]');

  /// `true` si el texto contiene ideogramas chinos.
  static bool containsCjk(String text) => _cjkCharacters.hasMatch(text);

  /// Traduce un texto de una sola celda/párrafo.
  TranslationOutcome translate(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) {
      return TranslationOutcome(text: source, changed: false);
    }

    final hadCjk = containsCjk(trimmed);
    final endsWithColon = RegExp(r'[:：]\s*$').hasMatch(trimmed);

    var label = trimmed;
    var tail = '';
    if (endsWithColon) {
      label = trimmed.replaceAll(RegExp(r'[:：]\s*$'), '').trimRight();
    } else {
      final match = _separator.firstMatch(trimmed);
      if (match != null && match.start > 0 && match.start <= 120) {
        label = trimmed.substring(0, match.start);
        tail = trimmed.substring(match.start + 1);
      }
    }
    return _translateParts(
      original: source,
      trimmed: trimmed,
      label: label,
      tail: tail,
      endsWithColon: endsWithColon,
      hadCjk: hadCjk,
    );
  }

  TranslationOutcome _translateParts({
    required String original,
    required String trimmed,
    required String label,
    required String tail,
    required bool endsWithColon,
    required bool hadCjk,
  }) {
    final direct = _lookupLabel(label);
    String translated;
    if (direct != null) {
      translated = direct;
    } else {
      final replaced = _replacePhrases(label);
      if (replaced == label) {
        // Último intento: el término puede estar dentro de la frase completa.
        final whole = _replacePhrases(trimmed);
        if (whole == trimmed) {
          return TranslationOutcome(
            text: original,
            changed: false,
            untranslatedCjk: hadCjk,
          );
        }
        return TranslationOutcome(
          text: whole,
          changed: true,
          untranslatedCjk: containsCjk(whole),
        );
      }
      translated = replaced;
    }

    final composed = endsWithColon
        ? '$translated:'
        : (tail.isEmpty ? translated : '$translated:$tail');

    return TranslationOutcome(
      text: composed,
      changed: composed != original,
      untranslatedCjk: containsCjk(composed),
    );
  }

  /// Traduce el nombre de una hoja si existe una equivalencia razonable.
  ///
  /// Excel limita los nombres de hoja a 31 caracteres y prohíbe `: \ / ? * [ ]`.
  String translateSheetName(String name) {
    final normalized = _normalize(name).toLowerCase();
    final direct = TranslationDictionary.sheetNames[normalized];
    if (direct != null) {
      return direct;
    }
    final outcome = translate(name);
    if (!outcome.changed) {
      return name;
    }
    final cleaned = outcome.text
        .replaceAll(RegExp(r'[:\\/\?\*\[\]]'), ' ')
        .trim();
    if (cleaned.isEmpty || cleaned.length > 31) {
      return name;
    }
    return cleaned;
  }

  String? _lookupLabel(String raw) {
    final normalized = _normalize(raw);
    if (normalized.isEmpty) {
      return null;
    }
    final key = normalized.toLowerCase();

    final direct = _extraTerms[key] ?? TranslationDictionary.terms[key];
    if (direct != null) {
      return direct;
    }

    // Puntuación final: "Report No." / "测试日期、"
    final withoutPunctuation = key.replaceAll(RegExp(r'[\s\.。、,，;；]+$'), '');
    if (withoutPunctuation.isNotEmpty && withoutPunctuation != key) {
      final match =
          _extraTerms[withoutPunctuation] ??
          TranslationDictionary.terms[withoutPunctuation];
      if (match != null) {
        return match;
      }
    }

    // Numeración inicial: "1. 测试日期" / "1) Width"
    final numbered = RegExp(r'^(\s*\d+\s*[\.\)、]\s*)(.+)$')
        .firstMatch(normalized);
    if (numbered != null) {
      final inner = _lookupLabel(numbered.group(2)!);
      if (inner != null) {
        return '${numbered.group(1)}$inner';
      }
    }

    // Unidades entre paréntesis al final: "Max Force (N)"
    final withUnit = RegExp(r'^(.*?)\s*([\(\[][^\)\]]*[\)\]])\s*$')
        .firstMatch(normalized);
    if (withUnit != null) {
      final base = _lookupLabel(withUnit.group(1)!);
      if (base != null) {
        return '$base ${withUnit.group(2)}';
      }
    }

    // Etiquetas compuestas: "宽度/厚度"
    if (normalized.contains('/')) {
      final parts = normalized.split('/');
      if (parts.length > 1) {
        final translated = parts.map(_lookupLabel).toList();
        if (translated.every((part) => part != null)) {
          return translated.join('/');
        }
      }
    }

    return null;
  }

  String _replacePhrases(String input) {
    var result = input;
    for (final phrase in _cjkPhrases) {
      if (result.contains(phrase.source)) {
        result = result.replaceAll(phrase.source, phrase.target);
      }
    }
    if (result.length > 200) {
      return result;
    }
    for (final phrase in _asciiPhrases) {
      result = result.replaceAll(phrase.pattern!, phrase.target);
    }
    return result;
  }

  List<_Phrase> _buildPhrases() {
    final entries = <String, String>{
      ...TranslationDictionary.terms,
      ..._extraTerms,
    };
    final phrases = entries.entries.map((entry) {
      final isCjk = containsCjk(entry.key);
      return _Phrase(
        source: entry.key,
        target: entry.value,
        isCjk: isCjk,
        pattern: isCjk ? null : _wordPattern(entry.key),
      );
    }).toList();
    phrases.sort((a, b) => b.source.length.compareTo(a.source.length));
    return phrases;
  }

  static RegExp _wordPattern(String term) {
    final escaped = RegExp.escape(term);
    return RegExp(
      '(?<![A-Za-z0-9])$escaped(?![A-Za-z0-9])',
      caseSensitive: false,
    );
  }

  static String _normalize(String value) {
    return value
        .replaceAll('\u00A0', ' ')
        .replaceAll('\u3000', ' ')
        .replaceAll('：', ':')
        .replaceAll('（', '(')
        .replaceAll('）', ')')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
