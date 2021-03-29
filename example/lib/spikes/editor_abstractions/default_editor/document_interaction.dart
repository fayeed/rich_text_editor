import 'dart:math';
import 'dart:ui';

// import 'package:example/spikes/editor_abstractions/core/edit_context.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart' hide SelectableText;
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../core/document.dart';
import '../core/document_selection.dart';
import '../core/document_layout.dart';
import '../core/edit_context.dart';
import '../gestures/multi_tap_gesture.dart';
import '_text_tools.dart';

/// Composes and edits a rich text document based on user
/// gestures and keyboard input.
///
/// TODO: write more docs here
class DocumentInteractor extends StatefulWidget {
  const DocumentInteractor({
    Key key,
    @required this.documentLayoutKey,
    @required this.editContext,
    @required this.keyboardActions,
    @required this.child,
    this.scrollController,
    this.showDebugPaint = false,
  }) : super(key: key);

  final GlobalKey documentLayoutKey;

  final EditContext editContext;

  final List<DocumentKeyboardAction> keyboardActions;

  final ScrollController scrollController;

  final Widget child;

  /// Paints some extra visual ornamentation to help with
  /// debugging, when true.
  final showDebugPaint;

  @override
  _DocumentInteractorState createState() => _DocumentInteractorState();
}

