import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../models/moodle_event.dart';
import '../services/moodle_api.dart';

/// Runs the Moodle (LSU single sign-on) login.
///
/// On mobile it shows Moodle's login page in a webview and hands the session
/// cookie to the backend once it appears. On the web, where the app can't read
/// another site's cookies, the backend opens its own browser window for the
/// login instead.
class MoodleView extends StatefulWidget {
  final Uri loginUrl;

  const MoodleView({super.key, required this.loginUrl});

  @override
  State<MoodleView> createState() => _MoodleViewState();
}

class _MoodleViewState extends State<MoodleView> {
  late final WebViewController _controller;

  // Web only. Kept in state so a rebuild doesn't start a second login.
  Future<LoginResponse>? _webLogin;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController();

    if (kIsWeb) {
      _webLogin = context.read<MoodleService>().dispatchSessionToken();
      return;
    }
    _controller
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) async {
            if (change.url == null || !mounted) return;
            try {
              await context.read<MoodleService>().handleUrlChange(
                url: change.url,
              );
            } on MoodleApiException catch (error) {
              if (!mounted) return;
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(error.message)));
            }
          },
        ),
      )
      ..loadRequest(widget.loginUrl);
  }

  void _retryWebLogin() {
    setState(() {
      _webLogin = context.read<MoodleService>().dispatchSessionToken();
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      return SizedBox.expand(child: WebViewWidget(controller: _controller));
    }
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: FutureBuilder<LoginResponse>(
          future: _webLogin,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text(
                    'Finish signing in to Moodle in the browser window '
                    'that opened.',
                    textAlign: TextAlign.center,
                  ),
                ],
              );
            }
            // On success the app moves on by itself; this only shows briefly.
            if (snapshot.data?.success ?? false) {
              return const Text('Signed in. Loading your calendar...');
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  snapshot.hasError
                      ? '${snapshot.error}'
                      : "Moodle sign-in didn't finish.",
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _retryWebLogin,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Try again'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
