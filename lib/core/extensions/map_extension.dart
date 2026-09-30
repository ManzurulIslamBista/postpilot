extension MapExtension<K, V> on Map<K, V> {
  void removeKeys(Iterable<K> keys) => keys.forEach(remove);
}

extension KeyValueListExtension on List<({String key, String value, bool enabled})> {
  Map<String, String> get enabledMap => {
        for (final item in this)
          if (item.enabled && item.key.isNotEmpty) item.key: item.value,
      };
}
