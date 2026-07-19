import 'dart:async';
import 'package:flutter/material.dart';
import 'package:icloud_storage_example/utils.dart';
import 'package:icloud_storage_plus/icloud_storage.dart';

/// Gather example widget.
class Gather extends StatefulWidget {
  /// Create a new [Gather] widget.
  const Gather({super.key});

  @override
  State<Gather> createState() => _GatherState();
}

class _GatherState extends State<Gather> {
  final _containerIdController = TextEditingController();
  StreamSubscription<GatherResult>? _updateListener;

  List<String> _files = [];
  String? _error;
  String _status = '';

  Future<void> _handleGather() async {
    setState(() {
      _status = 'busy';
    });

    try {
      final results = await ICloudStorage.gather(
        containerId: _containerIdController.text,
        onUpdate: (stream) {
          _updateListener = stream.listen(
            (updatedResult) {
              if (!mounted) return;
              setState(() {
                _files =
                    updatedResult.files.map((e) => e.relativePath).toList();
              });
            },
            onError: (Object error) {
              if (!mounted) return;
              setState(() {
                _error = getErrorMessage(error);
                _status = '';
              });
            },
          );
        },
      );

      if (!mounted) return;
      setState(() {
        _status = 'listening';
        _error = null;
        _files = results.files.map((e) => e.relativePath).toList();
      });
    } on Exception catch (ex) {
      if (!mounted) return;
      setState(() {
        _error = getErrorMessage(ex);
        _status = '';
      });
    }
  }

  Future<void> _cancel() async {
    await _updateListener?.cancel();
    if (!mounted) return;
    setState(() {
      _status = '';
    });
  }

  @override
  void dispose() {
    // ignore: discarded_futures, cancel returns a Future but we can't await it in dispose
    _updateListener?.cancel();
    _containerIdController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('icloud_storage example'),
        actions: [
          PopupMenuButton(
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: '/upload',
                child: Text('Upload'),
              ),
              PopupMenuItem(
                value: '/download',
                child: Text('Download'),
              ),
              PopupMenuItem(
                value: '/delete',
                child: Text('Delete'),
              ),
              PopupMenuItem(
                value: '/move',
                child: Text('Move'),
              ),
              PopupMenuItem(
                value: '/rename',
                child: Text('Rename'),
              ),
              PopupMenuItem(
                value: '/listContents',
                child: Text('List Contents'),
              ),
            ],
            onSelected: (value) => Navigator.pushNamed(
              context,
              value,
              arguments: _containerIdController.text,
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              TextField(
                controller: _containerIdController,
                decoration: const InputDecoration(
                  labelText: 'containerId',
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _status == ''
                    ? _handleGather
                    : _status == 'listening'
                        ? _cancel
                        : null,
                child: Text(
                  _status == ''
                      ? 'GATHER'
                      : _status == 'busy'
                          ? 'GATHERING'
                          : 'STOP LISTENING TO UPDATE',
                ),
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: _files.length + (_error != null ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (_error != null) {
                      if (index == 0) {
                        return Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                          ),
                        );
                      }
                    }
                    final fileIndex = _error != null ? index - 1 : index;
                    final file = _files[fileIndex];
                    return Padding(
                      padding: const EdgeInsets.all(8),
                      child: SelectableText(file),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
