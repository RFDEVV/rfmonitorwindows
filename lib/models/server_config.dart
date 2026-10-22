class ServerConfig {
  final String id; // stable local id, independent of name/url edits
  final String name; // user-friendly label shown in the Server tab
  final String baseUrl; // e.g. https://monitor.domainku.com
  final String localBaseUrl;
  final String tailscaleBaseUrl;
  final String apiKey;
  final double idleWatt;
  final double maxExtraWatt;
  final double tariffPerKwh; // Rp per kWh
  final double monthlyInternetCostRp;

  const ServerConfig({
    required this.id,
    required this.baseUrl,
    required this.apiKey,
    this.localBaseUrl = '',
    this.tailscaleBaseUrl = '',
    this.name = '',
    this.idleWatt = 30,
    this.maxExtraWatt = 90,
    this.tariffPerKwh = 1445,
    this.monthlyInternetCostRp = 0,
  });

  String get wsUrl => baseUrl.replaceFirst('https://', 'wss://').replaceFirst('http://', 'ws://');

  String get localHost => Uri.tryParse(localBaseUrl)?.host ?? '';

  String get tailscaleHost => Uri.tryParse(tailscaleBaseUrl)?.host ?? '';

  /// Falls back to the host portion of the URL when the user hasn't set a
  /// friendly name, so the Server list is never left blank.
  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    try {
      final uri = Uri.parse(baseUrl);
      return uri.host.isNotEmpty ? uri.host : baseUrl;
    } catch (_) {
      return baseUrl;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'baseUrl': baseUrl,
        'localBaseUrl': localBaseUrl,
        'tailscaleBaseUrl': tailscaleBaseUrl,
        'apiKey': apiKey,
        'idleWatt': idleWatt,
        'maxExtraWatt': maxExtraWatt,
        'tariffPerKwh': tariffPerKwh,
        'monthlyInternetCostRp': monthlyInternetCostRp,
      };

  factory ServerConfig.fromJson(Map<String, dynamic> json) => ServerConfig(
        id: json['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
        name: json['name'] ?? '',
        baseUrl: json['baseUrl'] ?? '',
        localBaseUrl: json['localBaseUrl'] ?? '',
        tailscaleBaseUrl: json['tailscaleBaseUrl'] ?? '',
        apiKey: json['apiKey'] ?? '',
        idleWatt: (json['idleWatt'] ?? 30).toDouble(),
        maxExtraWatt: (json['maxExtraWatt'] ?? 90).toDouble(),
        tariffPerKwh: (json['tariffPerKwh'] ?? 1445).toDouble(),
        monthlyInternetCostRp: (json['monthlyInternetCostRp'] ?? 0).toDouble(),
      );

  ServerConfig copyWith({
    String? id,
    String? name,
    String? baseUrl,
    String? localBaseUrl,
    String? tailscaleBaseUrl,
    String? apiKey,
    double? idleWatt,
    double? maxExtraWatt,
    double? tariffPerKwh,
    double? monthlyInternetCostRp,
  }) {
    return ServerConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      baseUrl: baseUrl ?? this.baseUrl,
      localBaseUrl: localBaseUrl ?? this.localBaseUrl,
      tailscaleBaseUrl: tailscaleBaseUrl ?? this.tailscaleBaseUrl,
      apiKey: apiKey ?? this.apiKey,
      idleWatt: idleWatt ?? this.idleWatt,
      maxExtraWatt: maxExtraWatt ?? this.maxExtraWatt,
      tariffPerKwh: tariffPerKwh ?? this.tariffPerKwh,
      monthlyInternetCostRp: monthlyInternetCostRp ?? this.monthlyInternetCostRp,
    );
  }
}
