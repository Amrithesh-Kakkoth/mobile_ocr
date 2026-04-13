import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobile_ocr/mobile_ocr.dart';

List<Offset> _rectPoints(Rect rect) {
  return <Offset>[
    rect.topLeft,
    Offset(rect.right, rect.top),
    rect.bottomRight,
    Offset(rect.left, rect.bottom),
  ];
}

TextBlock _blockFromRect(String text, Rect rect) {
  final double characterWidth = rect.width / text.length;
  return TextBlock(
    text: text,
    confidence: 1.0,
    points: _rectPoints(rect),
    characters: List<CharacterBox>.generate(text.length, (index) {
      final double left = rect.left + (characterWidth * index);
      final double right = index == text.length - 1
          ? rect.right
          : left + characterWidth;
      return CharacterBox(
        text: text[index],
        confidence: 1.0,
        points: _rectPoints(Rect.fromLTRB(left, rect.top, right, rect.bottom)),
      );
    }),
  );
}

Widget _buildTestHarness({
  required TextOverlayController controller,
  required List<TextBlock> textBlocks,
  void Function(String)? onTextCopied,
  bool isImageZoomed = false,
  ZoomedInteractionPolicy zoomedInteractionPolicy =
      ZoomedInteractionPolicy.panFirst,
  double uiScale = 1.0,
  Offset uiOffset = Offset.zero,
  bool applyParentTransform = false,
}) {
  Widget overlay = TextOverlayWidget(
    imageSize: const Size(320, 200),
    textBlocks: textBlocks,
    controller: controller,
    onTextCopied: onTextCopied,
    isImageZoomed: isImageZoomed,
    uiScale: uiScale,
    uiOffset: uiOffset,
    zoomedInteractionPolicy: zoomedInteractionPolicy,
  );

  if (applyParentTransform) {
    overlay = Transform(
      alignment: Alignment.center,
      transform: Matrix4.identity()
        ..translate(uiOffset.dx, uiOffset.dy)
        ..scale(uiScale),
      child: overlay,
    );
  }

  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          key: const Key('overlay-host'),
          width: 320,
          height: 200,
          child: overlay,
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('toolbar stays visible when zoomed and panned', (tester) async {
    final controller = TextOverlayController();
    final textBlocks = <TextBlock>[
      _blockFromRect('HELLO', const Rect.fromLTWH(250, 56, 54, 24)),
    ];

    await tester.pumpWidget(
      _buildTestHarness(
        controller: controller,
        textBlocks: textBlocks,
        uiScale: 2.0,
        uiOffset: const Offset(120, 0),
        applyParentTransform: true,
      ),
    );
    await tester.pump();

    expect(controller.selectAllText(), isTrue);
    await tester.pumpAndSettle();

    final Rect hostRect = tester.getRect(find.byKey(const Key('overlay-host')));
    final Rect copyRect = tester.getRect(find.text('Copy'));
    final Rect selectAllRect = tester.getRect(find.text('Select all'));

    expect(copyRect.left, greaterThanOrEqualTo(hostRect.left));
    expect(copyRect.top, greaterThanOrEqualTo(hostRect.top));
    expect(selectAllRect.right, lessThanOrEqualTo(hostRect.right));
    expect(selectAllRect.bottom, lessThanOrEqualTo(hostRect.bottom));
  });

  testWidgets('panFirst ignores drag selection while zoomed', (tester) async {
    final controller = TextOverlayController();
    final textBlocks = <TextBlock>[
      _blockFromRect('HELLO', const Rect.fromLTWH(96, 64, 96, 24)),
    ];

    await tester.pumpWidget(
      _buildTestHarness(
        controller: controller,
        textBlocks: textBlocks,
        isImageZoomed: true,
        zoomedInteractionPolicy: ZoomedInteractionPolicy.panFirst,
      ),
    );
    await tester.pump();

    final Rect hostRect = tester.getRect(find.byKey(const Key('overlay-host')));
    await tester.dragFrom(
      hostRect.topLeft + const Offset(120, 76),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();

    expect(controller.hasActiveSelection, isFalse);
    expect(find.text('Copy'), findsNothing);
  });

  testWidgets('interactive mode still supports drag selection when zoomed', (
    tester,
  ) async {
    final controller = TextOverlayController();
    final textBlocks = <TextBlock>[
      _blockFromRect('HELLO', const Rect.fromLTWH(96, 64, 96, 24)),
    ];

    await tester.pumpWidget(
      _buildTestHarness(
        controller: controller,
        textBlocks: textBlocks,
        isImageZoomed: true,
        zoomedInteractionPolicy: ZoomedInteractionPolicy.interactive,
      ),
    );
    await tester.pump();

    final Rect hostRect = tester.getRect(find.byKey(const Key('overlay-host')));
    await tester.dragFrom(
      hostRect.topLeft + const Offset(120, 76),
      const Offset(40, 0),
    );
    await tester.pumpAndSettle();

    expect(controller.hasActiveSelection, isTrue);
    expect(find.text('Copy'), findsOneWidget);
  });

  testWidgets(
    'non-zoomed long press keeps the full word selected after slight drift',
    (tester) async {
      final controller = TextOverlayController();
      String? copiedText;
      final textBlocks = <TextBlock>[
        _blockFromRect('HELLO', const Rect.fromLTWH(96, 64, 96, 24)),
      ];

      await tester.pumpWidget(
        _buildTestHarness(
          controller: controller,
          textBlocks: textBlocks,
          onTextCopied: (text) => copiedText = text,
        ),
      );
      await tester.pump();

      final Rect hostRect = tester.getRect(
        find.byKey(const Key('overlay-host')),
      );
      final TestGesture gesture = await tester.startGesture(
        hostRect.topLeft + const Offset(120, 76),
      );
      await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
      await gesture.moveBy(const Offset(10, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();

      expect(copiedText, 'HELLO');
    },
  );
}
