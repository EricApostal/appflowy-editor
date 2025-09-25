import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';

/// A [Delta] encoder that encodes a [Delta] to Markdown.
///
/// Only support inline styles, like bold, italic, underline, strike, code.
class DeltaMarkdownEncoder extends Converter<Delta, String> {
  @override
  String convert(Delta input) {
    final buffer = StringBuffer();
    final iterator = input.iterator;
    while (iterator.moveNext()) {
      final op = iterator.current;
      if (op is TextInsert) {
        final attributes = op.attributes;
        if (attributes != null) {
          // trailing space fix
          final text = op.text;
          final trimmedText = text.trimRight();
          final trailingSpaces = text.substring(trimmedText.length);

          if (trimmedText.isNotEmpty) {
            buffer.write(_prefixSyntax(attributes));
            buffer.write(trimmedText);
            buffer.write(_suffixSyntax(attributes));
          }

          if (trailingSpaces.isNotEmpty) {
            buffer.write(trailingSpaces);
          }
        } else {
          buffer.write(op.text);
        }
      }
    }
    return buffer.toString();
  }

  String _prefixSyntax(Attributes attributes) {
    var syntax = '';

    if (attributes[BuiltInAttributeKey.bold] == true &&
        attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '***';
    } else if (attributes[BuiltInAttributeKey.bold] == true) {
      syntax += '**';
    } else if (attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '_';
    }

    if (attributes[BuiltInAttributeKey.strikethrough] == true) {
      syntax += '~~';
    }
    if (attributes[BuiltInAttributeKey.underline] == true) {
      syntax += '<u>';
    }
    if (attributes[BuiltInAttributeKey.code] == true) {
      syntax += '`';
    }

    if (attributes[BuiltInAttributeKey.href] != null) {
      syntax += '[';
    }

    return syntax;
  }

  String _suffixSyntax(Attributes attributes) {
    var syntax = '';

    if (attributes[BuiltInAttributeKey.href] != null) {
      syntax += '](${attributes[BuiltInAttributeKey.href]})';
    }

    if (attributes[BuiltInAttributeKey.code] == true) {
      syntax += '`';
    }

    if (attributes[BuiltInAttributeKey.underline] == true) {
      syntax += '</u>';
    }

    if (attributes[BuiltInAttributeKey.strikethrough] == true) {
      syntax += '~~';
    }

    if (attributes[BuiltInAttributeKey.bold] == true &&
        attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '***';
    } else if (attributes[BuiltInAttributeKey.bold] == true) {
      syntax += '**';
    } else if (attributes[BuiltInAttributeKey.italic] == true) {
      syntax += '_';
    }

    return syntax;
  }
}
