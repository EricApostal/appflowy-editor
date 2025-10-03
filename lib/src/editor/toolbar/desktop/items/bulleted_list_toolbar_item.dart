import 'package:appflowy_editor/appflowy_editor.dart';

const _kBulletedListItemId = 'editor.bulleted_list';

void _insertOrConvertToBulletedList(EditorState editorState) {
  final selection = editorState.selection;
  if (selection == null || !selection.isCollapsed) {
    return;
  }

  final currentNode = editorState.getNodeAtPath(selection.end.path);
  if (currentNode == null) {
    return;
  }

  // If current node is already a bulleted list, don't do anything
  if (currentNode.type == BulletedListBlockKeys.type) {
    return;
  }

  final transaction = editorState.transaction;
  final delta = currentNode.delta;

  // If cursor is at the beginning of a line with content, or on an empty line,
  // convert the current line to a bulleted list
  if (delta != null && (selection.startIndex == 0 || delta.isEmpty)) {
    // Convert current node to bulleted list
    transaction.updateNode(currentNode, {
      'type': BulletedListBlockKeys.type,
      BulletedListBlockKeys.delta: delta.toJson(),
      blockComponentTextDirection:
          currentNode.attributes[blockComponentTextDirection],
    });
    transaction.afterSelection = selection;
  } else if (delta != null && delta.isNotEmpty) {
    // If cursor is in the middle of text, split the line and create bulleted list
    final beforeDelta = delta.slice(0, selection.startIndex);
    final afterDelta = delta.slice(selection.startIndex);

    // Update current node with text before cursor
    transaction.updateNode(currentNode, {
      currentNode.type: currentNode.type,
      ParagraphBlockKeys.delta: beforeDelta.toJson(),
      blockComponentTextDirection:
          currentNode.attributes[blockComponentTextDirection],
    });

    // Create new bulleted list node with text after cursor
    final bulletNode = bulletedListNode(delta: afterDelta);
    bulletNode.updateAttributes({
      blockComponentTextDirection:
          currentNode.attributes[blockComponentTextDirection],
    });

    final nextPath = selection.end.path.next;
    transaction.insertNode(nextPath, bulletNode);
    transaction.afterSelection =
        Selection.collapsed(Position(path: nextPath, offset: 0));
  }

  editorState.apply(transaction);
}

final ToolbarItem bulletedListItem = ToolbarItem(
  id: _kBulletedListItemId,
  group: 3,
  isActive: onlyShowInTextType,
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection;
    final node = selection != null
        ? editorState.getNodeAtPath(selection.start.path)
        : null;
    final isHighlight = node?.type == 'bulleted_list';
    final child = SVGIconItemWidget(
      iconName: 'toolbar/bulleted_list',
      isHighlight: isHighlight,
      highlightColor: highlightColor,
      iconColor: iconColor,
      onPressed: () {
        if (isHighlight) {
          // Convert bulleted list back to paragraph
          editorState.formatNode(
            selection,
            (node) => node.copyWith(type: 'paragraph'),
          );
        } else {
          // Convert current line to bulleted list or create new one
          _insertOrConvertToBulletedList(editorState);
        }
      },
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        _kBulletedListItemId,
        AppFlowyEditorL10n.current.bulletedList,
        child,
      );
    }

    return child;
  },
);
