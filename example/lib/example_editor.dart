import 'dart:collection';
import 'dart:math';

import 'package:example/custom_text.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_richtext/flutter_richtext.dart';

class LengthMap {
  LengthMap({
    this.start,
    this.end,
    this.str,
  });

  String str;
  int start;
  int end;
}

class Mention {
  Mention({
    this.trigger,
    this.data = const [],
    this.style,
    this.matchAll = false,
    this.suggestionBuilder,
    this.disableMarkup = false,
    this.markupBuilder,
  });

  /// A single character that will be used to trigger the suggestions.
  final String trigger;

  /// List of Map to represent the suggestions shown to the user
  ///
  /// You need to provide two properties `id` & `display` both are [String]
  /// You can also have any custom properties as you like to build custom suggestion
  /// widget.
  final List<Map<String, dynamic>> data;

  /// Style for the mention item in Input.
  final TextStyle style;

  /// Should every non-suggestion with the trigger character be matched
  final bool matchAll;

  /// Should the markup generation be disabled for this Mention Item.
  final bool disableMarkup;

  /// Build Custom suggestion widget using this builder.
  final Widget Function(Map<String, dynamic>) suggestionBuilder;

  /// Allows to set custom markup for the mentioned item.
  final String Function(String trigger, String mention, String value)
      markupBuilder;
}

class Annotation {
  Annotation({
    this.trigger,
    this.style,
    this.id,
    this.display,
    this.disableMarkup = false,
    this.markupBuilder,
  });

  TextStyle style;
  String id;
  String display;
  String trigger;
  bool disableMarkup;
  final String Function(String trigger, String mention, String value)
      markupBuilder;
}

class AddTextAttributionsCommand implements EditorCommand {
  AddTextAttributionsCommand({
    this.documentSelection,
    this.attributions,
  });

  final DocumentSelection documentSelection;
  final Set<String> attributions;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final nodes = document.getNodesInside(
        documentSelection.base, documentSelection.extent);
    if (nodes.isEmpty) {
      return;
    }

    // Calculate a DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final nodeRange = document.getRangeBetween(
        documentSelection.base, documentSelection.extent);

    final nodesAndSelections = LinkedHashMap<TextNode, TextRange>();
    bool alreadyHasAttributions = false;

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      final _textNode = textNode as TextNode;

      int startOffset = -1;
      int endOffset = -1;

      if (_textNode == nodes.first && _textNode == nodes.last) {
        // Handle selection within a single node
        final baseOffset =
            (documentSelection.base.nodePosition as TextPosition).offset;
        final extentOffset =
            (documentSelection.extent.nodePosition as TextPosition).offset;
        startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
        endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;
      } else if (_textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (nodeRange.start.nodePosition as TextPosition).offset;
        endOffset = max(_textNode.text.text.length - 1, 0);
      } else if (_textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;
        endOffset = (nodeRange.end.nodePosition as TextPosition).offset;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(_textNode.text.text.length - 1, 0);
      }

      // The attribution range needs the `start` and `end` to
      // be inclusive. Make sure the `endOffset` isn't equal
      // to the text length.
      if (endOffset == _textNode.text.text.length) {
        endOffset = _textNode.text.text.length - 1;
      }

      final selectionRange = TextRange(start: startOffset, end: endOffset);

      alreadyHasAttributions = alreadyHasAttributions ||
          _textNode.text.hasAttributionsWithin(
            attributions: attributions,
            range: selectionRange,
          );

      nodesAndSelections.putIfAbsent(_textNode, () => selectionRange);
    }

    // Toggle attributions.
    for (final entry in nodesAndSelections.entries) {
      for (String attribution in attributions) {
        final node = entry.key;
        final range = entry.value;

        node.text.addAttribution(
          attribution,
          range,
        );
      }
    }
  }
}

class RemoveTextAttributionsCommand implements EditorCommand {
  RemoveTextAttributionsCommand({
    this.documentSelection,
    this.attributions,
  });

  final DocumentSelection documentSelection;
  final Set<String> attributions;

