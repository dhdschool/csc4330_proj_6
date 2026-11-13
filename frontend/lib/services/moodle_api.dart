import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:webview_cookie_manager_flutter/webview_cookie_manager.dart';

import "../models/moodle_event.dart";

class MoodleApiException implements Exception {
  MoodleApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

class MoodleService extends ChangeNotifier {
  final http.Client client; 
  final String baseUrl;

  MoodleService({
    required this.client,
    required this.baseUrl   
  });

  final WebviewCookieManager _cookieManager = WebviewCookieManager();
  String _sessionToken = "";


  Future<void> handleUrlChange({required String? url}) async {
    List<Cookie> cookies = await _cookieManager.getCookies(url);
    for (Cookie cookie in cookies){
      if(cookie.name == "MoodleSessionlsumoodle4" && cookie.value != _sessionToken){
        // New session token found
        _sessionToken = cookie.value;
        await dispatchSessionToken();
        break;
      }
    }
  }

  Future<LoginResponse> dispatchSessionToken() async {
    final http.Response response;

    try{
      response = await client.post(
        Uri.parse('$baseUrl/api/moodle/login'),
        headers: <String, String>{
          'Content-Type': 'application/json',
        },
        body: jsonEncode(<String, dynamic>{
          'token': _sessionToken,
          'backend_login': kIsWeb
        })
      );
    } on Exception {
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode == 503) {
      throw MoodleApiException(
        "Moodle's api is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    final loginResponse =  LoginResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
    );

    if (loginResponse.success){
      notifyListeners();
    }

    return loginResponse;
  }

  Future<IsAuthorizedResponse> isAuthorized() async {
    final http.Response response;

    try {
      response = await client.get(Uri.parse('$baseUrl/api/moodle/authorized'));
    } catch (e) { 
      throw MoodleApiException(
        "Couldn't reach the calendar server at $baseUrl.",
      );
    }
    if (response.statusCode == 503) {
      throw MoodleApiException(
        "Moodle's api is unavailable right now. Try again in a few minutes.",
      );
    }
    if (response.statusCode != 200) {
      throw MoodleApiException(
        'The calendar server returned an error (${response.statusCode}).',
      );
    }
    return IsAuthorizedResponse.fromJson(
      jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic> 
    );
  }
} 
