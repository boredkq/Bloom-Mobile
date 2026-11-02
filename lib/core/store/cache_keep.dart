/// How long a cache lives: `days` is the limit, `null` means no limit of its own.
enum CacheKeep {
  never('never', null),
  restart('restart', null),
  day('24h', 1),
  days3('3d', 3),
  week('1w', 7),
  month('1m', 30);

  const CacheKeep(this.id, this.days);

  final String id;
  final int? days;

  static CacheKeep of(Object? id) =>
      values.firstWhere((k) => k.id == id, orElse: () => never);
}
