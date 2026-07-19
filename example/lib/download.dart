import 'dart:async';
import 'package:flutter/material.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'utils.dart';

class Download extends StatefulWidget {
  final String containerId;

  const Download({super.key, required this.containerId});

  @override
  State<Download> createState() => _DownloadState();
}

class _DownloadState extends State<Download> {
  final _containerIdController = TextEditingController();
  final _cloudPathController = TextEditingController();
  final _localPathController = TextEditingController();
  StreamSubscription<ICloudTransferProgress>? _progressListener;
  String? _error;
  String? _progress;

  Future<void> _handleDownload() async {
    try {
      setState(() {
        _progress = 'Download Started';
        _error = null;
      });

      await ICloudStorage.downloadFile(
        containerId: _containerIdController.text,
        relativePath: _cloudPathController.text,
        localPath: _localPathController.text,
        onProgress: (stream) {
          _progressListener = stream.listen(
            (event) {
              setState(() {
                switch (event.type) {
                  case ICloudTransferProgressType.progress:
                    _error = null;
                    _progress =
                        'Download Progress: ${formatProgressPercent(event.percent)}';
                  case ICloudTransferProgressType.done:
                    _error = null;
                    _progress = 'Download Completed';
                }
              });
            },
            onError: (Object error) {
              setState(() {
                _progress = null;
                _error = getErrorMessage(error);
              });
            },
          );
        },
      );
    } catch (ex) {
      setState(() {
        _progress = null;
        _error = getErrorMessage(ex);
      });
    }
  }

  @override
  void initState() {
    _containerIdController.text = widget.containerId;
    super.initState();
  }

  @override
  void dispose() {
    _progressListener?.cancel();
    _containerIdController.dispose();
    _cloudPathController.dispose();
    _localPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('download example'),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              TextField(
                controller: _containerIdController,
                decoration: const InputDecoration(
                  labelText: 'containerId',
                ),
              ),
              TextField(
                controller: _cloudPathController,
                decoration: const InputDecoration(
                  labelText: 'relativePath',
                ),
              ),
              TextField(
                controller: _localPathController,
                decoration: const InputDecoration(
                  labelText: 'localPath',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _handleDownload,
                child: const Text('DOWNLOAD'),
              ),
              const SizedBox(height: 16),
              if (_error != null)
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                ),
              if (_progress != null)
                Text(
                  _progress!,
                  style: TextStyle(color: Theme.of(context).primaryColor),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
