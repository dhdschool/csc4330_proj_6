import 'package:flutter/material.dart';

import '../services/moodle_api.dart';
import 'sign_in_screen.dart';

enum _Stage { checking, signIn, home }

/// Decides what the app opens to: the calendar when the backend already holds
/// a Moodle session, otherwise the sign-in screen. Signing in or out later
/// moves between the two.
class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.moodleService,
    required this.homeBuilder,
  });

  final MoodleService moodleService;

  /// Builds the calendar. Its callback reopens the sign-in screen, for users
  /// who skipped it.
  final Widget Function(BuildContext context, VoidCallback requestSignIn)
  homeBuilder;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  _Stage _stage = _Stage.checking;
  Uri? _loginUrl;
  String? _error;

  @override
  void initState() {
    super.initState();
    widget.moodleService.addListener(_onMoodleChanged);
    _check(atLaunch: true);
  }

  @override
  void dispose() {
    widget.moodleService.removeListener(_onMoodleChanged);
    super.dispose();
  }

  Future<void> _check({required bool atLaunch}) async {
    setState(() {
      _stage = _Stage.checking;
      _error = null;
    });
    try {
      final result = await widget.moodleService.isAuthorized();
      if (!mounted) return;
      setState(() {
        if (result.authorized) {
          _stage = _Stage.home;
        } else {
          _stage = _Stage.signIn;
          _loginUrl = result.loginUrl == null
              ? null
              : Uri.parse(result.loginUrl!);
          if (_loginUrl == null) _error = "Moodle didn't send a login page.";
        }
      });
    } on Exception catch (error) {
      if (!mounted) return;
      setState(() {
        // At launch, a server problem shouldn't lock people out of the
        // calendar, which shows its own error. When they asked to sign in,
        // tell them why it can't happen.
        if (atLaunch) {
          _stage = _Stage.home;
        } else {
          _stage = _Stage.signIn;
          _loginUrl = null;
          _error = error is MoodleApiException
              ? error.message
              : "Couldn't check your Moodle sign-in.";
        }
      });
    }
  }

  void _onMoodleChanged() {
    if (widget.moodleService.signedIn) {
      if (_stage != _Stage.home) setState(() => _stage = _Stage.home);
    } else {
      // Signed out: get a fresh login page.
      _check(atLaunch: false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return switch (_stage) {
      _Stage.checking => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      _Stage.signIn => SignInScreen(
        moodleService: widget.moodleService,
        loginUrl: _loginUrl,
        error: _error,
        onRetry: () => _check(atLaunch: false),
        onSkip: () => setState(() => _stage = _Stage.home),
      ),
      _Stage.home => widget.homeBuilder(
        context,
        () => _check(atLaunch: false),
      ),
    };
  }
}
