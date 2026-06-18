class SourceReference {
  final String sourceId;
  final String stableId;
  final String sourceType;
  final String? path;

  const SourceReference({
    required this.sourceId,
    required this.stableId,
    required this.sourceType,
    this.path,
  });
}
