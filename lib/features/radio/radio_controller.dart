import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../controllers/player_controller.dart';
import '../../core/json_store.dart';
import '../../models/radio_station.dart';
import '../../models/track.dart';
import 'radio_client.dart';

class RadioController extends ChangeNotifier {
  RadioController({
    required PlayerController player,
    RadioClient? client,
    JsonStore? store,
  })  : _player = player,
        _client = client ?? RadioClient(),
        _store = store ?? JsonStore('radio.json') {
    unawaited(_restore());
  }

  final PlayerController _player;
  final RadioClient _client;
  final JsonStore _store;

  List<RadioStation> _stations = <RadioStation>[];
  List<RadioStation> _favorites = <RadioStation>[];
  List<MapEntry<String, String>> _countries = <MapEntry<String, String>>[];
  bool _loading = false;
  bool _loadingCountries = false;
  String? _error;
  String _query = '';
  String? _country;
  bool _favoritesOnly = false;

  List<RadioStation> get stations =>
      List<RadioStation>.unmodifiable(_stations);
  List<RadioStation> get favorites =>
      List<RadioStation>.unmodifiable(_favorites);
  List<MapEntry<String, String>> get countries =>
      List<MapEntry<String, String>>.unmodifiable(_countries);
  bool get loading => _loading;
  bool get loadingCountries => _loadingCountries;
  String? get error => _error;
  String get query => _query;
  String? get country => _country;
  bool get favoritesOnly => _favoritesOnly;
  bool get isEmpty => _stations.isEmpty;

  List<RadioStation> get visible =>
      _favoritesOnly ? favorites : stations;

  Future<void> _restore() async {
    final Map<String, dynamic> data = await _store.read();
    final List<dynamic> raw = data['favorites'] as List<dynamic>? ?? <dynamic>[];
    _favorites = raw
        .whereType<Map<String, dynamic>>()
        .map(RadioStation.fromJson)
        .toList();
    notifyListeners();
    await loadTop();
  }

  Future<void> loadTop() async {
    if (_loading) return;
    _loading = true;
    _error = null;
    _favoritesOnly = false;
    _country = null;
    notifyListeners();
    try {
      _stations = await _client.topHits(limit: 100);
      if (_stations.isEmpty) _error = '没有取到电台列表';
    } on RadioException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '加载失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> search(String keyword) async {
    final String kw = keyword.trim();
    if (kw.isEmpty) {
      await loadTop();
      return;
    }
    _query = kw;
    _loading = true;
    _error = null;
    _favoritesOnly = false;
    _country = null;
    notifyListeners();
    try {
      _stations = await _client.search(kw, limit: 60);
      if (_stations.isEmpty) _error = '没找到匹配的电台';
    } on RadioException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '搜索失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> ensureCountries() async {
    if (_countries.isNotEmpty || _loadingCountries) return;
    _loadingCountries = true;
    notifyListeners();
    _countries = await _client.countries();
    _loadingCountries = false;
    notifyListeners();
  }

  Future<void> filterByCountry(String? code) async {
    if (code == null || code.isEmpty) {
      await loadTop();
      return;
    }
    _country = code;
    _loading = true;
    _error = null;
    _favoritesOnly = false;
    _query = '';
    notifyListeners();
    try {
      _stations = await _client.byCountry(code, limit: 80);
      if (_stations.isEmpty) _error = '该国家暂无可用电台';
    } on RadioException catch (e) {
      _error = e.message;
    } catch (e) {
      _error = '加载失败：$e';
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  void showFavorites() {
    _favoritesOnly = true;
    notifyListeners();
  }

  bool isFavorite(String uuid) =>
      _favorites.any((RadioStation s) => s.uuid == uuid);

  Future<void> toggleFavorite(RadioStation station) async {
    if (isFavorite(station.uuid)) {
      _favorites =
          _favorites.where((RadioStation s) => s.uuid != station.uuid).toList();
    } else {
      _favorites = <RadioStation>[..._favorites, station];
    }
    notifyListeners();
    await _persist();
  }

  Future<void> play(RadioStation station) async {
    final List<RadioStation> source = visible;
    final int index = source.indexWhere((RadioStation s) => s.uuid == station.uuid);
    final List<Track> queue = <Track>[
      for (final RadioStation s in source) s.toTrack(),
    ];
    if (queue.isEmpty) return;
    await _player.playAll(queue, at: index < 0 ? 0 : index);
  }

  Future<void> _persist() async {
    await _store.write(<String, dynamic>{
      'favorites': _favorites
          .map((RadioStation s) => <String, dynamic>{
                'stationuuid': s.uuid,
                'name': s.name,
                'url_resolved': s.url,
                'favicon': s.favicon,
                'country': s.country,
                'countrycode': s.countryCode,
                'tags': s.tags,
                'codec': s.codec,
                'bitrate': s.bitrate,
              })
          .toList(),
    });
  }
}
