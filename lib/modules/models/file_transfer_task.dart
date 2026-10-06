enum TransferStatus { pending, transferring, completed, failed, cancelled }

class FileTransferTask {
  final String id;
  final String fileName;
  String filePath;
  final int fileSize;
  int transferredBytes;
  final bool isUpload;
  final String peerId;
  final String peerName;
  final String peerIp;
  final String? groupId;
  final String? attachmentBatchId;
  double speedBytesPerSec;
  TransferStatus status;
  String? errorMessage;
  DateTime startTime;

  FileTransferTask({
    required this.id,
    required this.fileName,
    required this.filePath,
    required this.fileSize,
    this.transferredBytes = 0,
    required this.isUpload,
    required this.peerId,
    required this.peerName,
    required this.peerIp,
    this.groupId,
    this.attachmentBatchId,
    this.speedBytesPerSec = 0,
    this.status = TransferStatus.pending,
    this.errorMessage,
    DateTime? startTime,
  }) : startTime = startTime ?? DateTime.now();

  double get progress {
    if (fileSize <= 0) return 0.0;
    return (transferredBytes / fileSize).clamp(0.0, 1.0);
  }

  String get formattedSpeed {
    if (speedBytesPerSec < 1024) {
      return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
    }
    if (speedBytesPerSec < 1024 * 1024) {
      return '${(speedBytesPerSec / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(speedBytesPerSec / (1024 * 1024)).toStringAsFixed(1)} MB/s';
  }

  String get formattedFileSize {
    if (fileSize < 1024) return '$fileSize B';
    if (fileSize < 1024 * 1024) {
      return '${(fileSize / 1024).toStringAsFixed(1)} KB';
    }
    if (fileSize < 1024 * 1024 * 1024) {
      return '${(fileSize / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(fileSize / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