  @override
  void execute(Document document, DocumentEditorTransaction transaction) {
    final nodes = document.getNodesInside(
        documentSelection.base, documentSelection.extent);
    if (nodes.isEmpty) {
      return;
    }

    // Calculate a DocumentRange so we know which DocumentPosition
    // belongs to the first node, and which belongs to the last node.
    final nodeRange = document.getRangeBetween(
        documentSelection.base, documentSelection.extent);

    final nodesAndSelections = LinkedHashMap<TextNode, TextRange>();
    bool alreadyHasAttributions = false;

    for (final textNode in nodes) {
      if (textNode is! TextNode) {
        continue;
      }

      final _textNode = textNode as TextNode;

      int startOffset = -1;
      int endOffset = -1;

      if (_textNode == nodes.first && _textNode == nodes.last) {
        // Handle selection within a single node
        final baseOffset =
            (documentSelection.base.nodePosition as TextPosition).offset;
        final extentOffset =
            (documentSelection.extent.nodePosition as TextPosition).offset;
        startOffset = baseOffset < extentOffset ? baseOffset : extentOffset;
        endOffset = baseOffset < extentOffset ? extentOffset : baseOffset;
      } else if (_textNode == nodes.first) {
        // Handle partial node selection in first node.
        startOffset = (nodeRange.start.nodePosition as TextPosition).offset;
        endOffset = max(_textNode.text.text.length - 1, 0);
      } else if (_textNode == nodes.last) {
        // Handle partial node selection in last node.
        startOffset = 0;
        endOffset = (nodeRange.end.nodePosition as TextPosition).offset;
      } else {
        // Handle full node selection.
        startOffset = 0;
        endOffset = max(_textNode.text.text.length - 1, 0);
      }

      // The attribution range needs the `start` and `end` to
      // be inclusive. Make sure the `endOffset` isn't equal
      // to the text length.
      if (endOffset == _textNode.text.text.length) {
        endOffset = _textNode.text.text.length - 1;
      }

      final selectionRange = TextRange(start: startOffset, end: endOffset);

      alreadyHasAttributions = alreadyHasAttributions ||
          _textNode.text.hasAttributionsWithin(
            attributions: attributions,
            range: selectionRange,
          );

      nodesAndSelections.putIfAbsent(_textNode, () => selectionRange);
    }

    // Toggle attributions.
    for (final entry in nodesAndSelections.entries) {
      for (String attribution in attributions) {
        final node = entry.key;
        final range = entry.value;
        node.text.removeAttribution(
          attribution,
          range,
        );
      }
    }
  }
}

/// Example of a rich text editor.
///
/// This editor will expand in functionality as the rich text
/// package expands.
class ExampleEditor extends StatefulWidget {
  @override
  _ExampleEditorState createState() => _ExampleEditorState();
}

class _ExampleEditorState extends State<ExampleEditor> {
  Document _doc;
  DocumentEditor _docEditor;
  DocumentComposer _composer;
  List<Mention> mentions;
  String _pattern = '';
  var _lengthMap = <LengthMap>[];
  Map<String, Annotation> data;

  Map<String, Annotation> mapToAnotation() {
    final data = <String, Annotation>{};

    // Loop over all the mention items and generate a suggestions matching list
    mentions.forEach((element) {
      // if matchAll is set to true add a general regex patteren to match with
      if (element.matchAll) {
        data['${element.trigger}([A-Za-z0-9])*'] = Annotation(
          style: element.style,
          id: null,
          display: null,
          trigger: element.trigger,
          disableMarkup: element.disableMarkup,
          markupBuilder: element.markupBuilder,
        );
      }

      element.data.forEach(
        (e) => data["${element.trigger}${e['display']}"] = e['style'] != null
            ? Annotation(
                style: e['style'],
                id: e['id'],
                display: e['display'],
                trigger: element.trigger,
                disableMarkup: element.disableMarkup,
                markupBuilder: element.markupBuilder,
              )
            : Annotation(
                style: element.style,
                id: e['id'],
                display: e['display'],
                trigger: element.trigger,
                disableMarkup: element.disableMarkup,
                markupBuilder: element.markupBuilder,
              ),
      );
    });

    return data;
  }

  @override
  void initState() {
    super.initState();
    _createMentionList();
    data = mapToAnotation();
    _pattern = "(${data.keys.map((key) => RegExp.escape(key)).join('|')})";
    _doc = _createInitialDocument();
    _docEditor = DocumentEditor(document: _doc);
    _composer = DocumentComposer();

    _docEditor.document.addListener(() {
      final node = _doc.getNode(_composer.selection.base);

      if (node.runtimeType == ParagraphNode) {
        final _node = node as ParagraphNode;

        suggestionListerner();
      }
    });
  }

