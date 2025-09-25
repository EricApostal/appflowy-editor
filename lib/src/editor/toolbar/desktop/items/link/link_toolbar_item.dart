import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor/src/editor/toolbar/desktop/items/link/link_menu.dart';
import 'package:appflowy_editor/src/editor/util/link_util.dart';
import 'package:flutter/material.dart';

const _menuWidth = 300;
const _hasTextHeight = 244;
const _noTextHeight = 150;
const _kLinkItemId = 'editor.link';

final linkItem = ToolbarItem(
  id: _kLinkItemId,
  group: 4,
  isActive: (editorState) {
    final selection = editorState.selection;
    if (selection == null || !selection.isSingle) {
      return false;
    }

    final node = editorState.getNodeAtPath(selection.start.path);
    if (node == null ||
        node.delta == null ||
        !toolbarItemWhiteList.contains(node.type)) {
      return false;
    }

    // If text is selected, show the link button
    if (!selection.isCollapsed) {
      return true;
    }

    // If cursor is positioned within an existing link, show the link button
    final attributes = editorState.getDeltaAttributesInSelectionStart();
    if (attributes != null && attributes[AppFlowyRichTextKeys.href] != null) {
      return true;
    }

    return false;
  },
  builder: (context, editorState, highlightColor, iconColor, tooltipBuilder) {
    final selection = editorState.selection;
    if (selection == null) {
      return const SizedBox.shrink();
    }

    // Expand collapsed selection to include the entire link if cursor is within a link
    Selection workingSelection = selection;
    bool isHref = false;

    if (selection.isCollapsed) {
      // Check if cursor is within a link
      final attributes = editorState.getDeltaAttributesInSelectionStart();
      if (attributes != null && attributes[AppFlowyRichTextKeys.href] != null) {
        // Find the bounds of the link text
        final node = editorState.getNodeAtPath(selection.start.path);
        if (node?.delta != null) {
          final delta = node!.delta!;
          final offset = selection.start.offset;

          // Find start of link
          int linkStart = offset;
          while (linkStart > 0) {
            final prevAttrs =
                delta.slice(linkStart - 1, linkStart).firstOrNull?.attributes;
            if (prevAttrs?[AppFlowyRichTextKeys.href] !=
                attributes[AppFlowyRichTextKeys.href]) {
              break;
            }
            linkStart--;
          }

          // Find end of link
          int linkEnd = offset;
          while (linkEnd < delta.length) {
            final nextAttrs =
                delta.slice(linkEnd, linkEnd + 1).firstOrNull?.attributes;
            if (nextAttrs?[AppFlowyRichTextKeys.href] !=
                attributes[AppFlowyRichTextKeys.href]) {
              break;
            }
            linkEnd++;
          }

          // Create expanded selection
          workingSelection = Selection(
            start: Position(path: selection.start.path, offset: linkStart),
            end: Position(path: selection.end.path, offset: linkEnd),
          );
          isHref = true;
        }
      }
    } else {
      // Non-collapsed selection, check if it's a link
      final nodes = editorState.getNodesInSelection(workingSelection);
      isHref = nodes.allSatisfyInSelection(workingSelection, (delta) {
        return delta.everyAttributes(
          (attributes) => attributes[AppFlowyRichTextKeys.href] != null,
        );
      });
    }

    final child = SVGIconItemWidget(
      iconName: 'toolbar/link',
      isHighlight: isHref,
      highlightColor: highlightColor,
      iconColor: iconColor,
      onPressed: () {
        showLinkMenu(context, editorState, workingSelection, isHref);
      },
    );

    if (tooltipBuilder != null) {
      return tooltipBuilder(
        context,
        _kLinkItemId,
        AppFlowyEditorL10n.current.link,
        child,
      );
    }

    return child;
  },
);

void showLinkMenu(
  BuildContext context,
  EditorState editorState,
  Selection selection,
  bool isHref,
) {
  // Since link format is only available for single line selection,
  // the first rect(also the only rect) is used as the starting reference point for the [overlay] position

  // get link address if the selection is already a link
  String? linkText;
  if (isHref) {
    linkText = editorState.getDeltaAttributeValueInSelection(
      BuiltInAttributeKey.href,
      selection,
    );
  }

  final (left, top, right, bottom) = _getPosition(editorState, linkText);

  // get node, index and length for formatting text when the link is removed
  final node = editorState.getNodeAtPath(selection.end.path);
  if (node == null) {
    return;
  }
  final index = selection.normalized.startIndex;
  final length = selection.length;

  OverlayEntry? overlay;

  void dismissOverlay() {
    keepEditorFocusNotifier.decrease();
    overlay?.remove();
    overlay = null;
  }

  keepEditorFocusNotifier.increase();
  overlay = FullScreenOverlayEntry(
    top: top,
    bottom: bottom,
    left: left,
    right: right,
    dismissCallback: () => keepEditorFocusNotifier.decrease(),
    builder: (context) {
      return LinkMenu(
        linkText: linkText,
        editorState: editorState,
        onOpenLink: () async {
          await editorLaunchUrl(linkText);
        },
        onSubmitted: (text) async {
          if (isUri(text)) {
            await editorState.formatDelta(selection, {
              BuiltInAttributeKey.href: text,
            });
            dismissOverlay();
          }
        },
        onCopyLink: () {
          AppFlowyClipboard.setData(text: linkText);
          dismissOverlay();
        },
        onRemoveLink: () {
          final transaction = editorState.transaction
            ..formatText(
              node,
              index,
              length,
              {BuiltInAttributeKey.href: null},
            );
          editorState.apply(transaction);
          dismissOverlay();
        },
        onDismiss: dismissOverlay,
      );
    },
  ).build();

  Overlay.of(context, rootOverlay: true).insert(overlay!);
}

// get a proper position for link menu
(double? left, double? top, double? right, double? bottom) _getPosition(
  EditorState editorState,
  String? linkText,
) {
  final rect = editorState.selectionRects().first;

  double? left, right, top, bottom;
  final offset = rect.center;
  final editorOffset = editorState.renderBox!.localToGlobal(Offset.zero);
  final editorWidth = editorState.renderBox!.size.width;
  (left, right) = _getStartEnd(
    editorWidth,
    offset.dx,
    editorOffset.dx,
    _menuWidth,
    rect.left,
    rect.right,
    true,
  );

  final editorHeight = editorState.renderBox!.size.height;
  (top, bottom) = _getStartEnd(
    editorHeight,
    offset.dy,
    editorOffset.dy,
    linkText != null ? _hasTextHeight : _noTextHeight,
    rect.top,
    rect.bottom,
    false,
  );

  return (left, top, right, bottom);
}

// This method calculates the start and end position for a specific
// direction (either horizontal or vertical) in the layout.
(double? start, double? end) _getStartEnd(
  double editorLength,
  double offsetD,
  double editorOffsetD,
  int menuLength,
  double rectStart,
  double rectEnd,
  bool isHorizontal,
) {
  final threshold = editorOffsetD + editorLength - _menuWidth;
  double? start, end;
  if (offsetD > threshold) {
    end = editorOffsetD + editorLength - rectStart - 5;
  } else if (isHorizontal) {
    start = rectStart;
  } else {
    start = rectEnd + 5;
  }

  return (start, end);
}
