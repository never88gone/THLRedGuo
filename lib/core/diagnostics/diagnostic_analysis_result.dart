/// 诊断分析结果对象，包含清晰分类、具体失败原因与针对性排查建议
class DiagnosticAnalysisResult {
  const DiagnosticAnalysisResult({
    required this.category,
    required this.title,
    required this.message,
    required this.advice,
    required this.code,
    this.businessCode = '',
  });

  final String category;
  final String title;
  final String message;
  final String advice;
  final String code;
  final String businessCode;
}