  void _createMentionList() {
    mentions = [
      Mention(
          trigger: '@',
          style: TextStyle(
            color: Colors.amber,
          ),
          data: [
            {
              'id': '61as61fsa',
              'display': 'fayeedP',
              'full_name': 'Fayeed Pawaskar',
              'photo':
                  'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940'
            },
            {
              'id': '61asasgasgsag6a',
              'display': 'khaled',
              'full_name': 'DJ Khaled',
              'style': TextStyle(color: Colors.purple),
              'photo':
                  'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940'
            },
            {
              'id': 'asfgasga41',
              'display': 'markT',
              'full_name': 'Mark Twain',
              'photo':
                  'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940'
            },
            {
              'id': 'asfsaf451a',
              'display': 'JhonL',
              'full_name': 'Jhon Legend',
              'photo':
                  'https://images.pexels.com/photos/220453/pexels-photo-220453.jpeg?auto=compress&cs=tinysrgb&dpr=2&h=650&w=940'
            },
          ],
          matchAll: false,
          suggestionBuilder: (data) {
            return Container(
              padding: EdgeInsets.all(10.0),
              child: Row(
                children: <Widget>[
                  CircleAvatar(
                    backgroundImage: NetworkImage(
                      data['photo'],
                    ),
                  ),
                  SizedBox(
                    width: 20.0,
                  ),
                  Column(
                    children: <Widget>[
                      Text(data['full_name']),
                      Text('@${data['display']}'),
                    ],
                  )
                ],
              ),
            );
          }),
      Mention(
        trigger: '#',
        disableMarkup: true,
        style: TextStyle(
          color: Colors.blue,
        ),
        data: [
          {'id': 'reactjs', 'display': 'reactjs'},
          {'id': 'javascript', 'display': 'javascript'},
        ],
        matchAll: true,
      )
    ];
  }

  void suggestionListerner() {
    final node = _doc.getNode(_composer.selection.base);

    if (node.runtimeType == ParagraphNode) {
      final _node = node as ParagraphNode;

      final _textPosition =
          _composer.selection.base.nodePosition as TextPosition;

      final cursorPos = _textPosition.offset + 1;

      if (cursorPos >= 0) {
        var _pos = 0;

        _lengthMap = <LengthMap>[];

        // split on each word and generate a list with start & end position of each word.
        _node.text.text.split(RegExp(r'(\s)')).forEach((element) {
          _lengthMap.add(
              LengthMap(str: element, start: _pos, end: _pos + element.length));

          _pos = _pos + element.length + 1;
        });

        final val = _lengthMap.indexWhere((element) {
          final _pattern = mentions.map((e) => e.trigger).join('|');

          return element.end == cursorPos &&
              element.str.toLowerCase().contains(RegExp(_pattern));
        });

        print('show: ${val != -1} | $val');

        // showSuggestions.value = val != -1;

        // if (widget.onSuggestionVisibleChanged != null) {
        //   widget.onSuggestionVisibleChanged!(val != -1);
        // }

        // setState(() {
        //   _selectedMention = val == -1 ? null : lengthMap[val];
        // });
      }
    }
  }

  @override
  void dispose() {
    super.dispose();
  }

  void toggleBold() {
    final selection = _composer.selection;
    print(selection);

    _docEditor.executeCommand(ToggleTextAttributionsCommand(
      documentSelection: selection,
      attributions: {'bold'},
    ));

    _composer.notifyListeners();
  }

