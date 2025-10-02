import 'dart:convert';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

final QuillDeltaEncoder quillDeltaEncoder = QuillDeltaEncoder();

const _newLineSymbol = '\n';
const _header = 'header';
const _list = 'list';
const _orderedList = 'ordered';
const _bulletedList = 'bullet';
const _uncheckedList = 'unchecked';
const _checkedList = 'checked';
const _blockquote = 'blockquote';
const _indent = 'indent';

class QuillDeltaEncoder extends Converter<Delta, Document> {
  @override
  Document convert(Delta input) {
    final document = Document.blank(withInitialText: false);
    if (input.isEmpty) {
      document.insert([0], [paragraphNode()]);
      return document;
    }

    var currentNode = paragraphNode();
    var topLevelIndex = 0;

    // Stores the full path to the last node inserted at a given indent level.
    // This is the key to correctly reconstructing nested structures.
    final Map<int, List<int>> lastPathAtLevel = {};

    for (final op in input) {
      if (op is! TextInsert) {
        continue;
      }

      final lines = op.text.split(_newLineSymbol);

      for (int i = 0; i < lines.length; i++) {
        final lineText = lines[i];

        if (lineText.isNotEmpty) {
          _applyStyle(currentNode, lineText, op.attributes);
        }

        // A newline character signifies the end of a block.
        if (i < lines.length - 1) {
          final attributes = op.attributes;
          int indentLevel = attributes?[_indent] as int? ?? 0;

          // Apply block styles (e.g., convert from paragraph to list item).
          if (attributes != null) {
            currentNode = _applyListStyleIfNeeded(currentNode, attributes);
            currentNode = _applyHeadingStyleIfNeeded(currentNode, attributes);
            currentNode = _applyBlockquoteIfNeeded(currentNode, attributes);
            _applyIndentIfNeeded(currentNode, attributes);
          }

          // Determine the correct insertion path for the node.
          List<int> insertionPath;
          if (indentLevel == 0) {
            insertionPath = [topLevelIndex];
            topLevelIndex++;
          } else {
            // Get the path of the parent (the last node at the level above).
            List<int>? parentPath = lastPathAtLevel[indentLevel - 1];
            if (parentPath == null) {
              // This is an "orphaned" indented item. Fallback to inserting at the top level.
              insertionPath = [topLevelIndex];
              topLevelIndex++;
            } else {
              // Get the parent node from the document to find its number of children.
              // This gives us the correct index for the new child node.
              final parentNode = document.nodeAtPath(parentPath);
              final childIndex = parentNode?.children.length ?? 0;
              insertionPath = [...parentPath, childIndex];
            }
          }

          document.insert(insertionPath, [currentNode]);

          // Store the path of the node we just inserted for subsequent children.
          lastPathAtLevel[indentLevel] = insertionPath;
          // Invalidate paths for any deeper levels, as they are no longer relevant.
          lastPathAtLevel.keys
              .where((k) => k > indentLevel)
              .toList()
              .forEach(lastPathAtLevel.remove);

          // Reset for the next block.
          currentNode = paragraphNode();
        }
      }
    }

    // Add the very last node if it has content (for deltas that don't end with a newline).
    if (currentNode.delta?.isNotEmpty == true) {
      document.insert([topLevelIndex], [currentNode]);
    }

    // Ensure the document is never completely empty.
    if (document.root.children.isEmpty) {
      document.insert([0], [paragraphNode()]);
    }

    return document;
  }

  void _applyStyle(Node node, String text, Map<String, dynamic>? attributes) {
    final Attributes attrs = {};
    if (_containsStyle(attributes, 'strike')) {
      attrs[AppFlowyRichTextKeys.strikethrough] = true;
    }
    if (_containsStyle(attributes, 'underline')) {
      attrs[AppFlowyRichTextKeys.underline] = true;
    }
    if (_containsStyle(attributes, 'bold')) {
      attrs[AppFlowyRichTextKeys.bold] = true;
    }
    if (_containsStyle(attributes, 'italic')) {
      attrs[AppFlowyRichTextKeys.italic] = true;
    }
    final link = attributes?['link'] as String?;
    if (link != null) {
      attrs[AppFlowyRichTextKeys.href] = link;
    }
    final color = attributes?['color'] as String?;
    final colorHex = _convertColorToHexString(color);
    if (colorHex != null) {
      attrs[AppFlowyRichTextKeys.textColor] = colorHex;
    }
    final backgroundColor = attributes?['background'] as String?;
    final backgroundHex = _convertColorToHexString(backgroundColor);
    if (backgroundHex != null) {
      attrs[AppFlowyRichTextKeys.backgroundColor] = backgroundHex;
    }
    final newDelta = (node.delta ?? Delta())..insert(text, attributes: attrs);
    node.updateAttributes({'delta': newDelta.toJson()});
  }

  void _applyIndentIfNeeded(Node node, Map<String, dynamic> attributes) {
    final indent = attributes[_indent] as int?;
    final list = attributes[_list] as String?;
    if (indent != null && list == null && node.delta != null) {
      node.updateAttributes({
        'delta': node.delta
            ?.compose(
              Delta()
                ..retain(0)
                ..insert('  ' * indent),
            )
            .toJson(),
      });
    }
  }

  Node _applyBlockquoteIfNeeded(Node node, Map<String, dynamic> attributes) {
    final blockquote = attributes[_blockquote] as bool?;
    if (blockquote == true) {
      return quoteNode(
        delta: node.delta,
      );
    }
    return node;
  }

  Node _applyHeadingStyleIfNeeded(Node node, Map<String, dynamic> attributes) {
    final header = attributes[_header] as int?;
    if (header == null) {
      return node;
    }
    return headingNode(
      delta: node.delta,
      level: header,
    );
  }

  // This helper now just transforms the node type without any side effects.
  Node _applyListStyleIfNeeded(Node node, Map<String, dynamic> attributes) {
    final list = attributes[_list] as String?;
    switch (list) {
      case _bulletedList:
        return bulletedListNode(
          delta: node.delta,
        );
      case _orderedList:
        return numberedListNode(
          delta: node.delta,
        );
      case _checkedList:
        return todoListNode(
          delta: node.delta,
          checked: true,
        );
      case _uncheckedList:
        return todoListNode(
          delta: node.delta,
          checked: false,
        );
      default:
        return node;
    }
  }

  int _indentLevel(Map? attributes) {
    final indent = attributes?['indent'] as int?;
    return indent ?? 1;
  }

  bool _isIndentBulletedList(Map<String, dynamic>? attributes) {
    final list = attributes?[_list] as String?;
    final indent = attributes?[_indent] as int?;
    return [_bulletedList, _orderedList].contains(list) && indent != null;
  }

  bool _containsStyle(Map<String, dynamic>? attributes, String key) {
    final value = attributes?[key] as bool?;
    return value == true;
  }

  String? _convertColorToHexString(String? color) {
    if (color == null) {
      return null;
    }
    if (color.startsWith('#')) {
      return '0xFF${color.substring(1)}';
    } else if (color.startsWith("rgba")) {
      List rgbaList = color.substring(5, color.length - 1).split(',');
      return Color.fromRGBO(
        int.parse(rgbaList[0]),
        int.parse(rgbaList[1]),
        int.parse(rgbaList[2]),
        double.parse(rgbaList[3]),
      ).toHex();
    }
    return null;
  }
}
