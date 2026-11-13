import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:provider/provider.dart';

import '../services/moodle_api.dart';
import '../models/moodle_event.dart';

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
    _controller = WebViewController();

    if(!kIsWeb){
      _controller
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
    }
      
    super.initState();
  }

  @override
  Widget build(BuildContext context){
    return SizedBox.expand(
      child: kIsWeb 
        ? Center(child: FutureBuilder<LoginResponse>(
          future: context.read<MoodleService>().dispatchSessionToken(), 
          builder: (BuildContext context, AsyncSnapshot<LoginResponse> snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return CircularProgressIndicator();
            } else if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            } else {
              return Text('Redirecting...');
            }
          }
        ))
        : WebViewWidget(controller: _controller)
    );
  }

}