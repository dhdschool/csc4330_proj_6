import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_cookie_manager_flutter/webview_cookie_manager.dart';
import 'package:provider/provider.dart';

import '../services/moodle_api.dart';

class MoodleView extends StatefulWidget {
  final Uri loginUrl;
  
  const MoodleView({
    super.key,
    required this.loginUrl  
  });

  @override 
  State<MoodleView> createState() =>  _MoodleViewState();
}

class _MoodleViewState extends State<MoodleView>{
  late final WebViewController _controller; 

  @override
  void initState(){
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onUrlChange: (change) {
            if(change.url == null || !mounted){
              return;
            }
            
            context.read<MoodleService>().handleUrlChange(
              url: change.url
            );
          }
        )
      )
      ..loadRequest(widget.loginUrl);


    super.initState();
  }

  @override
  Widget build(BuildContext context){
    return SizedBox.expand(
      child: WebViewWidget(controller: _controller)
    );
  }

}