  Widget firstParagraphHintComponentBuilder(ComponentContext componentContext) {
    if (componentContext.documentNode is! ParagraphNode) {
      return null;
    }

    final textSelection = componentContext.nodeSelection == null ||
            componentContext.nodeSelection.nodeSelection is! TextSelection
        ? null
        : componentContext.nodeSelection.nodeSelection as TextSelection;
    if (componentContext.nodeSelection != null &&
        componentContext.nodeSelection.nodeSelection is! TextSelection) {}
    final showCaret = componentContext.nodeSelection != null
        ? componentContext.nodeSelection.isExtent
        : false;
    final highlightWhenEmpty = componentContext.nodeSelection == null
        ? false
        : componentContext.nodeSelection.highlightWhenEmpty;

    TextAlign textAlign = TextAlign.left;
    final textAlignName =
        (componentContext.documentNode as TextNode).metadata['textAlign'];
    switch (textAlignName) {
      case 'left':
        textAlign = TextAlign.left;
        break;
      case 'center':
        textAlign = TextAlign.center;
        break;
      case 'right':
        textAlign = TextAlign.right;
        break;
      case 'justify':
        textAlign = TextAlign.justify;
        break;
    }

    var children = <InlineSpan>[];

    final paragraphNode = componentContext.documentNode;
    if (paragraphNode is! ParagraphNode) {
      return null;
    }

    final node = paragraphNode as ParagraphNode;

    final text = node.text.text;

    if (_pattern == null || _pattern == '()') {
      children.add(TextSpan(text: text));
    } else {
      text.splitMapJoin(
        RegExp('$_pattern'),
        onMatch: (Match match) {
          children.add(
            TextSpan(
              text: match[0],
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        },
        onNonMatch: (String text) {
          children.add(TextSpan(text: text));
          return '';
        },
      );
    }

    return CustomTextComponent(
      key: componentContext.componentKey,
      pattern: _pattern,
      text: node.text,
      textStyleBuilder: componentContext.extensions[textStylesExtensionKey],
      metadata: (componentContext.documentNode as TextNode).metadata,
      textAlign: textAlign,
      textSelection: textSelection,
      selectionColor: (componentContext.extensions[selectionStylesExtensionKey]
              as SelectionStyle)
          .selectionColor,
      showCaret: showCaret,
      caretColor: (componentContext.extensions[selectionStylesExtensionKey]
              as SelectionStyle)
          .textCaretColor,
      highlightWhenEmpty: highlightWhenEmpty,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      child: Center(
        child: Column(
          children: [
            Container(
              height: 600,
              width: 500,
              child: Editor.custom(
                editor: _docEditor,
                composer: _composer,
                maxWidth: 600,
                padding:
                    const EdgeInsets.symmetric(vertical: 56, horizontal: 24),
                componentBuilders: [firstParagraphHintComponentBuilder],
              ),
            ),
            Row(
              children: [
                FlatButton(onPressed: toggleBold, child: Text('bold'))
              ],
            )
          ],
        ),
      ),
    );
  }
}

Document _createInitialDocument() {
  return MutableDocument(
    nodes: [
      ImageNode(
        id: DocumentEditor.createNodeId(),
        imageUrl: 'https://i.ytimg.com/vi/fq4N0hgOWzU/maxresdefault.jpg',
      ),
      ParagraphNode(
        id: DocumentEditor.createNodeId(),
        text: AttributedText(
          text: 'Example Document',
        ),
        metadata: {
          'blockType': 'header1',
        },
      ),
      HorizontalRuleNode(id: DocumentEditor.createNodeId()),
      ParagraphNode(
        id: DocumentEditor.createNodeId(),
        text: AttributedText(
          text:
              'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Phasellus sed sagittis urna. Aenean mattis ante justo, quis sollicitudin metus interdum id. Aenean ornare urna ac enim consequat mollis. In aliquet convallis efficitur. Phasellus convallis purus in fringilla scelerisque. Ut ac orci a turpis egestas lobortis. Morbi aliquam dapibus sem, vitae sodales arcu ultrices eu. Duis vulputate mauris quam, eleifend pulvinar quam blandit eget.',
        ),
      ),
      ParagraphNode(
        id: DocumentEditor.createNodeId(),
        text: AttributedText(
            text:
                'Cras vitae sodales nisi. Vivamus dignissim vel purus vel aliquet. Sed viverra diam vel nisi rhoncus pharetra. Donec gravida ut ligula euismod pharetra. Etiam sed urna scelerisque, efficitur mauris vel, semper arcu. Nullam sed vehicula sapien. Donec id tellus volutpat, eleifend nulla eget, rutrum mauris.'),
      ),
      ParagraphNode(
        id: DocumentEditor.createNodeId(),
        text: AttributedText(
          text:
              'Nam hendrerit vitae elit ut placerat. Maecenas nec congue neque. Fusce eget tortor pulvinar, cursus neque vitae, sagittis lectus. Duis mollis libero eu scelerisque ullamcorper. Pellentesque eleifend arcu nec augue molestie, at iaculis dui rutrum. Etiam lobortis magna at magna pellentesque ornare. Sed accumsan, libero vel porta molestie, tortor lorem eleifend ante, at egestas leo felis sed nunc. Quisque mi neque, molestie vel dolor a, eleifend tempor odio.',
        ),
      ),
      ParagraphNode(
        id: DocumentEditor.createNodeId(),
        text: AttributedText(
          text:
              'Etiam id lacus interdum, efficitur ex convallis, accumsan ipsum. Integer faucibus mollis mauris, a suscipit ante mollis vitae. Fusce justo metus, congue non lectus ac, luctus rhoncus tellus. Phasellus vitae fermentum orci, sit amet sodales orci. Fusce at ante iaculis nunc aliquet pharetra. Nam placerat, nisl in gravida lacinia, nisl nibh feugiat nunc, in sagittis nisl sapien nec arcu. Nunc gravida faucibus massa, sit amet accumsan dolor feugiat in. Mauris ut elementum leo. @fayeedP saf',
          // spans: AttributedSpans(attributions: [
          //   SpanMarker(
          //       attribution: 'bold',
          //       offset: 478,
          //       markerType: SpanMarkerType.start),
          //   SpanMarker(
          //       attribution: 'bold',
          //       offset: 485,
          //       markerType: SpanMarkerType.end),
          // ]),
        ),
      ),
    ],
  );
}
