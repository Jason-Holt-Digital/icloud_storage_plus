import 'dart:async';
import 'package:flutter/material.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';
import 'utils.dart';

class Upload extends StatefulWidget {
  final String containerId;

  const Upload({super.key, required this.containerId});

  @override
  State<Upload> createState() => _UploadState();
}

class _UploadState extends State<Upload> {
  final _containerIdController = TextEditingController();
  final _filePathController = TextEditingController();
  final _destPathController = TextEditingController();
  StreamSubscription<ICloudTransferProgress>? _progressListener;
  String? _error;
  String? _progress;

  Future<void> _handleUpload() async {
    try {
      setState(() {
        _progress = 'Upload Started';
        _error = null;
      });

      await ICloudStorage.uploadFile(
        containerId: _containerIdController.text,
        localPath: _filePathController.text,
        relativePath: _destPathController.text,
        onProgress: (stream) {
          _progressListener = stream.listen(
            (event) {
              setState(() {
                switch (event.type) {
                  case ICloudTransferProgressType.progress:
                    _error = null;
                    _progress =
                        'Upload Progress: ${formatProgressPercent(event.percent)}';
                  case ICloudTransferProgressType.done:
                    _error = null;
                    _progress = 'Upload Completed';
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
    _filePathController.dispose();
    _destPathController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('upload example'),
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
                controller: _filePathController,
                decoration: const InputDecoration(
                  labelText: 'filePath',
                ),
              ),
              TextField(
                controller: _destPathController,
                decoration: const InputDecoration(
                  labelText: 'relativePath',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _handleUpload,
                child: const Text('UPLOAD'),
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
