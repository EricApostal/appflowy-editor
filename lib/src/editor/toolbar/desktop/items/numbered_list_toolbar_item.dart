import 'package:appflowy_editor/appflowy_editor.dart';

const _kNumberedListItemId = 'editor.numbered_list';

void _insertOrConvertToNumberedList(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }

  final currentNode = editorState.getNodeAtPath(selection.end.path);
  if (currentNode == null) {
    return;
  }

  // If current node is already a numbered list, don't do anything
  if (currentNode.type == NumberedListBlockKeys.type) {
    return;
  }

  final transaction = editorState.transaction;
  final delta = currentNode.delta;
  
  // If cursor is at the beginning of a line with content, or on an empty line,
  // convert the current line to a numbered list
  if (delta != null && (selection.startIndex == 0 || delta.isEmpty)) {
    // Convert current node to numbered list
    transaction.updateNode(currentNode, {
      'type': NumberedListBlockKeys.type,
      NumberedListBlockKeys.delta: delta.toJson(),
      blockComponentTextDirection: currentNode.attributes[blockComponentTextDirection],
    });
    transaction.afterSelection = selection;
  } else if (delta != null && delta.isNotEmpty) {
    // If cursor is in the middle of text, split the line and create numbered list
    final beforeDelta = delta.slice(0, selection.startIndex);
    final afterDelta = delta.slice(selection.startIndex);
    
    // Update current node with text before cursor
    transaction.updateNode(currentNode, {
      currentNode.type: currentNode.type,
      ParagraphBlockKeys.delta: beforeDelta.toJson(),
      blockComponentTextDirection: currentNode.attributes[blockComponentTextDirection],
    });
    
    // Create new numbered list node with text after cursor
    final numberedNode = numberedListNode(delta: afterDelta);
    numberedNode.updateAttributes({
      blockComponentTextDirection: currentNode.attributes[blockComponentTextDirection],
    });
    
    final nextPath = selection.end.path.next;
    transaction.insertNode(nextPath, numberedNode);
    transaction.afterSelection = Selection.collapsed(Position(path: nextPath, offset: 0));
  }
  
  editorState.apply(transaction);
}

final ToolbarItem numberedListItem = ToolbarItem(
  id: _kNumberedListItemId,
  group: 3,
  isActive: onlyShowInTextType,
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection;
    final node = selection != null
        ? editorState.getNodeAtPath(selection.start.path)
        : null;
    final isHighlight = node?.type == 'numbered_list';
    final child = SVGIconItemWidget(
      iconName: 'toolbar/numbered_list',
      isHighlight: isHighlight,
      highlightColor: highlightColor,
      iconColor: iconColor,
      onPressed: () {
        if (isHighlight) {
          // Convert numbered list back to paragraph
          editorState.formatNode(
            selection,
            (node) => node.copyWith(type: 'paragraph'),
          );
        } else {
          // Convert current line to numbered list or create new one
          _insertOrConvertToNumberedList(editorState);
        }
      },
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        _kNumberedListItemId,
        AppFlowyEditorL10n.current.numberedList,
        child,
      );
    }

    return child;
  },
);
