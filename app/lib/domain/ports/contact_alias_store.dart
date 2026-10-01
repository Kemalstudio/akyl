abstract interface class ContactAliasStore {
  Future<Map<String, String>> load();
  Future<void> save(Map<String, String> aliases);
}
