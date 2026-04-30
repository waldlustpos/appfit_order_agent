enum UpdateStatus {
  idle,
  checking,
  downloading,
  readyToInstall,
  installing,
  error,
}

class UpdateInfo {
  final int currentVersion;
  final int latestVersion;
  final String downloadUrl;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.downloadUrl,
  });

  bool get hasUpdate => latestVersion > currentVersion;
}
