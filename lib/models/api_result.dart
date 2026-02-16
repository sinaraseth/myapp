class ApiResult {
  final bool success;
  final dynamic data;
  final String? error;
  final int statusCode;

  ApiResult({
    required this.success,
    this.data,
    this.error,
    required this.statusCode,
  });

  Map<String, dynamic> toJson() => {
    'success': success,
    'data': data,
    'error': error,
    'status_code': statusCode,
  };
}
