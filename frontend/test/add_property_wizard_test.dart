import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:bleiben/features/stays/add_property_wizard_screen.dart';

void main() {
  testWidgets(
      'Complete Property Onboarding Wizard journey (20 steps: Steps 0 to 19)',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    tester.view.physicalSize = const Size(1440, 1024);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      const MaterialApp(
        home: AddPropertyWizardScreen(),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Verify Step 0 (Figma 6:2)
    expect(find.text('CHOOSE HOW TO ADD YOUR PROPERTY'), findsOneWidget);
    expect(find.text('Create Manually'), findsOneWidget);
    expect(find.text('Continue to create manually'), findsOneWidget);

    // 2. Tap "Continue to create manually" -> Moves to Step 1
    await tester.tap(find.text('Continue to create manually'));
    await tester.pumpAndSettle();

    // 3. Verify Step 1 is Figma 11:110 ("Select your property type")
    expect(find.text('Select your property type'), findsOneWidget);
    expect(find.textContaining('Choose one primary type that best describes'),
        findsOneWidget);
    expect(find.text('Save as Draft'), findsOneWidget);
    expect(find.text('Villa'), findsOneWidget);
    expect(find.text('Next'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    // 4. Select "Villa" card and tap "Next" -> Step 2
    await tester.tap(find.text('Villa'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 5. Verify Step 2 is Figma 15:2 ("Which of these best describes your place?")
    expect(
        find.text('Which of these best describes your place?'), findsOneWidget);
    expect(find.text('An entire place'), findsOneWidget);
    expect(find.text('A private room'), findsOneWidget);
    expect(find.text('A shared room'), findsOneWidget);

    // 6. Select "An entire place" and tap "Next" -> Step 3
    await tester.tap(find.text('An entire place'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 7. Verify Step 3: Owner vs Manager
    expect(find.text('Are you the property owner or manager?'), findsOneWidget);
    expect(find.text('I am the Property Owner'), findsOneWidget);
    expect(find.text('I am a Property Manager'), findsOneWidget);

    // Select "I am the Property Owner" and tap "Next" -> Step 4
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 8. Verify Step 4 is Figma 17:139 ("Add your property address")
    expect(find.text('Add your property address'), findsOneWidget);
    expect(find.text('Pin placed accurately'), findsOneWidget);
    expect(find.text('Enter Your Address'), findsOneWidget);
    await tester.enterText(
        find.byType(TextField).first, 'Lonavala, Maharashtra');
    await tester.pumpAndSettle();

    // Tap "Next" -> Step 5: Photos
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 9. Verify Step 5: Photos
    expect(find.text('Upload your property photos'), findsOneWidget);
    expect(
        find.textContaining('At least 10 photos recommended'), findsOneWidget);

    // Tap "Next" -> Step 6: Documents
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 10. Verify Step 6: Documents
    expect(find.text('Property ownership documents'), findsOneWidget);

    // Tap "Next" -> Step 7: Capacity & Floor plan
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 11. Verify Step 7: Capacity
    expect(find.text('How many guests can stay here?'), findsOneWidget);
    expect(find.text('Guests allowed'), findsOneWidget);

    // Tap "Next" -> Step 8: Amenities
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 12. Verify Step 8: Amenities
    expect(find.text('Tell guests what amenities you offer'), findsOneWidget);

    // Tap "Next" -> Step 9: Uniqueness
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 13. Verify Step 9: Uniqueness
    expect(find.text('What makes your place unique?'), findsOneWidget);

    // Tap "Next" -> Step 10: Experiences
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 14. Verify Step 10: Experiences
    expect(find.text('Experiences offered on-site'), findsOneWidget);

    // Tap "Next" -> Step 11: Title & Description
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 15. Verify Step 11: Headline
    expect(find.text('Give your property a headline & story'), findsOneWidget);

    // Tap "Next" -> Step 12: Neighbourhood
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 16. Verify Step 12: Neighbourhood
    expect(find.text('Describe the neighbourhood'), findsOneWidget);

    // Tap "Next" -> Step 13: Price
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 17. Verify Step 13: Price
    expect(find.text('Now, set your base price per night'), findsOneWidget);

    // Tap "Next" -> Step 14: Check-in / Check-out
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 18. Verify Step 14: Check-in / out
    expect(find.text('Check-in and check-out schedule'), findsOneWidget);

    // Tap "Next" -> Step 15: House rules
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 19. Verify Step 15: House rules
    expect(find.text('House rules & policies'), findsOneWidget);

    // Tap "Next" -> Step 16: Check-in method
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 20. Verify Step 16: Check-in method & Caretaker
    expect(find.text('Check-in method & on-ground support'), findsOneWidget);

    // Tap "Next" -> Step 17: Identity Verification (Matches user uploaded screenshot!)
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 21. Verify Step 17: ID Verification
    expect(find.text('Verify your identity'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget);
    expect(
        find.textContaining(
            'Use Homeyhuts Mobile App to complete profile verification'),
        findsOneWidget);
    expect(find.textContaining('Scan the code with your phone camera'),
        findsOneWidget);
    expect(find.text('Works on iPhone and Android'), findsOneWidget);

    // Tap "Next" -> Step 18: Preview
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 22. Verify Step 18: Listing preview
    expect(find.text('Preview your listing'), findsOneWidget);

    // Tap "Next" -> Step 19: Publish & Quick setup call
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();

    // 23. Verify Step 19: Publish screen
    expect(find.text("You're almost done!"), findsOneWidget);
    expect(find.text('Book a Quick Setup Call (Free)'), findsOneWidget);
    expect(find.text('Publish Listing Now'), findsOneWidget);

    // 24. Tap "Back" all the way back to verify navigation stack
    await tester.tap(find.text('Back'));
    await tester.pumpAndSettle();
    expect(find.text('Preview your listing'), findsOneWidget);
  });
}
