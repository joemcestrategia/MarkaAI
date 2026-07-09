import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:permission_handler/permission_handler.dart';

class UpdateInfo {
  final String versionName;
  final int versionCode;
  final String apkUrl;
  final String? changelog;
  final bool forceUpdate;

  UpdateInfo({
    required this.versionName,
    required this.versionCode,
    required this.apkUrl,
    this.changelog,
    required this.forceUpdate,
  });

  factory UpdateInfo.fromJson(Map<String, dynamic> json) {
    return UpdateInfo(
      versionName: json['version_name'],
      versionCode: json['version_code'],
      apkUrl: json['apk_url'],
      changelog: json['changelog'],
      forceUpdate: json['force_update'] ?? false,
    );
  }
}

class UpdateService {
  static Future<UpdateInfo?> checkForUpdate() async {
    try {
      if (!Platform.isAndroid) return null;

      final packageInfo = await PackageInfo.fromPlatform();
      // O buildNumber no pubspec (ex: 1.4.0+14) vem aqui como '14'
      final int currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      final response = await Supabase.instance.client
          .from('app_versions')
          .select()
          .eq('platform', 'android')
          .order('version_code', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      final remoteUpdate = UpdateInfo.fromJson(response);

      if (remoteUpdate.versionCode > currentBuildNumber) {
        return remoteUpdate;
      }

      return null;
    } catch (e) {
      debugPrint("UpdateService: Erro ao checar atualização: $e");
      return null;
    }
  }

  static Future<void> checkForUpdateAndPrompt(BuildContext context) async {
    try {
      final updateInfo = await checkForUpdate();
      if (updateInfo == null) return;
      
      if (!context.mounted) return;

      showDialog(
        context: context,
        barrierDismissible: !updateInfo.forceUpdate,
        builder: (dialogContext) {
          return AlertDialog(
            title: Text("Nova atualização disponível: ${updateInfo.versionName}"),
            content: SingleChildScrollView(
              child: Text(updateInfo.changelog ?? "Nova versão do aplicativo disponível."),
            ),
            actions: [
              if (!updateInfo.forceUpdate)
                TextButton(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                  },
                  child: const Text("Agora não"),
                ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _downloadAndInstall(context, updateInfo);
                },
                child: const Text("Atualizar agora"),
              ),
            ],
          );
        },
      );
    } catch (e) {
      debugPrint("UpdateService: Erro ao mostrar popup: $e");
    }
  }

  static Future<void> _downloadAndInstall(BuildContext context, UpdateInfo updateInfo) async {
    try {
      // Pedir permissão se necessário
      if (await Permission.requestInstallPackages.isDenied) {
         await Permission.requestInstallPackages.request();
      }

      final dir = await getExternalStorageDirectory();
      if (dir == null) throw Exception("Diretório não encontrado");

      final savePath = "${dir.path}/update_${updateInfo.versionCode}.apk";

      if (context.mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (progressContext) {
            return _DownloadProgressDialog(
              apkUrl: updateInfo.apkUrl,
              savePath: savePath,
              onComplete: () {
                Navigator.pop(progressContext); // fecha dialog
                OpenFilex.open(savePath); // dispara instalador
              },
              onError: (error) {
                Navigator.pop(progressContext);
                if (context.mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                     SnackBar(content: Text("Erro ao baixar atualização: $error")),
                   );
                }
              },
            );
          },
        );
      }
    } catch (e) {
      debugPrint("UpdateService: Erro no download/install: $e");
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Erro ao iniciar atualização: $e")),
        );
      }
    }
  }
}

class _DownloadProgressDialog extends StatefulWidget {
  final String apkUrl;
  final String savePath;
  final VoidCallback onComplete;
  final Function(String) onError;

  const _DownloadProgressDialog({
    required this.apkUrl,
    required this.savePath,
    required this.onComplete,
    required this.onError,
  });

  @override
  State<_DownloadProgressDialog> createState() => _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  double _progress = 0;
  final Dio _dio = Dio();
  CancelToken _cancelToken = CancelToken();

  @override
  void initState() {
    super.initState();
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    try {
      await _dio.download(
        widget.apkUrl,
        widget.savePath,
        cancelToken: _cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _progress = received / total;
            });
          }
        },
      );
      widget.onComplete();
    } catch (e) {
      if (!CancelToken.isCancel(e as DioException)) {
        widget.onError(e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text("Baixando atualização..."),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(value: _progress),
          const SizedBox(height: 16),
          Text("${(_progress * 100).toStringAsFixed(1)}%"),
        ],
      ),
    );
  }
}
