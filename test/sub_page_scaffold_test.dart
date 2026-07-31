import 'package:esk8os_mobile/widgets/esk8_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Sub-pages are pushed from two hosts: the dashboard's nested deck navigator
/// (insets already consumed) and the root navigator from the scan screen
/// (insets NOT consumed). The shared scaffold has to look the same in both,
/// which is what these tests pin down.
void main() {
  const insets = EdgeInsets.fromLTRB(0, 48, 0, 24);

  Widget host({required EdgeInsets padding, required Widget child}) =>
      MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(padding: padding, viewPadding: padding),
          child: child,
        ),
      );

  Widget page() => SubPageScaffold(
    title: 'Trip Playback',
    actions: [
      IconButton(
        icon: const Icon(Icons.ios_share),
        onPressed: () {},
        tooltip: 'Share',
      ),
    ],
    children: const [Expanded(child: Center(child: Text('BODY')))],
  );

  testWidgets('header clears the status bar / cutout as a root route', (
    tester,
  ) async {
    await tester.pumpWidget(host(padding: insets, child: page()));

    // The header must start below the cutout, not under it.
    expect(tester.getTopLeft(find.text('TRIP PLAYBACK')).dy, greaterThan(48));
    // ...and the body must stop above the gesture bar.
    final bodyBottom = tester.getBottomLeft(find.text('BODY')).dy;
    final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
    expect(bodyBottom, lessThan(screenHeight - 24));
  });

  testWidgets('adds no second gap when the host already consumed the insets', (
    tester,
  ) async {
    await tester.pumpWidget(host(padding: EdgeInsets.zero, child: page()));

    // Inside the deck the shell has already applied (and removed) the padding,
    // so the header sits flush at the top of the content area.
    expect(tester.getTopLeft(find.byType(SubPageHeader)).dy, 0);
  });

  testWidgets('title and actions render through the shared header', (
    tester,
  ) async {
    await tester.pumpWidget(host(padding: insets, child: page()));

    expect(find.byType(SubPageHeader), findsOneWidget);
    expect(find.text('TRIP PLAYBACK'), findsOneWidget); // header upper-cases
    expect(find.byIcon(Icons.arrow_back), findsOneWidget); // consistent back
    expect(find.byIcon(Icons.ios_share), findsOneWidget);
  });
}
