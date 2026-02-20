class ApiConnectionTestResult {
  final bool success;
  final String message;

  const ApiConnectionTestResult({required this.success, required this.message});

  factory ApiConnectionTestResult.ok([String message = '接続成功']) {
    return ApiConnectionTestResult(success: true, message: message);
  }

  factory ApiConnectionTestResult.ng(String message) {
    return ApiConnectionTestResult(success: false, message: message);
  }
}
