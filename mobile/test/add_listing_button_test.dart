import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:savespoon/features/listings/presentation/widgets/add_listing_button.dart';

void main() {
  late int presses;

  Future<void> pumpButton(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    presses = 0;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          home: Scaffold(
            body: Center(child: AddListingButton(onPressed: () => presses++)),
          ),
        ),
      ),
    );
  }

  double scale(WidgetTester tester) => tester
      .widget<ScaleTransition>(
        find
            .ancestor(
              of: find.text('Add Listing'),
              matching: find.byType(ScaleTransition),
            )
            .first,
      )
      .scale
      .value;

  double turn(WidgetTester tester) => tester
      .widget<RotationTransition>(
        find
            .ancestor(
              of: find.byIcon(Icons.add),
              matching: find.byType(RotationTransition),
            )
            .first,
      )
      .turns
      .value;

  testWidgets('pressing shrinks the button and turns the icon', (tester) async {
    await pumpButton(tester);
    expect(scale(tester), 1);
    expect(turn(tester), 0);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add Listing')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(scale(tester), closeTo(0.9, 0.001));
    expect(turn(tester), closeTo(0.25, 0.001));

    await gesture.up();
    await tester.pumpAndSettle();
  });

  testWidgets('pressing fades to light green and returns afterwards', (
    tester,
  ) async {
    await pumpButton(tester);
    final colors = Theme.of(tester.element(find.byType(AddListingButton)))
        .colorScheme;
    ButtonStyle style() => tester
        .widget<ButtonStyleButton>(
          find.byWidgetPredicate((widget) => widget is ButtonStyleButton),
        )
        .style!;

    expect(style().backgroundColor!.resolve({}), colors.primary);
    expect(style().foregroundColor!.resolve({}), colors.onPrimary);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add Listing')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));

    expect(style().backgroundColor!.resolve({}), colors.primaryContainer);
    expect(style().foregroundColor!.resolve({}), colors.primary);

    await gesture.up();
    await tester.pumpAndSettle();

    expect(style().backgroundColor!.resolve({}), colors.primary);
    expect(style().foregroundColor!.resolve({}), colors.onPrimary);
  });

  testWidgets('a quick tap still plays the animation before opening', (
    tester,
  ) async {
    await pumpButton(tester);

    await tester.tap(find.text('Add Listing'));
    await tester.pump();
    expect(presses, 0);

    await tester.pump(const Duration(milliseconds: 130));
    expect(presses, 1);

    await tester.pumpAndSettle();
    expect(scale(tester), 1);
    expect(turn(tester), 0);
  });

  testWidgets('a double tap opens the form only once', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('Add Listing'));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tap(find.text('Add Listing'));
    await tester.pumpAndSettle();

    expect(presses, 1);
  });

  testWidgets('it can be pressed again after finishing', (tester) async {
    await pumpButton(tester);

    await tester.tap(find.text('Add Listing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add Listing'));
    await tester.pumpAndSettle();

    expect(presses, 2);
  });

  testWidgets('dragging off the button springs back without opening', (
    tester,
  ) async {
    await pumpButton(tester);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add Listing')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    await gesture.moveBy(const Offset(0, 400));
    await gesture.up();
    await tester.pumpAndSettle();

    expect(presses, 0);
    expect(scale(tester), 1);
  });

  testWidgets('it skips the motion when animations are turned off', (
    tester,
  ) async {
    await pumpButton(tester, disableAnimations: true);

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Add Listing')),
    );
    await tester.pump(const Duration(milliseconds: 120));
    expect(scale(tester), 1);

    await gesture.up();
    await tester.pump();
    expect(presses, 1);
    await tester.pumpAndSettle();
  });
}
