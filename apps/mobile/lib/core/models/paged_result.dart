/// A page of results plus the metadata needed to fetch the next one.
///
/// Mirrors the API's list envelope: `{"items": [...], "meta": {...}}`.
class PagedResult<T> {
  const PagedResult({
    required this.items,
    required this.page,
    required this.totalPages,
    required this.total,
  });

  final List<T> items;
  final int page;
  final int totalPages;
  final int total;

  bool get hasMore => page < totalPages;

  bool get isEmpty => items.isEmpty;

  static PagedResult<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) parse,
  ) {
    final Map<String, dynamic> meta = Map<String, dynamic>.from(
      (json['meta'] as Map<dynamic, dynamic>?) ?? <dynamic, dynamic>{},
    );
    return PagedResult<T>(
      items: ((json['items'] as List<dynamic>?) ?? const <dynamic>[])
          .map((dynamic item) =>
              parse(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
          .toList(),
      page: meta['page'] as int? ?? 1,
      totalPages: meta['total_pages'] as int? ?? 1,
      total: meta['total'] as int? ?? 0,
    );
  }
}
