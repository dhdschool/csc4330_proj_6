class LoginResponse {
  final bool success;

  const LoginResponse({
    required this.success
  });

  factory fromJson(Map<String, dynamic> json) => LoginResponse(
    success: json['success'] as bool
  );
}

class IsAuthorizedResponse{
  final bool authorized; 
  final String? loginUrl;

  const IsAuthorizedResponse({
    required this.authorized,
    this.loginUrl 
  });

  factory fromJson(Map<String, dynamic> json) => IsAuthorizedResponse(
    authorized: json['authorized'] as bool,
    loginUrl: json.containsKey('login_url') ? json['login_url'] : null
  );
}