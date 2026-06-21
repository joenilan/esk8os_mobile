import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../ble/esk8os_ble.dart';

class WifiService {
  static const String baseUrl = Esk8WifiExport.baseUrl;

  /// Fetch the log index from the board. Returns a list of filenames.
  static Future<List<String>> fetchLogIndex() async {
    try {
      final response = await http.get(Uri.parse('$baseUrl/')).timeout(
            const Duration(seconds: 10),
          );
      if (response.statusCode == 200) {
        // Typical ESPAsyncWebServer directory listing parses easily via regex for hrefs.
        try {
          final List<dynamic> data = jsonDecode(response.body);
          return data.map((e) => e.toString()).toList();
        } catch (_) {
          // Fallback: parse HTML hrefs for .csv files
          final hrefRegex = RegExp(r'href="([^"]+\.csv)"');
          final matches = hrefRegex.allMatches(response.body);
          return matches.map((m) => m.group(1)!).toList();
        }
      }
      throw Exception('Server returned ${response.statusCode}');
    } catch (e) {
      throw Exception('Failed to connect to board WiFi: $e');
    }
  }

  /// Download a specific log file and save it to the device's downloads or docs dir.
  static Future<File> downloadLog(String filename) async {
    final response = await http.get(Uri.parse('$baseUrl/dl?f=$filename')).timeout(
          const Duration(seconds: 30), // Logs might be large
        );

    if (response.statusCode == 200) {
      Directory dir;
      if (Platform.isAndroid) {
        dir = (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
      } else {
        dir = await getApplicationDocumentsDirectory();
      }
      // Simple path join to avoid adding 'path' dependency if not strictly needed
      final sep = Platform.pathSeparator;
      final file = File('${dir.path}$sep$filename');
      await file.writeAsBytes(response.bodyBytes);
      return file;
    }
    throw Exception('Failed to download log: ${response.statusCode}');
  }

  /// Upload a new firmware .bin file for OTA.
  static Future<void> uploadOta(File binFile) async {
    final request = http.MultipartRequest('POST', Uri.parse('$baseUrl/update'));
    request.files.add(await http.MultipartFile.fromPath('update', binFile.path));
    
    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception('OTA failed: ${response.body}');
    }
  }
}