class _DocumentInteractorState extends State<DocumentInteractor>
    with SingleTickerProviderStateMixin {
  final _dragGutterExtent = 100;
  final _maxDragSpeed = 20;

  FocusNode _rootFocusNode;

  ScrollController _scrollController;

  // Tracks user drag gestures for selection purposes.
  SelectionType _selectionType = SelectionType.position;
  Offset _dragStartInViewport;
  Offset _dragStartInDoc;
  Offset _dragEndInViewport;
  Offset _dragEndInDoc;
  Rect _dragRectInViewport;

  bool _scrollUpOnTick = false;
  bool _scrollDownOnTick = false;
  Ticker _ticker;

  // Determines the current mouse cursor style displayed on screen.
  final _cursorStyle = ValueNotifier(SystemMouseCursors.basic);

  @override
  void initState() {
    super.initState();
    _rootFocusNode = FocusNode();
    _ticker = createTicker(_onTick);
    _scrollController =
        _scrollController = (widget.scrollController ?? ScrollController())
          ..addListener(_updateDragSelection);

    widget.editContext.composer.addListener(_onSelectionChange);
  }

  @override
  void didUpdateWidget(DocumentInteractor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.editContext.composer != oldWidget.editContext.composer) {
      oldWidget.editContext.composer?.removeListener(_onSelectionChange);
      widget.editContext.composer?.addListener(_onSelectionChange);
    }
    if (widget.scrollController != oldWidget.scrollController) {
      _scrollController.removeListener(_updateDragSelection);
      if (oldWidget.scrollController == null) {
        _scrollController.dispose();
      }
      _scrollController = (widget.scrollController ?? ScrollController())
        ..addListener(_updateDragSelection);
    }
  }

  @override
  void dispose() {
    widget.editContext.composer?.removeListener(_onSelectionChange);
    _ticker.dispose();
    if (widget.scrollController == null) {
      _scrollController.dispose();
    }
    _rootFocusNode.dispose();
    super.dispose();
  }

  DocumentLayout get _layout =>
      widget.documentLayoutKey.currentState as DocumentLayout;

  void _onSelectionChange() {
    print('EditableDocument: _onSelectionChange()');
    setState(() {
      _ensureSelectionExtentIsVisible();
    });
  }

  void _ensureSelectionExtentIsVisible() {
    final selection = widget.editContext.composer.selection;
    if (selection == null) {
      return;
    }

    // The reason that a Rect is returned instead of an Offset is
    // because things like Images an Horizontal Rules don't have
    // a clear selection offset. They are either entirely selected,
    // or not selected at all.
    final extentRect = _layout.getRectForPosition(
      selection.extent,
    );

    final myBox = context.findRenderObject() as RenderBox;
    final beyondTopExtent =
        min(extentRect.top - _scrollController.offset - _dragGutterExtent, 0)
            .abs();
    final beyondBottomExtent = max(
        extentRect.bottom -
            myBox.size.height -
            _scrollController.offset +
            _dragGutterExtent,
        0);

    print('Ensuring extent is visible.');
    print(' - interaction size: ${myBox.size}');
    print(' - scroll extent: ${_scrollController.offset}');
    print(' - extent rect: $extentRect');
    print(' - beyond top: $beyondTopExtent');
    print(' - beyond bottom: $beyondBottomExtent');

    if (beyondTopExtent > 0) {
      final newScrollPosition = (_scrollController.offset - beyondTopExtent)
          .clamp(0.0, _scrollController.position.maxScrollExtent);

      _scrollController.animateTo(
        newScrollPosition,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    } else if (beyondBottomExtent > 0) {
      final newScrollPosition = (beyondBottomExtent + _scrollController.offset)
          .clamp(0.0, _scrollController.position.maxScrollExtent);

      _scrollController.animateTo(
        newScrollPosition,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    }
  }

  KeyEventResult _onKeyPressed(RawKeyEvent keyEvent) {
    print('EditableDocument: onKeyPressed()');
    if (keyEvent is! RawKeyDownEvent) {
      return KeyEventResult.handled;
    }

    ExecutionInstruction instruction = ExecutionInstruction.continueExecution;
    int index = 0;
    while (instruction == ExecutionInstruction.continueExecution &&
        index < widget.keyboardActions.length) {
      instruction = widget.keyboardActions[index](
        editContext: widget.editContext,
        keyEvent: keyEvent,
      );
      index += 1;
    }

    return instruction == ExecutionInstruction.haltExecution
        ? KeyEventResult.handled
        : KeyEventResult.ignored;
  }

  void _onTapDown(TapDownDetails details) {
    print('EditableDocument: onTapDown()');
    _clearSelection();
    _selectionType = SelectionType.position;

    final docOffset = _getDocOffset(details.localPosition);
    print(' - document offset: $docOffset');
    final docPosition = _layout.getDocumentPositionAtOffset(docOffset);
    print(' - tapped document position: $docPosition');

    if (docPosition != null) {
      // Place the document selection at the location where the
      // user tapped.
      _selectPosition(docPosition);
    } else {
      // The user tapped in an area of the editor where there is no content node.
      // Give focus back to the root of the editor.
      _rootFocusNode.requestFocus();
    }
  }

  void _onDoubleTapDown(TapDownDetails details) {
    _selectionType = SelectionType.word;

    print('EditableDocument: onDoubleTap()');
    _clearSelection();

    final docOffset = _getDocOffset(details.localPosition);
    final docPosition = _layout.getDocumentPositionAtOffset(docOffset);
    print(' - tapped document position: $docPosition');

    if (docPosition != null) {
      final didSelectWord = _selectWordAt(
        docPosition: docPosition,
        docLayout: _layout,
      );
      if (!didSelectWord) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      // The user tapped in an area of the editor where there is no content node.
      // Give focus back to the root of the editor.
      _rootFocusNode.requestFocus();
    }
  }

  void _onDoubleTap() {
    _selectionType = SelectionType.position;
  }

  void _onTripleTapDown(TapDownDetails details) {
    _selectionType = SelectionType.paragraph;

    print('EditableDocument: onTripleTapDown()');
    _clearSelection();

    final docOffset = _getDocOffset(details.localPosition);
    final docPosition = _layout.getDocumentPositionAtOffset(docOffset);
    print(' - tapped document position: $docPosition');

    if (docPosition != null) {
      final didSelectParagraph = _selectParagraphAt(
        docPosition: docPosition,
        docLayout: _layout,
      );
      if (!didSelectParagraph) {
        // Place the document selection at the location where the
        // user tapped.
        _selectPosition(docPosition);
      }
    } else {
      // The user tapped in an area of the editor where there is no content node.
      // Give focus back to the root of the editor.
      _rootFocusNode.requestFocus();
    }
  }

  void _onTripleTap() {
    _selectionType = SelectionType.position;
  }

  void _onPanStart(DragStartDetails details) {
    print('_onPanStart()');
    _dragStartInViewport = details.localPosition;
    _dragStartInDoc = _getDocOffset(_dragStartInViewport);

    _clearSelection();
    _dragRectInViewport =
        Rect.fromLTWH(_dragStartInViewport.dx, _dragStartInViewport.dy, 1, 1);
  }

  void _onPanUpdate(DragUpdateDetails details) {
    print('_onPanUpdate()');
    setState(() {
      _dragEndInViewport = details.localPosition;
      _dragEndInDoc = _getDocOffset(_dragEndInViewport);
      _dragRectInViewport =
          Rect.fromPoints(_dragStartInViewport, _dragEndInViewport);
      print(' - drag rect: $_dragRectInViewport');
      _updateCursorStyle(details.localPosition);
      _updateDragSelection();

      _scrollIfNearBoundary();
    });
  }

  void _onPanEnd(DragEndDetails details) {
    setState(() {
      _dragStartInDoc = null;
      _dragEndInDoc = null;
      _dragRectInViewport = null;
    });

    _stopScrollingUp();
    _stopScrollingDown();
  }

  void _onPanCancel() {
    setState(() {
      _dragStartInDoc = null;
      _dragEndInDoc = null;
      _dragRectInViewport = null;
    });

    _stopScrollingUp();
    _stopScrollingDown();
  }

  void _onMouseMove(PointerEvent pointerEvent) {
    _updateCursorStyle(pointerEvent.localPosition);
  }

  bool _selectWordAt({
    @required DocumentPosition docPosition,
    @required DocumentLayout docLayout,
  }) {
    final newSelection =
        getWordSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editContext.composer.selection = newSelection;
      return true;
    } else {
      return false;
    }
  }

  bool _selectParagraphAt({
    @required DocumentPosition docPosition,
    @required DocumentLayout docLayout,
  }) {
    final newSelection =
        getParagraphSelection(docPosition: docPosition, docLayout: docLayout);
    if (newSelection != null) {
      widget.editContext.composer.selection = newSelection;
      return true;
    } else {
      return false;
    }
  }

  void _selectPosition(DocumentPosition position) {
    print('Setting document selection to $position');
    widget.editContext.composer.selection = DocumentSelection.collapsed(
      position: position,
    );
  }

  void _updateDragSelection() {
    if (_dragStartInDoc == null) {
      return;
    }

    _dragEndInDoc = _getDocOffset(_dragEndInViewport);

    _selectRegion(
      documentLayout: _layout,
      baseOffset: _dragStartInDoc,
      extentOffset: _dragEndInDoc,
      selectionType: _selectionType,
    );
  }

  void _selectRegion({
    @required DocumentLayout documentLayout,
    @required Offset baseOffset,
    @required Offset extentOffset,
    @required SelectionType selectionType,
  }) {
    print('Composer: selectionRegion(). Mode: $selectionType');
    DocumentSelection selection =
        documentLayout.getDocumentSelectionInRegion(baseOffset, extentOffset);
    DocumentPosition basePosition = selection?.base;
    DocumentPosition extentPosition = selection?.extent;
    print(' - base: $basePosition, extent: $extentPosition');

    if (basePosition == null || extentPosition == null) {
      widget.editContext.composer.selection = null;
      return;
    }

    if (selectionType == SelectionType.paragraph) {
      final baseParagraphSelection = getParagraphSelection(
        docPosition: basePosition,
        docLayout: documentLayout,
      );
      basePosition = baseOffset.dy < extentOffset.dy
          ? baseParagraphSelection.base
          : baseParagraphSelection.extent;
      final extentParagraphSelection = getParagraphSelection(
        docPosition: extentPosition,
        docLayout: documentLayout,
      );
      extentPosition = baseOffset.dy < extentOffset.dy
          ? extentParagraphSelection.extent
          : extentParagraphSelection.base;
    } else if (selectionType == SelectionType.word) {
      print(' - selecting a word');
      final baseWordSelection = getWordSelection(
        docPosition: basePosition,
        docLayout: documentLayout,
      );
      basePosition = baseWordSelection.base;

      final extentWordSelection = getWordSelection(
        docPosition: extentPosition,
        docLayout: documentLayout,
      );
      extentPosition = extentWordSelection.extent;
    }

    widget.editContext.composer.selection = (DocumentSelection(
      base: basePosition ?? widget.editContext.composer.selection.base,
      extent: extentPosition ?? widget.editContext.composer.selection.extent,
    ));
    print('Region selection: ${widget.editContext.composer.selection}');
  }

  void _clearSelection() {
    widget.editContext.composer.clearSelection();
  }

  void _updateCursorStyle(Offset cursorOffset) {
    final docOffset = _getDocOffset(cursorOffset);
    final desiredCursor = _layout.getDesiredCursorAtOffset(docOffset);

    if (desiredCursor != null && desiredCursor != _cursorStyle.value) {
      _cursorStyle.value = desiredCursor;
    } else if (desiredCursor == null &&
        _cursorStyle.value != SystemMouseCursors.basic) {
      _cursorStyle.value = SystemMouseCursors.basic;
    }
  }

  // Given an `offset` within this `EditableDocument`, returns that `offset`
  // in the coordinate space of the `DocumentLayout` for the rich text document.
  Offset _getDocOffset(Offset offset) {
    final docBox =
        widget.documentLayoutKey.currentContext.findRenderObject() as RenderBox;
    return docBox.globalToLocal(offset, ancestor: context.findRenderObject());
  }

  // ------ scrolling -------
  /// We prevent SingleChildScrollView from processing mouse events because
  /// it scrolls by drag by default, which we don't want. However, we do
  /// still want mouse scrolling. This method re-implements a primitive
  /// form of mouse scrolling.
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is PointerScrollEvent) {
      final newScrollOffset = (_scrollController.offset + event.scrollDelta.dy)
          .clamp(0.0, _scrollController.position.maxScrollExtent);
      _scrollController.jumpTo(newScrollOffset);

      _updateDragSelection();
    }
  }

  void _scrollIfNearBoundary() {
    final editorBox = context.findRenderObject() as RenderBox;

    if (_dragEndInViewport.dy < _dragGutterExtent) {
      _startScrollingUp();
    } else {
      _stopScrollingUp();
    }
    if (editorBox.size.height - _dragEndInViewport.dy < _dragGutterExtent) {
      _startScrollingDown();
    } else {
      _stopScrollingDown();
    }
  }

  void _startScrollingUp() {
    if (_scrollUpOnTick) {
      return;
    }

    _scrollUpOnTick = true;
    _ticker.start();
  }

  void _stopScrollingUp() {
    if (!_scrollUpOnTick) {
      return;
    }

    _scrollUpOnTick = false;
    _ticker.stop();
  }

  void _scrollUp() {
    if (_scrollController.offset <= 0) {
      return;
    }

    final gutterAmount = _dragEndInViewport.dy.clamp(0.0, _dragGutterExtent);
    final speedPercent = 1.0 - (gutterAmount / _dragGutterExtent);
    final scrollAmount = lerpDouble(0, _maxDragSpeed, speedPercent);

    _scrollController.position.jumpTo(_scrollController.offset - scrollAmount);
  }

  void _startScrollingDown() {
    if (_scrollDownOnTick) {
      return;
    }

    _scrollDownOnTick = true;
    _ticker.start();
  }

  void _stopScrollingDown() {
    if (!_scrollDownOnTick) {
      return;
    }

    _scrollDownOnTick = false;
    _ticker.stop();
  }

  void _scrollDown() {
    if (_scrollController.offset >=
        _scrollController.position.maxScrollExtent) {
      return;
    }

    final editorBox = context.findRenderObject() as RenderBox;
    final gutterAmount = (editorBox.size.height - _dragEndInViewport.dy)
        .clamp(0.0, _dragGutterExtent);
    final speedPercent = 1.0 - (gutterAmount / _dragGutterExtent);
    final scrollAmount = lerpDouble(0, _maxDragSpeed, speedPercent);

    _scrollController.position.jumpTo(_scrollController.offset + scrollAmount);
  }

  void _onTick(elapsedTime) {
    if (_scrollUpOnTick) {
      _scrollUp();
    }
    if (_scrollDownOnTick) {
      _scrollDown();
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildIgnoreKeyPresses(
      child: _buildCursorStyle(
        child: _buildKeyboardAndMouseInput(
          child: SizedBox.expand(
            child: Stack(
              children: [
                _buildDocumentContainer(
                  document: widget.child,
                ),
                Positioned.fill(
                  child: widget.showDebugPaint
                      ? _buildDragSelection()
                      : SizedBox(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Wraps the `child` with a `Shortcuts` widget that ignores arrow keys,
  /// enter, backspace, and delete.
  ///
  /// This doesn't prevent the editor from responding to these keys, it just
  /// prevents Flutter from attempting to do anything with them. I put this
  /// here because I was getting recurring sounds from the Mac window as
  /// I pressed various key combinations. This hack prevents most of them.
  /// TODO: figure out the correct way to deal with this situation.
  Widget _buildIgnoreKeyPresses({
    @required Widget child,
  }) {
    return Shortcuts(
      shortcuts: <LogicalKeySet, Intent>{
        // Up arrow
        LogicalKeySet(LogicalKeyboardKey.arrowUp): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.shift):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.alt):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.meta):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.meta,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.meta): DoNothingIntent(),
        // Down arrow
        LogicalKeySet(LogicalKeyboardKey.arrowDown): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.shift):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.alt):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.meta):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.meta,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowDown, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.meta): DoNothingIntent(),
        // Left arrow
        LogicalKeySet(LogicalKeyboardKey.arrowLeft): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.shift):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.alt):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.meta):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.meta,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.meta): DoNothingIntent(),
        // Right arrow
        LogicalKeySet(LogicalKeyboardKey.arrowRight): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.shift):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.alt):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.meta):
            DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.meta,
            LogicalKeyboardKey.alt): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.arrowRight, LogicalKeyboardKey.shift,
            LogicalKeyboardKey.meta): DoNothingIntent(),
        // Misc keys
        LogicalKeySet(LogicalKeyboardKey.enter): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.backspace): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.delete): DoNothingIntent(),
        LogicalKeySet(LogicalKeyboardKey.tab): DoNothingIntent(),
      },
      child: child,
    );
  }

  Widget _buildCursorStyle({
    Widget child,
  }) {
    return AnimatedBuilder(
      animation: _cursorStyle,
      builder: (context, child) {
        return Listener(
          onPointerHover: _onMouseMove,
          child: MouseRegion(
            cursor: _cursorStyle.value,
            child: child,
          ),
        );
      },
      child: child,
    );
  }

  Widget _buildKeyboardAndMouseInput({
    Widget child,
  }) {
    return Listener(
      onPointerSignal: _onPointerSignal,
      child: RawKeyboardListener(
        focusNode: _rootFocusNode,
        onKey: _onKeyPressed,
        autofocus: true,
        child: RawGestureDetector(
          behavior: HitTestBehavior.translucent,
          gestures: <Type, GestureRecognizerFactory>{
            TapSequenceGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                TapSequenceGestureRecognizer>(
              () => TapSequenceGestureRecognizer(),
              (TapSequenceGestureRecognizer recognizer) {
                recognizer
                  ..onTapDown = _onTapDown
                  ..onDoubleTapDown = _onDoubleTapDown
                  ..onDoubleTap = _onDoubleTap
                  ..onTripleTapDown = _onTripleTapDown
                  ..onTripleTap = _onTripleTap;
              },
            ),
            PanGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<PanGestureRecognizer>(
              () => PanGestureRecognizer(),
              (PanGestureRecognizer recognizer) {
                recognizer
                  ..onStart = _onPanStart
                  ..onUpdate = _onPanUpdate
                  ..onEnd = _onPanEnd
                  ..onCancel = _onPanCancel;
              },
            ),
          },
          child: child,
        ),
      ),
    );
  }

  Widget _buildDocumentContainer({
    Widget document,
  }) {
    return SingleChildScrollView(
      controller: _scrollController,
      physics: NeverScrollableScrollPhysics(),
      child: Row(
        children: [
          Spacer(),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: 400),
            child: document,
          ),
          Spacer(),
        ],
      ),
    );
  }

  Widget _buildDragSelection() {
    return CustomPaint(
      painter: DragRectanglePainter(
        selectionRect: _dragRectInViewport,
      ),
      size: Size.infinite,
    );
  }
}

