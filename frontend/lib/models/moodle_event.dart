class LoginResponse {
  final bool success;

  const LoginResponse({
    required this.success
  });

  factory fromJson(Map<String, dynamic> json) => LoginResponse(
    success: json['success'] as bool
  );
}