import 'dart:io';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../pages/update_page.dart';

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

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => UpdatePage(updateInfo: updateInfo),
          fullscreenDialog: true,
        ),
      );
    } catch (e) {
      debugPrint("UpdateService: Erro ao mostrar popup: $e");
    }
  }
}
