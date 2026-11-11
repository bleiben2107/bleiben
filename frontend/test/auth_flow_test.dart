import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:bleiben/app.dart';
import 'package:bleiben/core/network/api_client.dart';
import 'package:bleiben/core/storage/session_store.dart';
import 'package:bleiben/features/auth/auth_controller.dart';
import 'package:bleiben/features/auth/login_screen.dart';

/// Minimal in-memory stand-in for the Bleiben API's auth/account/org routes.
class FakeApi {
  final requests = <String>[];
  Map<String, dynamic>? lastSignup;
  Map<String, dynamic>? lastProfile;
  Map<String, dynamic>? lastInvite;
  String role = 'owner';
  String? orgName;

  Map<String, dynamic> user = {
    'id': 1,
    'name': 'Asha Rao',
    'email': 'asha@example.com',
    'email_verified': true,
    'phone': null,
    'phone_verified': false,
    'avatar_url': null,
    'profile': <String, dynamic>{},
  };

  List<Map<String, dynamic>> get memberships => orgName == null
      ? []
      : [
          {
            'org_id': 1,
            'org_name': orgName,
            'role': role,
            'permissions': role == 'read_only'
                ? ['org.read', 'team.read']
                : ['org.read', 'org.update', 'team.read', 'team.manage'],
          },
        ];

  Map<String, dynamic> get session => {
        'access_token': 'tok',
        'user': user,
        'memberships': memberships,
      };

  late final client = MockClient((req) async {
    final path = req.url.path;
    requests.add('${req.method} $path');
    final body = req.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(req.body) as Map<String, dynamic>;
    http.Response json(Object data, [int status = 200]) =>
        http.Response(jsonEncode(data), status,
            headers: {'content-type': 'application/json'});

    switch ('${req.method} $path') {
      case 'POST /api/auth/signup/request-otp':
        if (body['email'] == 'taken@example.com') {
          return json({
            'detail':
                'An account with this email already exists. Please log in.',
            'action': 'login'
          }, 409);
        }
        lastSignup = body;
        return json({
          'sent_to': body['email'],
          'resend_in': 60,
          'channel': 'email',
          'dev_code': '123456'
        }, 202);
      case 'POST /api/auth/signup/verify-otp':
        if (body['code'] != '123456') {
          return json({'detail': 'Incorrect OTP. 4 attempts left.'}, 400);
        }
        user = {
          ...user,
          'name': lastSignup?['name'] ?? user['name'],
          'email': lastSignup?['email'] ?? user['email'],
        };
        orgName ??= user['name'] as String;
        return json(session, 201);
      case 'POST /api/auth/login/request-otp':
        if (body['identifier'] == 'nobody@example.com') {
          return json({
            'detail': 'No account found with this email. Please sign up.',
            'action': 'signup'
          }, 404);
        }
        return json({
          'sent_to': body['identifier'],
          'resend_in': 60,
          'channel': 'email',
          'dev_code': '123456'
        }, 202);
      case 'POST /api/auth/login/verify-otp':
        return body['code'] == '123456'
            ? json(session)
            : json({'detail': 'Incorrect OTP. 4 attempts left.'}, 400);
      case 'GET /api/auth/me':
        return json({...user, 'memberships': memberships});
      case 'PATCH /api/account/profile':
        lastProfile = body;
        user = {
          ...user,
          'name': [body['first_name'], body['last_name']]
              .where((p) => (p as String).isNotEmpty)
              .join(' '),
          'profile': body,
        };
        return json(user);
      case 'POST /api/account/contact/request-otp':
        return json({
          'sent_to': body['value'],
          'resend_in': 60,
          'channel': body['channel'],
          'dev_code': '654321'
        }, 202);
      case 'POST /api/account/contact/verify-otp':
        if (body['code'] != '654321') {
          return json({'detail': 'Incorrect OTP. 4 attempts left.'}, 400);
        }
        user = body['channel'] == 'email'
            ? {...user, 'email': body['value'], 'email_verified': true}
            : {
                ...user,
                'phone': '+91${body['value']}',
                'phone_verified': true
              };
        return json(user);
      case 'POST /api/orgs':
        orgName = body['name'] as String;
        return json({'id': 1, 'name': orgName, 'role': 'owner'}, 201);
      case 'PATCH /api/orgs/1':
        orgName = body['name'] as String;
        return json({'id': 1, 'name': orgName, 'role': role});
      case 'GET /api/orgs/1/members':
        return json([
          {'id': 1, 'role': role, 'status': 'active', 'user': user},
          if (lastInvite != null)
            {
              'id': 2,
              'role': lastInvite!['role'],
              'status': 'invited',
              'invited_email': lastInvite!['email'],
              'user': null,
            },
        ]);
      case 'POST /api/orgs/1/invites':
        lastInvite = body;
        return json({'id': 2}, 201);
    }
    return json({'detail': 'not found'}, 404);
  });
}

