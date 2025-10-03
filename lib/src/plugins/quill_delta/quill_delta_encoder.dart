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

// Table attribute constants
const _tableCellKey = 'table-cell';
const _tableRowKey = 'table-row';
const _tableColKey = 'table-col';
const _tableIdKey = 'table-id';

class QuillDeltaEncoder extends Converter<Delta, Document> {
  @override
  Document convert(Delta input) {
    final document = Document.blank(withInitialText: false);
    if (input.isEmpty) {
      document.insert([0], [paragraphNode()]);
      return document;
    }

    // Pre-process the delta to group table cell content properly
    final processedOps = input.toList();
    
    var currentNode = paragraphNode();
    var topLevelIndex = 0;

    // Stores the full path to the last node inserted at a given indent level.
    // This is the key to correctly reconstructing nested structures.
    final Map<int, List<int>> lastPathAtLevel = {};
    
    // Table reconstruction data
    final Map<String, Node> tableNodes = {}; // tableId -> tableNode
    final Map<String, List<Node>> tableCells = {}; // tableId -> list of cells
    
    // Track the last table cell that was created but not yet populated with content
    Node? pendingTableCell;
    String? pendingTableId;

    for (final op in processedOps) {
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

          // Check if this is a table or table cell
          final isTableCell = attributes?[_tableCellKey] == true;
          final tableId = attributes?[_tableIdKey] as String?;
          final hasTableCols = attributes?.containsKey('table-cols') == true;
          final hasTableRows = attributes?.containsKey('table-rows') == true;

          if (isTableCell && tableId != null) {
            // Handle table cell - apply formatting but NOT indentation to the content
            if (attributes != null) {
              currentNode = _applyListStyleIfNeeded(currentNode, attributes);
              currentNode = _applyHeadingStyleIfNeeded(currentNode, attributes);
              currentNode = _applyBlockquoteIfNeeded(currentNode, attributes);
              // Skip indent for table cells as it's not meant for content but structure
            }
            
            // Convert to table cell
            currentNode =
                _applyTableCellIfNeeded(currentNode, attributes ?? {});

            // Store the cell for later table reconstruction
            tableCells.putIfAbsent(tableId, () => []).add(currentNode);
            
            // Set this as the pending table cell to receive the next content
            pendingTableCell = currentNode;
            pendingTableId = tableId;

            // Reset for the next block
            currentNode = paragraphNode();
            continue;
          } else if (tableId != null && (hasTableCols || hasTableRows)) {
            // Handle table node - only if it has table-specific attributes
            final tableNode = _createTableNode(attributes ?? {});
            tableNodes[tableId] = tableNode;

            // Reset for the next block
            currentNode = paragraphNode();
            continue;
          }

          // Check if we have a pending table cell to populate
          if (pendingTableCell != null && 
              currentNode.delta != null && 
              currentNode.delta!.toPlainText().trim().isNotEmpty) {
            // Replace the empty paragraph in the table cell with the content
            if (pendingTableCell.children.isNotEmpty) {
              final existingChild = pendingTableCell.children.first;
              // Update the existing child with the content
              existingChild.updateAttributes(currentNode.attributes);
              if (currentNode.delta != null) {
                existingChild.updateAttributes({'delta': currentNode.delta!.toJson()});
              }
            }
            
            // Clear the pending state
            pendingTableCell = null;
            pendingTableId = null;
            
            // Reset currentNode and continue to avoid double insertion
            currentNode = paragraphNode();
            continue;
          }

          // Apply block styles (e.g., convert from paragraph to list item).
          if (attributes != null) {
            currentNode = _applyListStyleIfNeeded(currentNode, attributes);
            currentNode = _applyHeadingStyleIfNeeded(currentNode, attributes);
            currentNode = _applyBlockquoteIfNeeded(currentNode, attributes);
            _applyIndentIfNeeded(currentNode, attributes);
          }

          // Determine the correct insertion path for the node.
          // Only create nested structures for lists, not for simple indented paragraphs
          final list = attributes?[_list] as String?;
          final isListItem = list != null;

          List<int> insertionPath;
          if (indentLevel == 0 || !isListItem) {
            // Insert at top level for non-indented items or indented paragraphs (not lists)
            insertionPath = [topLevelIndex];
            topLevelIndex++;
          } else {
            // Only create nested structure for list items
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
          // Only track paths for list items that can have nested children
          if (isListItem) {
            lastPathAtLevel[indentLevel] = insertionPath;
            // Invalidate paths for any deeper levels, as they are no longer relevant.
            lastPathAtLevel.keys
                .where((k) => k > indentLevel)
                .toList()
                .forEach(lastPathAtLevel.remove);
          }

          // Reset for the next block.
          currentNode = paragraphNode();
        }
      }
    }

    // Add the very last node if it has content (for deltas that don't end with a newline).
    if (currentNode.delta?.isNotEmpty == true) {
      document.insert([topLevelIndex], [currentNode]);
    }

    // Reconstruct tables by adding cells to their parent tables
    _reconstructTables(document, tableNodes, tableCells);

    // Ensure the document is never completely empty.
    if (document.root.children.isEmpty) {
      document.insert([0], [paragraphNode()]);
    }

    return document;
  }  void _applyStyle(Node node, String text, Map<String, dynamic>? attributes) {
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

  Node _applyTableCellIfNeeded(Node node, Map<String, dynamic> attributes) {
    final colPos = attributes[_tableColKey] as int?;
    final rowPos = attributes[_tableRowKey] as int?;

    return Node(
      type: TableCellBlockKeys.type,
      attributes: {
        if (colPos != null) TableCellBlockKeys.colPosition: colPos,
        if (rowPos != null) TableCellBlockKeys.rowPosition: rowPos,
      },
      children: [node], // The original node becomes a child of the table cell
    );
  }

  Node _createTableNode(Map<String, dynamic> attributes) {
    final colsLen = attributes['table-cols'] as int? ?? 1;
    final rowsLen = attributes['table-rows'] as int? ?? 1;

    return Node(
      type: TableBlockKeys.type,
      attributes: {
        TableBlockKeys.colsLen: colsLen,
        TableBlockKeys.rowsLen: rowsLen,
        TableBlockKeys.colDefaultWidth: 160.0,
        TableBlockKeys.rowDefaultHeight: 40.0,
        TableBlockKeys.colMinimumWidth: 40.0,
      },
      children: [], // Children will be added later during reconstruction
    );
  }



  void _reconstructTables(
    Document document,
    Map<String, Node> tableNodes,
    Map<String, List<Node>> tableCells,
  ) {
    // For each table, add its cells and insert it into the document
    for (final entry in tableNodes.entries) {
      final tableId = entry.key;
      final tableNode = entry.value;
      final cells = tableCells[tableId] ?? [];

      // Sort cells by position to ensure correct order
      cells.sort((a, b) {
        final aRow = a.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;
        final aCol = a.attributes[TableCellBlockKeys.colPosition] as int? ?? 0;
        final bRow = b.attributes[TableCellBlockKeys.rowPosition] as int? ?? 0;
        final bCol = b.attributes[TableCellBlockKeys.colPosition] as int? ?? 0;

        // Sort by row first, then by column
        final rowCompare = aRow.compareTo(bRow);
        return rowCompare != 0 ? rowCompare : aCol.compareTo(bCol);
      });

      // Add cells to the table
      for (final cell in cells) {
        tableNode.insert(cell);
      }

      // Insert the table into the document at the end
      final topLevelIndex = document.root.children.length;
      document.insert([topLevelIndex], [tableNode]);
    }
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
