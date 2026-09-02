import 'dart:async';
import 'dart:developer';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
// import 'package:flutter_app_installer/flutter_app_installer.dart';
import 'package:flutter_qjs/quickjs/ffi.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:mangayomi/providers/l10n_providers.dart';
import 'package:mangayomi/utils/platform_utils.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

class DownloadFileScreen extends ConsumerStatefulWidget {
  final (String, String, String, List<dynamic>) updateAvailable;
  const DownloadFileScreen({required this.updateAvailable, super.key});

  @override
  ConsumerState<DownloadFileScreen> createState() => _DownloadFileScreenState();
}

class _DownloadFileScreenState extends ConsumerState<DownloadFileScreen> {
  int _total = 0;
  int _received = 0;
  http.StreamedResponse? _response;
  final List<int> _bytes = [];
  StreamSubscription<List<int>>? _subscription;

  /// Set when the download could not start or could not finish, so the dialog
  /// can say so and offer another go instead of sitting at 0 MB forever.
  String? _error;

  @override
  void initState() {
    super.initState();
    // Checking for an update is the only decision worth asking for, and it has
    // already been made by the time this opens. So the download starts itself
    // rather than waiting behind a second button.
    //
    // Android only: elsewhere "download" means handing the release page to a
    // browser, and throwing someone out of the app without a tap is not the
    // same favour.
    if (Platform.isAndroid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _startAndroidDownload();
      });
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  /// The release asset matching this device.
  ///
  /// Prefers an APK built for one of the device's own ABIs, then falls back to
  /// any APK in the release: a universal build still installs, and offering it
  /// beats reporting that there is no download when there plainly is one.
  Future<String?> _apkUrlForDevice() async {
    final assets = widget.updateAvailable.$4.whereType<String>().toList();
    var apks = assets.where((url) => url.endsWith('.apk')).toList();
    if (apks.isEmpty) return null;

    // A release carries both builds, and "android-tv-arm64-v8a" contains
    // "arm64-v8a", so matching on the ABI alone would happily hand a phone the
    // television build. Narrow to this device's flavour first, and only ignore
    // the split if it leaves nothing to install.
    final flavour = apks
        .where((url) => url.contains('android-tv') == isTv)
        .toList();
    if (flavour.isNotEmpty) apks = flavour;

    final androidInfo = await DeviceInfoPlugin().androidInfo;
    for (final abi in androidInfo.supportedAbis) {
      final match = apks.firstWhereOrNull((url) => url.contains(abi));
      if (match != null) return match;
    }
    return apks.first;
  }

  /// Picks the asset and downloads it, reporting anything that goes wrong.
  Future<void> _startAndroidDownload() async {
    if (_total > 0 || _error != null) return;
    try {
      final url = await _apkUrlForDevice();
      if (url == null) {
        if (mounted) {
          setState(() => _error = 'No APK in this release for this device.');
        }
        return;
      }
      await _downloadApk(url);
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = l10nLocalizations(context)!;
    final updateAvailable = widget.updateAvailable;
    return AlertDialog(
      title: Text(l10n.new_update_available),
      content: SingleChildScrollView(
        child: Column(
          children: [
            Text(
              "${l10n.app_version(updateAvailable.$1)}\n\n${updateAvailable.$2}",
            ),
          ],
        ),
      ),
      actions: [
        Column(
          children: [
            _total > 0
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      Flexible(
                        child: LinearProgressIndicator(
                          value: _total > 0 ? (_received * 1.0) / _total : 0.0,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          '${(_received / 1048576.0).toStringAsFixed(2)}/${(_total / 1048576.0).toStringAsFixed(2)} MB',
                        ),
                      ),
                    ],
                  )
                : SizedBox.shrink(),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () async {
                    try {
                      await _subscription?.cancel();
                    } catch (_) {}
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  child: Text(l10n.cancel),
                ),
                const SizedBox(width: 15),
                // The button stays where it has always been. On Android the
                // download is already running by the time this is on screen,
                // so it sits disabled and the progress bar above it does the
                // talking; it comes back to life only if the download failed
                // and there is something to try again.
                ElevatedButton(
                  onPressed: !Platform.isAndroid
                      ? () => _launchInBrowser(Uri.parse(updateAvailable.$3))
                      : _error == null
                      ? null
                      : () {
                          setState(() => _error = null);
                          _startAndroidDownload();
                        },
                  child: Text(
                    Platform.isAndroid && _error != null
                        ? l10n.retry
                        : l10n.download,
                  ),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _downloadApk(String url) async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      await Permission.storage.request();
    }
    Directory? dir = Directory('/storage/emulated/0/Download');
    if (!await dir.exists()) dir = await getExternalStorageDirectory();
    final file = File(
      '${dir!.path}/${url.split("/").lastOrNull ?? "AvePlay.apk"}',
    );
    if (await file.exists()) {
      await _installApk(file);
      if (mounted) {
        Navigator.pop(context);
      }
      return;
    }
    _response = await http.Client().send(http.Request('GET', Uri.parse(url)));
    if (_response!.statusCode != 200) {
      throw HttpException('Download failed (${_response!.statusCode})');
    }
    _total = _response?.contentLength ?? 0;
    _subscription = _response?.stream.listen(
      (value) {
        if (!mounted) return;
        setState(() {
          _bytes.addAll(value);
          _received += value.length;
        });
      },
      // Without this a dropped connection leaves the bar stopped part way
      // with nothing said and no way on.
      onError: (Object e) {
        if (mounted) setState(() => _error = '$e');
      },
      cancelOnError: true,
    );
    _subscription?.onDone(() async {
      if (_error != null) return;
      await file.writeAsBytes(_bytes);
      await _installApk(file);
      if (mounted) {
        Navigator.pop(context);
      }
    });
  }

  Future<void> _installApk(File file) async {
    var status = await Permission.requestInstallPackages.status;
    if (!status.isGranted) {
      await Permission.requestInstallPackages.request();
    }
    await ApkInstaller.installApk(file.path);
  }

  Future<void> _launchInBrowser(Uri url) async {
    if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
      throw 'Could not launch $url';
    }
  }
}

class ApkInstaller {
  static const _platform = MethodChannel('com.kodjodevf.mangayomi.apk_install');
  static Future<void> installApk(String filePath) async {
    try {
      await _platform.invokeMethod('installApk', {'filePath': filePath});
    } catch (e) {
      if (kDebugMode) {
        log("Erreur d'installation : $e");
      }
    }
  }
}
