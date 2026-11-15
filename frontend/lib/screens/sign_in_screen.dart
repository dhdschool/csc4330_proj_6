import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/moodle_api.dart';
import '../theme.dart';
import 'moodle_view.dart';

/// The first screen for anyone not signed in to Moodle. Signing in adds their
/// course deadlines to the calendar; they can also skip and use the LSU
/// calendar alone.
class SignInScreen extends StatefulWidget {
  const SignInScreen({
    super.key,
    required this.moodleService,
    required this.loginUrl,
    required this.onSkip,
    this.error,
    this.onRetry,
  });

  final MoodleService moodleService;

  /// Moodle's login page. Null when the server couldn't be reached, in which
  /// case [error] explains why and [onRetry] checks again.
  final Uri? loginUrl;
  final VoidCallback onSkip;
  final String? error;
  final VoidCallback? onRetry;

  @override
  State<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends State<SignInScreen> {
  bool _showLogin = false;

  @override
  Widget build(BuildContext context) {
    final loginUrl = widget.loginUrl;
    if (_showLogin && loginUrl != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('SIGN IN TO MOODLE'),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => setState(() => _showLogin = false),
          ),
        ),
        // Once the login succeeds, MoodleService notifies the AuthGate,
        // which swaps this screen for the calendar.
        body: ChangeNotifierProvider.value(
          value: widget.moodleService,
          child: MoodleView(loginUrl: loginUrl),
        ),
      );
    }

    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'LSU CALENDAR',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      color: lsuPurple,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Sign in with your LSU Moodle account to see your '
                    'assignment due dates and class sessions alongside the '
                    'academic calendar.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 32),
                  if (widget.error != null) ...[
                    Text(
                      widget.error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (loginUrl != null)
                    FilledButton.icon(
                      onPressed: () => setState(() => _showLogin = true),
                      icon: const Icon(Icons.login),
                      label: const Text('Sign in with Moodle'),
                    )
                  else if (widget.onRetry != null)
                    FilledButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: widget.onSkip,
                    child: const Text('Continue without signing in'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