Future<(AuthController, FakeApi)> pumpApp(WidgetTester tester,
    {FakeApi? fake, bool signedIn = false}) async {
  GoogleFonts.config.allowRuntimeFetching = false;
  SharedPreferences.setMockInitialValues(
      signedIn ? {'bleiben_token': 'tok'} : {});
  tester.view.physicalSize = const Size(1280, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final api = fake ?? FakeApi();
  final session = SessionStore();
  await session.load();
  final client = ApiClient(session: session, httpClient: api.client);
  final auth = AuthController(api: client, session: session);
  if (signedIn) await auth.loadProfile();
  await tester.pumpWidget(BleibenApp(auth: auth, api: client));
  await tester.pump();
  return (auth, api);
}

Future<void> openLogin(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu and account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sign up / Sign in'));
  await tester.pumpAndSettle();
}

/// Signed-in users stay on the homepage (as on homyhuts); Account settings
/// opens from the account menu.
Future<void> openAccountSettings(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Menu and account'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Account settings'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'sign up: name + email (+ optional phone), OTP by email, back on the homepage',
      (tester) async {
    final (auth, fake) = await pumpApp(tester);
    await openLogin(tester);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    expect(find.text('Create your account'), findsOneWidget);
    // Required fields are validated before anything is sent.
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Name is required'), findsOneWidget);
    expect(find.text('Email is required'), findsOneWidget);
    expect(fake.requests.where((r) => r.contains('signup')), isEmpty);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name *'), 'Asha Rao');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'), 'asha@example.com');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Phone number'), '9876543210');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    expect(fake.lastSignup?['name'], 'Asha Rao');
    expect(fake.lastSignup?['phone'], '9876543210');
    expect(find.text('Enter OTP'), findsOneWidget);
    expect(find.text('Please enter the OTP sent to asha@example.com'),
        findsOneWidget);
    expect(find.textContaining('team@bleiben.co.in'), findsOneWidget);
    expect(find.text('Resend OTP (60s)'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.pumpAndSettle();
    expect(find.text('Incorrect OTP. 4 attempts left.'), findsOneWidget);

    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isTrue);
    expect(fake.requests, contains('POST /api/auth/signup/verify-otp'));
    // No separate organisation screen: it is created at sign-up.
    expect(fake.requests, isNot(contains('POST /api/orgs')));

    // Like homyhuts: back on the homepage, signed in (avatar shows the
    // initial); nothing else is forced on them.
    expect(find.text('Enter OTP'), findsNothing);
    expect(find.text('Log in'), findsNothing);
    expect(find.byTooltip('Menu and account'), findsOneWidget);
    expect(find.text('A'), findsWidgets, reason: 'initial on the avatar');
    expect(find.text('Personal Info'), findsNothing);
  });

  testWidgets('sign up with an existing email offers to log in instead',
      (tester) async {
    await pumpApp(tester);
    await openLogin(tester);
    await tester.tap(find.text('Sign up'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Full name *'), 'Asha Rao');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email *'), 'taken@example.com');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    expect(find.textContaining('already exists'), findsOneWidget);
    await tester.tap(find.text('Log in instead'));
    await tester.pumpAndSettle();
    expect(find.text('Welcome back'), findsOneWidget);
    expect(
        find.widgetWithText(TextFormField, 'taken@example.com'), findsOneWidget,
        reason: 'email carried over');
  });

  testWidgets('log in: email → OTP → signed in on the homepage, log out',
      (tester) async {
    final (auth, fake) = await pumpApp(tester);
    await openLogin(tester);

    expect(find.text('Welcome back'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email or phone number *'),
        'asha@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please enter the OTP sent to asha@example.com'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pumpAndSettle();

    expect(auth.isSignedIn, isTrue);
    expect(fake.requests, contains('POST /api/auth/login/verify-otp'));
    expect(find.text('Enter OTP'), findsNothing);
    expect(find.byTooltip('Menu and account'), findsOneWidget);

    await tester.tap(find.byTooltip('Menu and account'));
    await tester.pumpAndSettle();
    expect(find.text('Sign up / Sign in'), findsNothing);
    await tester.tap(find.text('Log out'));
    await tester.pumpAndSettle();
    expect(auth.isSignedIn, isFalse);
  });

  testWidgets('log in with an unknown email offers to sign up', (tester) async {
    await pumpApp(tester);
    await openLogin(tester);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email or phone number *'),
        'nobody@example.com');
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.textContaining('No account found'), findsOneWidget);
    await tester.tap(find.text('Sign up instead'));
    await tester.pumpAndSettle();
    expect(find.text('Create your account'), findsOneWidget);
  });

  testWidgets('signed-in menu: only Account settings and Log out act',
      (tester) async {
    final fake = FakeApi()..orgName = 'Hill Homes';
    final (auth, _) = await pumpApp(tester, fake: fake, signedIn: true);
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Menu and account'));
    await tester.pumpAndSettle();
    expect(find.text('Asha Rao'), findsOneWidget);
    for (final label in [
      'Book your stay',
      'About us',
      'Trips',
      'Contact us',
      'Help centre'
    ]) {
      expect(find.text(label), findsWidgets);
    }
    // A placeholder entry just closes the menu.
    await tester.tap(find.text('Trips').last);
    await tester.pumpAndSettle();
    expect(find.text('Trips'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(auth.isSignedIn, isTrue);
  });

  testWidgets('account settings: personal info saves to the API',
      (tester) async {
    final fake = FakeApi()..orgName = 'Hill Homes';
    final (auth, _) = await pumpApp(tester, fake: fake, signedIn: true);
    await tester.pumpAndSettle();
    await openAccountSettings(tester);

    expect(find.text('Personal Info'), findsOneWidget);
    expect(find.text('Account Verifications'), findsOneWidget);
    expect(find.text('Pending'), findsOneWidget, reason: 'phone not verified');
    expect(find.text('asha@example.com'), findsOneWidget);
    expect(find.text('Add'), findsOneWidget, reason: 'no phone yet');
    // The name from sign-up is split into first / last.
    expect(find.widgetWithText(TextFormField, 'Asha'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Rao'), findsOneWidget);

    await tester.enterText(find.byKey(const ValueKey('field-first_name')), '');
    await tester.enterText(find.byKey(const ValueKey('field-pincode')), '12');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();
    expect(find.text('Pincode should be 6 digits'), findsOneWidget);
    expect(fake.lastProfile, isNull);

    await tester.enterText(
        find.byKey(const ValueKey('field-first_name')), 'Asha');
    await tester.enterText(
        find.byKey(const ValueKey('field-last_name')), 'Menon');
    await tester.enterText(
        find.byKey(const ValueKey('field-pincode')), '682001');
    await tester.enterText(find.byKey(const ValueKey('field-city')), 'Kochi');
    await tester.ensureVisible(find.text('Save changes'));
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect(fake.lastProfile?['last_name'], 'Menon');
    expect(fake.lastProfile?['city'], 'Kochi');
    expect(fake.lastProfile?['email_notifications'], isTrue);
    expect(find.text('Changes saved'), findsOneWidget);
    expect(auth.displayName, 'Asha Menon');
  });

  testWidgets('account settings: add a phone number with an OTP',
      (tester) async {
    final fake = FakeApi()..orgName = 'Hill Homes';
    final (auth, _) = await pumpApp(tester, fake: fake, signedIn: true);
    await tester.pumpAndSettle();
    await openAccountSettings(tester);

    await tester.tap(find.text('Add'));
    await tester.pumpAndSettle();
    expect(find.text('Add phone number'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '9822222222');
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(
        find.text('Please enter the OTP sent to 9822222222'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();
    expect(find.text('Incorrect OTP. 4 attempts left.'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '654321');
    await tester.tap(find.text('Verify'));
    await tester.pumpAndSettle();

    expect(auth.account.phone, '+919822222222');
    expect(auth.account.verified, isTrue);
    expect(find.text('+919822222222'), findsOneWidget);
    expect(find.text('Verified'), findsOneWidget, reason: 'sidebar badge');
  });

  testWidgets('account settings: Team & roles lists roles and invites',
      (tester) async {
    final fake = FakeApi()..orgName = 'Hill Homes';
    await pumpApp(tester, fake: fake, signedIn: true);
    await tester.pumpAndSettle();
    await openAccountSettings(tester);

    await tester.tap(find.text('Team & roles'));
    await tester.pumpAndSettle();
    expect(find.text('Hill Homes'), findsOneWidget);
    expect(find.text('Your role: Owner'), findsOneWidget);
    for (final r in ['Owner', 'Manager', 'Staff', 'Read-only']) {
      expect(find.text(r), findsWidgets);
    }
    expect(find.text('Team members (1)'), findsOneWidget);

    await tester.tap(find.text('Invite member'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.widgetWithText(TextFormField, 'Email'), 'ravi@example.com');
    await tester.tap(find.text('Manager').last);
    await tester.tap(find.text('Send invite'));
    await tester.pumpAndSettle();
    expect(fake.lastInvite, {'email': 'ravi@example.com', 'role': 'manager'});
    expect(find.text('Team members (2)'), findsOneWidget);
    expect(find.text('ravi@example.com'), findsOneWidget);
  });

  testWidgets('read-only members can see the team but not invite',
      (tester) async {
    final fake = FakeApi()
      ..orgName = 'Hill Homes'
      ..role = 'read_only';
    await pumpApp(tester, fake: fake, signedIn: true);
    await tester.pumpAndSettle();
    await openAccountSettings(tester);
    await tester.tap(find.text('Team & roles'));
    await tester.pumpAndSettle();

    expect(find.text('Your role: Read-only'), findsOneWidget);
    expect(find.text('Invite member'), findsNothing);
    expect(find.bySemanticsLabel('Edit organisation name'), findsNothing);
  });

  testWidgets('login screen keeps the sign-up heading', (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    final session = SessionStore();
    final api = ApiClient(session: session, httpClient: FakeApi().client);
    await tester.pumpWidget(MaterialApp(
      home: LoginScreen(
        auth: AuthController(api: api, session: session),
        initialRegister: true,
      ),
    ));
    expect(find.text('Create your account'), findsOneWidget);
  });
}
