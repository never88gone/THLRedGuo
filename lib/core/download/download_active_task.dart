import 'dart:io';

import 'package:http/http.dart' as http;

/// 活跃下载任务网络连接与文件句柄管理器
class DownloadActiveTask {
  DownloadActiveTask(this.client);

  final http.Client client;
  bool isCancelled = false;
  IOSink? sink;

  void cancel() {
    isCancelled = true;
    try {
      sink?.close();
    } catch (_) {}
    client.close();
  }
}