enum SelectionType {
  position,
  word,
  paragraph,
}

/// Executes this action, if the action wants to run, and returns
/// a desired `ExecutionInstruction` to either continue or halt
/// execution of actions.
///
/// It is possible that an action makes changes and then returns
/// `ExecutionInstruction.continueExecution` to continue execution.
///
/// It is possible that an action does nothing and then returns
/// `ExecutionInstruction.haltExecution` to prevent further execution.
typedef DocumentKeyboardAction = ExecutionInstruction Function({
  @required EditContext editContext,
  @required RawKeyEvent keyEvent,
});

enum ExecutionInstruction {
  continueExecution,
  haltExecution,
}

/// Paints a rectangle border around the given `selectionRect`.
class DragRectanglePainter extends CustomPainter {
  DragRectanglePainter({
    this.selectionRect,
    Listenable repaint,
  }) : super(repaint: repaint);

  final Rect selectionRect;
  final Paint _selectionPaint = Paint()
    ..color = Colors.red
    ..style = PaintingStyle.stroke;

  @override
  void paint(Canvas canvas, Size size) {
    if (selectionRect != null) {
      print('Painting drag rect: $selectionRect');
      canvas.drawRect(selectionRect, _selectionPaint);
    }
  }

  @override
  bool shouldRepaint(DragRectanglePainter oldDelegate) {
    return oldDelegate.selectionRect != selectionRect;
  }
}
