import 'dart:convert';
import 'dart:io';

import 'package:dartssh2/dartssh2.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../models/server_config.dart';
import '../services/ssh_store.dart';
import '../theme/app_theme.dart';

class FileManagerScreen extends StatefulWidget {
  final ServerConfig config;

  const FileManagerScreen({super.key, required this.config});

  @override
  State<FileManagerScreen> createState() => _FileManagerScreenState();
}

class _RemoteEntry {
  final String name;
  final String path;
  final SftpFileAttrs attrs;

  const _RemoteEntry(this.name, this.path, this.attrs);
}

class _RemoteCommandResult {
  final Uint8List output;
  final int? exitCode;

  const _RemoteCommandResult(this.output, this.exitCode);
}

class _FileManagerScreenState extends State<FileManagerScreen> {
  static const _hiddenRootEntries = {'boot', 'proc', 'sys', 'dev', 'run'};
  static const _readOnlyRootEntries = {
    'etc',
    'usr',
    'bin',
    'sbin',
    'lib',
    'lib64',
    'boot',
    'proc',
    'sys',
    'dev',
    'run',
  };
  static const _textExtensions = {
    'txt',
    'log',
    'conf',
    'ini',
    'env',
    'md',
    'json',
    'yaml',
    'yml',
    'toml',
    'xml',
    'html',
    'css',
    'js',
    'mjs',
    'cjs',
    'ts',
    'tsx',
    'jsx',
    'py',
    'sh',
    'bash',
    'php',
    'java',
    'kt',
    'dart',
    'sql',
    'go',
    'rs',
    'c',
    'h',
    'cpp',
    'properties',
    'csv',
    'service',
    'timer',
  };
  static const _imageExtensions = {'png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'};
  static const _videoExtensions = {'mp4', 'm4v', 'mov', 'webm', 'mkv'};

  final _sshStore = SshStore();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _searchController = TextEditingController();
  SSHClient? _client;
  SftpClient? _sftp;
  SshProfile? _profile;
  List<_RemoteEntry> _entries = [];
  _RemoteEntry? _clipboardEntry;
  bool _clipboardIsCut = false;
  bool _loading = false;
  bool _busy = false;
  String? _error;
  String _currentPath = '/';
  bool _searchOpen = false;
  String? _transferLabel;
  int _transferTotalBytes = 0;
  int _transferredBytes = 0;
  int _lastProgressPaint = 0;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _client?.close();
    _usernameController.dispose();
    _passwordController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await _sshStore.loadProfile();
      if (!mounted) return;
      _profile = profile;
      if (profile != null) {
        _usernameController.text = profile.username;
        _passwordController.text = profile.password;
        if (profile.username.isNotEmpty &&
            (profile.password.isNotEmpty || profile.privateKey.isNotEmpty)) {
          await _connect();
          return;
        }
        setState(() {});
      }
    } catch (error) {
      if (mounted) {
        setState(
            () => _error = 'Gagal membaca kredensial SSH tersimpan: $error');
      }
    }
  }

  List<String> get _privateRouteHosts => <String>{
        widget.config.localHost.trim(),
        widget.config.tailscaleHost.trim(),
      }.where((host) => host.isNotEmpty).toList();

  bool _isPrivateAddress(InternetAddress address) {
    final bytes = address.address.split('%').first;
    if (address.type == InternetAddressType.IPv4) {
      final octets = bytes.split('.').map(int.tryParse).toList();
      if (octets.length != 4 || octets.any((part) => part == null)) {
        return false;
      }
      final a = octets[0]!;
      final b = octets[1]!;
      return a == 10 ||
          (a == 172 && b >= 16 && b <= 31) ||
          (a == 192 && b == 168) ||
          (a == 100 && b >= 64 && b <= 127);
    }
    if (address.type == InternetAddressType.IPv6) {
      final raw = address.rawAddress;
      return raw.isNotEmpty && (raw[0] & 0xfe) == 0xfc;
    }
    return false;
  }

  Future<bool> _verifyHostKey(
    String host,
    int port,
    Uint8List fingerprint,
  ) async {
    final hex = fingerprint
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join(':');
    final known = await _sshStore.knownFingerprint(host, port);
    if (known == hex) return true;
    if (!mounted) return false;
    final trusted = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.bgBottom,
            title: Text(
              known == null ? 'Percayai server SFTP?' : 'Kunci server berubah',
              style: const TextStyle(color: AppColors.textPrimary),
            ),
            content: SelectableText(
              '$host:$port\n\nFingerprint: $hex',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Percayai'),
              ),
            ],
          ),
        ) ??
        false;
    if (trusted) await _sshStore.trustFingerprint(host, port, hex);
    return trusted;
  }

  Future<void> _connect() async {
    if (_busy) return;
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final profile = _profile;
    final port = profile?.port ?? 22;
    if (username.isEmpty) {
      setState(() => _error = 'Username SSH wajib diisi.');
      return;
    }
    if ((profile?.privateKey.isEmpty ?? true) && password.isEmpty) {
      setState(() => _error = 'Isi password atau simpan private key SSH.');
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
    });
    SSHClient? candidateClient;
    try {
      final hosts = _privateRouteHosts;
      if (hosts.isEmpty) {
        throw StateError(
          'Isi URL Local atau Tailscale di Edit Server terlebih dahulu.',
        );
      }
      Object? lastError;
      String? connectedHost;
      for (final host in hosts) {
        late final List<InternetAddress> addresses;
        try {
          addresses = await InternetAddress.lookup(host)
              .timeout(const Duration(seconds: 3));
        } catch (error) {
          lastError = error;
          continue;
        }
        final allowed = addresses.where(_isPrivateAddress);
        for (final address in allowed) {
          SSHSocket? socket;
          try {
            socket = await SSHSocket.connect(
              address.address,
              port,
              timeout: const Duration(seconds: 3),
            );
            List<SSHKeyPair>? identities;
            if (profile != null && profile.privateKey.isNotEmpty) {
              identities = SSHKeyPair.fromPem(
                profile.privateKey,
                profile.passphrase.isEmpty ? null : profile.passphrase,
              );
            }
            candidateClient = SSHClient(
              socket,
              username: username,
              identities: identities,
              onPasswordRequest: () => password,
              onVerifyHostKey: (_, fingerprint) =>
                  _verifyHostKey(host, port, fingerprint),
            );
            await candidateClient.authenticated.timeout(
              const Duration(seconds: 8),
            );
            connectedHost = host;
            break;
          } catch (error) {
            lastError = error;
            candidateClient?.close();
            candidateClient = null;
            socket?.close();
          }
        }
        if (candidateClient != null) break;
      }
      if (candidateClient == null || connectedHost == null) {
        throw lastError ??
            StateError(
              'Alamat Local/Tailscale tidak terjangkau. File Manager tidak memakai URL publik.',
            );
      }
      final sftp = await candidateClient.sftp().timeout(
            const Duration(seconds: 8),
          );
      String? credentialWarning;
      try {
        await _sshStore.saveProfile(
          SshProfile(
            host: profile?.host.isNotEmpty == true
                ? profile!.host
                : widget.config.localHost,
            port: port,
            username: username,
            password: password,
            privateKey: profile?.privateKey ?? '',
            passphrase: profile?.passphrase ?? '',
            terminalFontSize: profile?.terminalFontSize ?? 8,
          ),
          saveSecrets: true,
        );
      } catch (error) {
        credentialWarning =
            'SFTP tersambung, tetapi kredensial gagal disimpan: $error';
      }
      if (!mounted) {
        candidateClient.close();
        return;
      }
      _client?.close();
      _client = candidateClient;
      _sftp = sftp;
      _currentPath = '/';
      await _loadDirectory('/');
      if (credentialWarning != null) _showMessage(credentialWarning);
      debugPrint(
          'Connected File Manager through private SSH host $connectedHost');
    } catch (error) {
      candidateClient?.close();
      if (mounted) setState(() => _error = 'Gagal menghubungkan SFTP: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String> _safePath(String path, {bool write = false}) async {
    if (_sftp == null) throw StateError('SFTP belum tersambung.');
    if (!path.startsWith('/') || path.contains('\u0000')) {
      throw StateError('Path server tidak valid.');
    }
    final parts = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (parts.isEmpty) {
          throw StateError('Path di luar root server tidak diizinkan.');
        }
        parts.removeLast();
      } else {
        parts.add(segment);
      }
    }
    final canonical = parts.isEmpty ? '/' : '/${parts.join('/')}';
    final segments = canonical.split('/').where((part) => part.isNotEmpty);
    if (segments.any(_hiddenRootEntries.contains)) {
      throw StateError('Akses ke filesystem sistem ini dibatasi.');
    }
    if (write) {
      if (canonical == '/') {
        throw StateError('Perubahan langsung di root server dibatasi.');
      }
      if (canonical == '/var') {
        throw StateError(
          'Folder sistem /var dibatasi; pilih folder data di dalamnya.',
        );
      }
      final first = segments.isEmpty ? '' : segments.first;
      if (_readOnlyRootEntries.contains(first)) {
        throw StateError('Direktori sistem hanya dapat dilihat, tidak diubah.');
      }
    }
    return canonical;
  }

  Future<void> _loadDirectory(String path) async {
    final sftp = _sftp;
    if (sftp == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final canonical = await _safePath(path);
      final names = await sftp.listdir(canonical);
      final entries = <_RemoteEntry>[];
      for (final item in names) {
        final name = item.filename;
        if (name == '.' || name == '..' || name.isEmpty) continue;
        if (canonical == '/' && _hiddenRootEntries.contains(name)) continue;
        final childPath = _joinRemote(canonical, name);
        if (_isBlockedRemotePath(childPath)) continue;
        entries.add(_RemoteEntry(name, childPath, item.attr));
      }
      entries.sort((a, b) {
        final aDirectory = a.attrs.isDirectory;
        final bDirectory = b.attrs.isDirectory;
        if (aDirectory != bDirectory) return aDirectory ? -1 : 1;
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
      if (!mounted) return;
      setState(() {
        _currentPath = canonical;
        _entries = entries;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Gagal membaca folder: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _joinRemote(String parent, String name) =>
      parent == '/' ? '/$name' : '$parent/$name';

  bool _isBlockedRemotePath(String path) {
    final segments = path.split('/').where((part) => part.isNotEmpty).toList();
    return segments.isNotEmpty && _hiddenRootEntries.contains(segments.first);
  }

  String _parentPath(String path) {
    if (path == '/') return '/';
    final index = path.lastIndexOf('/');
    return index <= 0 ? '/' : path.substring(0, index);
  }

  String _leaf(String path) => path.substring(path.lastIndexOf('/') + 1);

  bool _isWritable(String path) {
    final segments = path.split('/').where((part) => part.isNotEmpty);
    return path != '/' &&
        path != '/var' &&
        !segments.any(_hiddenRootEntries.contains) &&
        (segments.isEmpty || !_readOnlyRootEntries.contains(segments.first));
  }

  Future<void> _openEntry(_RemoteEntry entry) async {
    try {
      final path = await _safePath(entry.path);
      if (entry.attrs.isSymbolicLink) {
        _showMessage('Membuka symbolic link tidak didukung.');
        return;
      }
      final attrs = entry.attrs;
      if (attrs.isDirectory) {
        await _loadDirectory(path);
        return;
      }
      final size = attrs.size ?? entry.attrs.size;
      final extension = _extension(entry.name);
      if (_videoExtensions.contains(extension)) {
        if ((size ?? 0) > 1024 * 1024 * 1024) {
          _showMessage('Video lebih dari 1 GB. Unduh untuk membukanya.');
          return;
        }
        final directory = await getTemporaryDirectory();
        final safeName = _safeLocalName(entry.name);
        final localFile = File(
          '${directory.path}${Platform.pathSeparator}rfmonitor_${DateTime.now().microsecondsSinceEpoch}_$safeName',
        );
        await _downloadRemoteFile(path, localFile, length: size);
        if (!mounted) return;
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _RemotePreviewPage(
              name: entry.name,
              videoFile: localFile,
              video: true,
            ),
          ),
        );
        return;
      }
      if ((size ?? 0) > 32 * 1024 * 1024) {
        _showMessage('File lebih dari 32 MB. Unduh untuk membukanya.');
        return;
      }
      final file = await _sftp!.open(path, mode: SftpFileOpenMode.read);
      late Uint8List bytes;
      try {
        bytes = await file.readBytes(length: size);
      } finally {
        await file.close();
      }
      if (!mounted) return;
      if (_imageExtensions.contains(extension)) {
        await Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => _RemotePreviewPage(
              name: entry.name,
              bytes: bytes,
              video: false,
            ),
          ),
        );
        return;
      }
      try {
        final text = utf8.decode(bytes);
        if (_textExtensions.contains(extension) || _looksLikeText(bytes)) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _RemoteTextEditorPage(
                name: entry.name,
                initialText: text,
                onSave: (value) => _writeText(path, value),
              ),
            ),
          );
          await _loadDirectory(_currentPath);
          return;
        }
      } on FormatException {
        // Non-text files remain downloadable from the file actions.
      }
      _showMessage(
          'Format file tidak didukung untuk pratinjau. Unduh file ini.');
    } catch (error) {
      _showMessage('Tidak bisa membuka file: $error');
    }
  }

  String _extension(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  bool _looksLikeText(Uint8List bytes) {
    final sample = bytes.take(4096);
    return !sample.any(
      (byte) => byte == 0 || (byte < 0x09) || (byte > 0x0d && byte < 0x20),
    );
  }

  Future<void> _writeText(String path, String text) async {
    final safe = await _safePath(path, write: true);
    await _writeBytes(safe, Uint8List.fromList(utf8.encode(text)));
  }

  Future<void> _writeBytes(String path, Uint8List bytes) async {
    final sftp = _sftp!;
    final file = await sftp.open(
      path,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.truncate,
    );
    try {
      await file.writeBytes(bytes);
    } finally {
      await file.close();
    }
  }

  double? get _transferFraction => _transferTotalBytes <= 0
      ? null
      : (_transferredBytes / _transferTotalBytes).clamp(0.0, 1.0);

  void _beginTransfer(String label, int totalBytes) {
    setState(() {
      _busy = true;
      _transferLabel = label;
      _transferTotalBytes = totalBytes;
      _transferredBytes = 0;
      _lastProgressPaint = 0;
    });
  }

  void _advanceTransfer(int bytes) {
    if (_transferLabel == null) return;
    _transferredBytes += bytes;
    if (_transferredBytes - _lastProgressPaint < 256 * 1024 &&
        _transferredBytes < _transferTotalBytes) {
      return;
    }
    _lastProgressPaint = _transferredBytes;
    if (mounted) setState(() {});
  }

  void _finishTransfer() {
    if (!mounted) return;
    setState(() {
      _busy = false;
      _transferLabel = null;
      _transferTotalBytes = 0;
      _transferredBytes = 0;
    });
  }

  Future<void> _uploadFiles() async {
    if (_busy || !_isWritable(_currentPath)) return;
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: true,
    );
    if (selection == null) return;
    final files = selection.files
        .map((file) => file.path)
        .whereType<String>()
        .map(File.new)
        .toList();
    if (files.isEmpty) {
      _showMessage('File yang dipilih tidak dapat dibaca.');
      return;
    }
    try {
      final totalBytes = await _localFilesSize(files);
      _beginTransfer('Mengunggah ${files.length} file', totalBytes);
      final remoteDirectory = await _safePath(_currentPath, write: true);
      final existing = (await _sftp!.listdir(remoteDirectory))
          .map((item) => item.filename)
          .toSet();
      for (final file in files) {
        final name = _localLeaf(file.path);
        if (existing.contains(name)) {
          throw StateError('File "$name" sudah ada di folder tujuan.');
        }
        await _uploadLocalFile(
          file,
          await _safePath(_joinRemote(remoteDirectory, name), write: true),
        );
        existing.add(name);
      }
      await _loadDirectory(_currentPath);
      _showMessage('Upload selesai ke $_currentPath.');
    } catch (error) {
      _showMessage('Gagal mengunggah file: $error');
    } finally {
      _finishTransfer();
    }
  }

  Future<void> _uploadFolder() async {
    if (_busy || !_isWritable(_currentPath)) return;
    final folderPath = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pilih folder yang akan diunggah',
    );
    if (folderPath == null) return;
    final source = Directory(folderPath);
    final name = _localLeaf(folderPath);
    try {
      setState(() {
        _busy = true;
        _transferLabel = 'Memindai folder $name';
      });
      final files = await _collectLocalFiles(source);
      final totalBytes = await _localFilesSize(files);
      _beginTransfer('Mengunggah folder $name', totalBytes);
      final remoteParent = await _safePath(_currentPath, write: true);
      final target =
          await _safePath(_joinRemote(remoteParent, name), write: true);
      final existing = (await _sftp!.listdir(remoteParent))
          .map((item) => item.filename)
          .toSet();
      if (existing.contains(name)) {
        throw StateError('Folder "$name" sudah ada di folder tujuan.');
      }
      await _uploadLocalDirectory(source, target);
      await _loadDirectory(_currentPath);
      _showMessage('Folder $name berhasil diunggah.');
    } catch (error) {
      _showMessage('Gagal mengunggah folder: $error');
    } finally {
      _finishTransfer();
    }
  }

  Future<List<File>> _collectLocalFiles(Directory directory) async {
    final files = <File>[];
    await for (final entity
        in directory.list(followLinks: false, recursive: true)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.file) files.add(File(entity.path));
    }
    return files;
  }

  Future<int> _localFilesSize(List<File> files) async {
    var total = 0;
    for (final file in files) {
      total += await file.length();
    }
    return total;
  }

  Future<void> _uploadLocalDirectory(Directory source, String target) async {
    final sftp = _sftp!;
    await sftp.mkdir(target);
    await for (final entity
        in source.list(followLinks: false, recursive: false)) {
      final type = await FileSystemEntity.type(entity.path, followLinks: false);
      if (type == FileSystemEntityType.directory) {
        await _uploadLocalDirectory(
          Directory(entity.path),
          _joinRemote(target, _localLeaf(entity.path)),
        );
      } else if (type == FileSystemEntityType.file) {
        await _uploadLocalFile(
          File(entity.path),
          _joinRemote(target, _localLeaf(entity.path)),
        );
      }
    }
  }

  Future<void> _uploadLocalFile(File source, String remotePath) async {
    final remote = await _sftp!.open(
      remotePath,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.exclusive,
    );
    var offset = 0;
    try {
      await for (final chunk in source.openRead()) {
        final bytes = Uint8List.fromList(chunk);
        await remote.writeBytes(bytes, offset: offset);
        offset += bytes.length;
        _advanceTransfer(bytes.length);
      }
    } finally {
      await remote.close();
    }
  }

  String _localLeaf(String path) =>
      path.split(RegExp(r'[\\/]')).where((part) => part.isNotEmpty).last;

  Future<void> _showEntryActions(_RemoteEntry entry) async {
    final actions = <(String, IconData)>[
      ('Buka', Icons.open_in_new_rounded),
      ('Salin', Icons.copy_rounded),
      ('Potong', Icons.content_cut_rounded),
      ('Unduh', Icons.download_rounded),
      if (_isWritable(entry.path))
        ('Ubah nama', Icons.drive_file_rename_outline),
      if (_extension(entry.name) == 'zip' && _isWritable(_currentPath))
        ('Unzip di sini', Icons.unarchive_rounded),
      if (_isWritable(entry.path)) ('Hapus', Icons.delete_outline_rounded),
    ];
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.bgBottom,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                entry.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textPrimary),
              ),
              subtitle: Text(
                entry.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: AppColors.textSecondary),
              ),
            ),
            for (final item in actions)
              ListTile(
                leading: Icon(item.$2, color: AppColors.neonCyan),
                title: Text(
                  item.$1,
                  style: const TextStyle(color: AppColors.textPrimary),
                ),
                onTap: () => Navigator.pop(context, item.$1),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    switch (action) {
      case 'Buka':
        await _openEntry(entry);
      case 'Salin':
        setState(() {
          _clipboardEntry = entry;
          _clipboardIsCut = false;
        });
        _showMessage('Disalin. Buka folder tujuan lalu tekan Tempel.');
      case 'Potong':
        if (!_isWritable(entry.path)) {
          _showMessage('File ini berada di lokasi hanya-baca.');
          return;
        }
        setState(() {
          _clipboardEntry = entry;
          _clipboardIsCut = true;
        });
        _showMessage(
            'Dipilih untuk dipindahkan. Buka folder tujuan lalu Tempel.');
      case 'Unduh':
        await _downloadEntry(entry);
      case 'Ubah nama':
        await _renameEntry(entry);
      case 'Hapus':
        await _deleteEntry(entry);
      case 'Unzip di sini':
        await _unzipEntry(entry);
    }
  }

  Future<void> _pasteEntry() async {
    final source = _clipboardEntry;
    if (source == null || _busy) return;
    try {
      final destinationDirectory = await _safePath(_currentPath, write: true);
      final target = _joinRemote(destinationDirectory, _leaf(source.path));
      final existing = await _sftp!.listdir(destinationDirectory);
      if (existing.any((item) => item.filename == _leaf(target))) {
        throw StateError('Nama tersebut sudah ada di folder tujuan.');
      }
      setState(() => _busy = true);
      if (_clipboardIsCut) {
        final safeSource = await _safePath(source.path, write: true);
        await _sftp!.rename(safeSource, target);
      } else {
        await _copyRecursively(source.path, target);
      }
      setState(() {
        _clipboardEntry = null;
        _clipboardIsCut = false;
      });
      await _loadDirectory(_currentPath);
      _showMessage('Berhasil menempelkan ${_leaf(target)}.');
    } catch (error) {
      _showMessage('Gagal menempelkan file: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _copyRecursively(String source, String target) async {
    final safeSource = await _safePath(source);
    final attrs = await _sftp!.stat(safeSource, followLink: false);
    if (attrs.isSymbolicLink) {
      throw StateError('Menyalin symbolic link tidak didukung.');
    }
    if (attrs.isDirectory) {
      await _sftp!.mkdir(await _safePath(target, write: true));
      for (final entry in await _sftp!.listdir(safeSource)) {
        if (entry.filename == '.' || entry.filename == '..') continue;
        await _copyRecursively(
          _joinRemote(safeSource, entry.filename),
          _joinRemote(target, entry.filename),
        );
      }
      return;
    }
    final safeTarget = await _safePath(target, write: true);
    final input = await _sftp!.open(safeSource, mode: SftpFileOpenMode.read);
    final output = await _sftp!.open(
      safeTarget,
      mode: SftpFileOpenMode.write |
          SftpFileOpenMode.create |
          SftpFileOpenMode.exclusive,
    );
    try {
      await output.write(input.read()).done;
    } finally {
      await input.close();
      await output.close();
    }
  }

  Future<void> _renameEntry(_RemoteEntry entry) async {
    final name = await _askForName('Ubah nama', initial: entry.name);
    if (name == null || name.isEmpty || name.contains('/')) return;
    try {
      final safeSource = await _safePath(entry.path, write: true);
      final parent = _parentPath(safeSource);
      final safeTarget =
          await _safePath(_joinRemote(parent, name), write: true);
      final entries = await _sftp!.listdir(parent);
      if (entries.any((item) => item.filename == name)) {
        throw StateError('Nama tersebut sudah digunakan.');
      }
      await _sftp!.rename(safeSource, safeTarget);
      await _loadDirectory(_currentPath);
    } catch (error) {
      _showMessage('Gagal mengubah nama: $error');
    }
  }

  Future<void> _deleteEntry(_RemoteEntry entry) async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: AppColors.bgBottom,
            title: const Text(
              'Hapus secara permanen?',
              style: TextStyle(color: AppColors.textPrimary),
            ),
            content: Text(
              'Item ini akan dihapus dari server. Folder akan dihapus beserta seluruh isinya:\n${entry.path}',
              style: const TextStyle(color: AppColors.textSecondary),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  'Hapus',
                  style: TextStyle(color: AppColors.roseRed),
                ),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed) return;
    setState(() => _busy = true);
    try {
      await _deleteRecursively(entry.path);
      await _loadDirectory(_currentPath);
      _showMessage('Item dihapus.');
    } catch (error) {
      _showMessage('Gagal menghapus item: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteRecursively(String path) async {
    final safe = await _safePath(path, write: true);
    final attrs = await _sftp!.stat(safe, followLink: false);
    if (attrs.isDirectory) {
      for (final entry in await _sftp!.listdir(safe)) {
        if (entry.filename == '.' || entry.filename == '..') continue;
        await _deleteRecursively(_joinRemote(safe, entry.filename));
      }
      await _sftp!.rmdir(safe);
    } else {
      await _sftp!.remove(safe);
    }
  }

  Future<void> _createItem({required bool directory}) async {
    if (!_isWritable(_currentPath)) {
      _showMessage('Folder ini hanya dapat dibaca.');
      return;
    }
    final name = await _askForName(
      directory ? 'Folder baru' : 'File baru',
    );
    if (name == null || name.isEmpty || name.contains('/')) return;
    try {
      final parent = await _safePath(_currentPath, write: true);
      final target = _joinRemote(parent, name);
      final existing = await _sftp!.listdir(parent);
      if (existing.any((entry) => entry.filename == name)) {
        throw StateError('Nama tersebut sudah digunakan.');
      }
      if (directory) {
        await _sftp!.mkdir(target);
      } else {
        final file = await _sftp!.open(
          target,
          mode: SftpFileOpenMode.write |
              SftpFileOpenMode.create |
              SftpFileOpenMode.exclusive,
        );
        await file.close();
      }
      await _loadDirectory(_currentPath);
    } catch (error) {
      _showMessage('Gagal membuat item: $error');
    }
  }

  Future<String?> _askForName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgBottom,
        title:
            Text(title, style: const TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: AppColors.textPrimary),
          decoration: const InputDecoration(hintText: 'Nama'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Simpan'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<String?> _askForRemoteDirectory() async {
    final controller = TextEditingController(text: _currentPath);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppColors.bgBottom,
        title: const Text(
          'Lokasi ekstrak di server',
          style: TextStyle(color: AppColors.textPrimary),
        ),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(
            color: AppColors.textPrimary,
            fontFamily: 'monospace',
          ),
          decoration: const InputDecoration(
            labelText: 'Path folder server',
            helperText: 'Pilih folder tujuan yang sudah ada dan dapat ditulis.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Pilih lokasi'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  Future<void> _unzipEntry(_RemoteEntry entry) async {
    if (_busy) return;
    final selectedDirectory = await _askForRemoteDirectory();
    if (selectedDirectory == null || !mounted) return;
    try {
      final archive = await _safePath(entry.path);
      final destination = await _safePath(selectedDirectory, write: true);
      final destinationAttrs =
          await _sftp!.stat(destination, followLink: false);
      if (!destinationAttrs.isDirectory || destinationAttrs.isSymbolicLink) {
        throw StateError('Lokasi tujuan harus folder server yang valid.');
      }
      setState(() {
        _busy = true;
        _transferLabel = 'Mengekstrak ${_leaf(archive)}';
      });
      final listing = await _runRemoteCommand(
        'unzip -Z1 -- ${_shellQuote(archive)}',
      );
      if (listing.exitCode != null && listing.exitCode != 0) {
        final output = utf8.decode(listing.output, allowMalformed: true).trim();
        throw StateError(
          output.isEmpty ? 'Tidak dapat membaca isi ZIP.' : output,
        );
      }
      final members =
          utf8.decode(listing.output, allowMalformed: true).split('\n');
      for (final member in members) {
        final parts = member.replaceAll('\r', '').split('/');
        if (member.startsWith('/') ||
            member.contains('\\') ||
            parts.contains('..') ||
            member.contains(RegExp(r'[\x00-\x1F]'))) {
          throw StateError('Arsip berisi path yang tidak aman: $member');
        }
      }
      final result = await _runRemoteCommand(
        'unzip -n -- ${_shellQuote(archive)} -d ${_shellQuote(destination)}',
      );
      final output = utf8.decode(result.output, allowMalformed: true).trim();
      if (result.exitCode != null && result.exitCode != 0) {
        throw StateError(
          output.isEmpty
              ? 'Perintah unzip gagal (exit ${result.exitCode}).'
              : output,
        );
      }
      if (destination == _currentPath) await _loadDirectory(_currentPath);
      _showMessage(output.isEmpty ? 'Arsip berhasil diekstrak.' : output);
    } catch (error) {
      _showMessage('Gagal mengekstrak ZIP: $error');
    } finally {
      _finishTransfer();
    }
  }

  String _shellQuote(String value) => "'${value.replaceAll("'", "'\"'\"'")}'";

  Future<_RemoteCommandResult> _runRemoteCommand(String command) async {
    final session = await _client!.execute(command);
    try {
      final stdoutFuture = session.stdout.fold<List<int>>(
        <int>[],
        (output, chunk) => output..addAll(chunk),
      );
      final stderrFuture = session.stderr.fold<List<int>>(
        <int>[],
        (output, chunk) => output..addAll(chunk),
      );
      await session.done;
      final stdout = await stdoutFuture;
      final stderr = await stderrFuture;
      return _RemoteCommandResult(
        Uint8List.fromList([...stdout, ...stderr]),
        session.exitCode,
      );
    } finally {
      session.close();
    }
  }

  Future<void> _downloadEntry(_RemoteEntry entry) async {
    if (_busy) return;
    try {
      setState(() {
        _busy = true;
        _transferLabel = 'Menyiapkan unduhan ${_leaf(entry.path)}';
      });
      final totalBytes = await _remoteTreeSize(entry.path);
      final serverDirectory = await _downloadsDirectory();
      await serverDirectory.create(recursive: true);
      final target = File(
        '${serverDirectory.path}${Platform.pathSeparator}${_safeLocalName(_leaf(entry.path))}',
      );
      _beginTransfer('Mengunduh ${_leaf(entry.path)}', totalBytes);
      await _downloadRecursively(entry.path, target);
      _showMessage('Unduhan tersimpan di ${target.path}');
    } catch (error) {
      _showMessage('Gagal mengunduh file: $error');
    } finally {
      _finishTransfer();
    }
  }

  Future<Directory> _downloadsDirectory() async {
    if (Platform.isWindows) {
      final username = Platform.environment['USERNAME'];
      if (username == null || username.isEmpty) {
        throw StateError('Nama pengguna Windows tidak tersedia.');
      }
      return Directory(
        'C:\\Users\\$username\\Downloads\\RFMonitor\\${_safeLocalName(widget.config.displayName)}',
      );
    }
    final root = await getApplicationDocumentsDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}RFMonitor Downloads${Platform.pathSeparator}${_safeLocalName(widget.config.displayName)}',
    );
  }

  Future<int> _remoteTreeSize(String remote) async {
    final safe = await _safePath(remote);
    final attrs = await _sftp!.stat(safe, followLink: false);
    if (attrs.isSymbolicLink) {
      throw StateError('Unduhan symbolic link tidak didukung.');
    }
    if (!attrs.isDirectory) return attrs.size ?? 0;
    var total = 0;
    for (final entry in await _sftp!.listdir(safe)) {
      if (entry.filename == '.' || entry.filename == '..') continue;
      total += await _remoteTreeSize(_joinRemote(safe, entry.filename));
    }
    return total;
  }

  Future<void> _downloadRecursively(
      String remote, FileSystemEntity local) async {
    final safe = await _safePath(remote);
    final attrs = await _sftp!.stat(safe, followLink: false);
    if (attrs.isSymbolicLink) {
      throw StateError('Unduhan symbolic link tidak didukung.');
    }
    if (attrs.isDirectory) {
      final directory = Directory(local.path);
      await directory.create(recursive: true);
      for (final entry in await _sftp!.listdir(safe)) {
        if (entry.filename == '.' || entry.filename == '..') continue;
        final child = entry.filename.replaceAll(RegExp(r'[\\/]'), '_');
        await _downloadRecursively(
          _joinRemote(safe, entry.filename),
          File('${directory.path}${Platform.pathSeparator}$child'),
        );
      }
      return;
    }
    final file = local as File;
    await file.parent.create(recursive: true);
    await _downloadRemoteFile(safe, file, length: attrs.size);
  }

  Future<void> _downloadRemoteFile(
    String remotePath,
    File destination, {
    int? length,
  }) async {
    final remoteFile = await _sftp!.open(
      remotePath,
      mode: SftpFileOpenMode.read,
    );
    final sink = destination.openWrite();
    try {
      await for (final chunk in remoteFile.read(length: length)) {
        sink.add(chunk);
        _advanceTransfer(chunk.length);
      }
    } finally {
      try {
        await sink.close();
      } finally {
        await remoteFile.close();
      }
    }
  }

  String _safeLocalName(String value) =>
      value.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');

  Future<void> _disconnect() async {
    _client?.close();
    _client = null;
    _sftp = null;
    if (mounted) {
      setState(() {
        _entries = [];
        _error = null;
      });
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _formatSize(int? size) {
    if (size == null || size < 0) return '—';
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) {
      return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final connected = _sftp != null;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.folder_copy_rounded, color: AppColors.neonCyan),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'FILE MANAGER',
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              if (connected)
                IconButton(
                  tooltip: 'Putuskan',
                  onPressed: _disconnect,
                  icon: const Icon(
                    Icons.link_off_rounded,
                    color: AppColors.roseRed,
                  ),
                ),
              if (!connected)
                IconButton(
                  tooltip: 'Sambungkan',
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(
                    Icons.refresh_rounded,
                    color: AppColors.neonGreen,
                  ),
                ),
            ],
          ),
        ),
        if (connected)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.glassBase,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.glassBorder),
                        ),
                        child: _searchOpen
                            ? TextField(
                                controller: _searchController,
                                autofocus: true,
                                onChanged: (_) => setState(() {}),
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                ),
                                decoration: const InputDecoration(
                                  isDense: true,
                                  hintText: 'Cari nama file atau folder',
                                  border: InputBorder.none,
                                  prefixIcon: Icon(Icons.search_rounded),
                                ),
                              )
                            : Text(
                                _currentPath,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontFamily: 'monospace',
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ),
                    IconButton(
                      tooltip: _searchOpen ? 'Tutup pencarian' : 'Cari file',
                      onPressed: () {
                        setState(() {
                          _searchOpen = !_searchOpen;
                          _searchController.clear();
                        });
                      },
                      icon: Icon(
                        _searchOpen
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                        size: 22,
                        color: AppColors.neonCyan,
                      ),
                    ),
                  ],
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Folder sebelumnya',
                        onPressed: _busy || _currentPath == '/'
                            ? null
                            : () => _loadDirectory(_parentPath(_currentPath)),
                        icon: const Icon(Icons.arrow_upward_rounded, size: 22),
                      ),
                      IconButton(
                        tooltip: 'Salin path',
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: _currentPath),
                          );
                          _showMessage('Path folder disalin.');
                        },
                        icon: const Icon(Icons.copy_rounded, size: 22),
                      ),
                      IconButton(
                        tooltip: 'Tempel',
                        onPressed: _clipboardEntry == null || _busy
                            ? null
                            : _pasteEntry,
                        icon: Icon(
                          Icons.content_paste_rounded,
                          size: 22,
                          color: _clipboardEntry == null
                              ? AppColors.textSecondary
                              : AppColors.neonGreen,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Upload file atau folder',
                        onSelected: (value) {
                          if (value == 'files') {
                            _uploadFiles();
                          } else {
                            _uploadFolder();
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'files',
                            child: Text('Upload file / ZIP'),
                          ),
                          PopupMenuItem(
                            value: 'folder',
                            child: Text('Upload folder'),
                          ),
                        ],
                        icon: const Icon(
                          Icons.upload_rounded,
                          size: 23,
                          color: AppColors.neonGreen,
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Buat baru',
                        onSelected: (value) =>
                            _createItem(directory: value == 'folder'),
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'folder',
                            child: Text('Folder baru'),
                          ),
                          PopupMenuItem(
                              value: 'file', child: Text('File baru')),
                        ],
                        icon: const Icon(Icons.add_rounded, size: 23),
                      ),
                      IconButton(
                        tooltip: 'Muat ulang',
                        onPressed:
                            _busy ? null : () => _loadDirectory(_currentPath),
                        icon: const Icon(Icons.refresh_rounded, size: 22),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (_clipboardEntry != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 3),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${_clipboardIsCut ? 'Potong' : 'Salin'}: ${_leaf(_clipboardEntry!.path)}',
                style: const TextStyle(
                  color: AppColors.neonGold,
                  fontSize: 11,
                ),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              _error!,
              style: const TextStyle(color: AppColors.roseRed),
            ),
          ),
        if (!connected) _connectionForm(),
        if (connected)
          Expanded(
            child: _loading
                ? const Center(
                    child: CircularProgressIndicator(
                      color: AppColors.neonCyan,
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: () => _loadDirectory(_currentPath),
                    child: Builder(
                      builder: (context) {
                        final query =
                            _searchController.text.trim().toLowerCase();
                        final visibleEntries = _entries
                            .where((entry) =>
                                query.isEmpty ||
                                entry.name.toLowerCase().contains(query))
                            .toList();
                        return ListView.builder(
                          padding: EdgeInsets.fromLTRB(
                            12,
                            4,
                            12,
                            Platform.isWindows ? 24 : 120,
                          ),
                          itemCount: visibleEntries.length,
                          itemBuilder: (context, index) {
                            final entry = visibleEntries[index];
                            final directory = entry.attrs.isDirectory;
                            final symlink = entry.attrs.isSymbolicLink;
                            return Card(
                              color: AppColors.glassBase,
                              child: ListTile(
                                leading: Icon(
                                  directory
                                      ? Icons.folder_rounded
                                      : symlink
                                          ? Icons.link_rounded
                                          : Icons.insert_drive_file_rounded,
                                  color: directory
                                      ? AppColors.neonGold
                                      : AppColors.neonCyan,
                                ),
                                title: Text(
                                  entry.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  directory
                                      ? 'Folder'
                                      : '${_formatSize(entry.attrs.size)}${_isWritable(entry.path) ? '' : ' · hanya baca'}',
                                  style: const TextStyle(
                                    color: AppColors.textSecondary,
                                    fontSize: 11,
                                  ),
                                ),
                                onTap: () => _openEntry(entry),
                                onLongPress: () => _showEntryActions(entry),
                                trailing: IconButton(
                                  tooltip: 'Menu file',
                                  onPressed: () => _showEntryActions(entry),
                                  icon: const Icon(
                                    Icons.more_vert_rounded,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
          ),
        if (_busy) ...[
          if (_transferLabel != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _transferLabel!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    _transferFraction == null
                        ? 'Menyiapkan…'
                        : '${(_transferFraction! * 100).round()}%',
                    style: const TextStyle(
                      color: AppColors.neonCyan,
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          LinearProgressIndicator(
            value: _transferFraction,
            minHeight: 4,
            color: AppColors.neonCyan,
            backgroundColor: AppColors.glassBorder,
          ),
        ],
      ],
    );
  }

  Widget _connectionForm() {
    return Expanded(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
        children: [
          const Text(
            'SFTP hanya mencoba alamat Local lalu Tailscale yang resolve ke IP privat/VPN. URL publik/Cloudflare tidak dipakai di File Manager.',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _usernameController,
            autocorrect: false,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Username SSH',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _passwordController,
            obscureText: true,
            style: const TextStyle(color: AppColors.textPrimary),
            decoration: const InputDecoration(
              labelText: 'Password SSH',
              prefixIcon: Icon(Icons.password_rounded),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _connect,
            icon: const Icon(Icons.folder_open_rounded),
            label: Text(_busy ? 'Menyambungkan…' : 'Hubungkan ke server'),
          ),
        ],
      ),
    );
  }
}

class _RemoteTextEditorPage extends StatefulWidget {
  final String name;
  final String initialText;
  final Future<void> Function(String text) onSave;

  const _RemoteTextEditorPage({
    required this.name,
    required this.initialText,
    required this.onSave,
  });

  @override
  State<_RemoteTextEditorPage> createState() => _RemoteTextEditorPageState();
}

class _RemoteTextEditorPageState extends State<_RemoteTextEditorPage> {
  late final _controller = TextEditingController(text: widget.initialText);
  late String _savedText = widget.initialText;
  double _fontSize = 13;
  bool _saving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final textToSave = _controller.text;
    try {
      await widget.onSave(textToSave);
      if (mounted) {
        setState(() => _savedText = textToSave);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('File berhasil disimpan ke server.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan file: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xFF101114),
        appBar: AppBar(
          title: Text(
            '${widget.name}${_controller.text == _savedText ? '' : ' •'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          actions: [
            IconButton(
              tooltip: 'Salin isi file',
              onPressed: () async {
                await Clipboard.setData(
                  ClipboardData(text: _controller.text),
                );
              },
              icon: const Icon(Icons.copy_rounded),
            ),
            IconButton(
              tooltip: 'Simpan ke server',
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Row(
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.text_decrease_rounded),
                ),
                Expanded(
                  child: Slider(
                    min: 8,
                    max: 24,
                    value: _fontSize,
                    onChanged: (value) => setState(() => _fontSize = value),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 12),
                  child: Icon(Icons.text_increase_rounded),
                ),
              ],
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                expands: true,
                maxLines: null,
                minLines: null,
                keyboardType: TextInputType.multiline,
                textAlignVertical: TextAlignVertical.top,
                autofocus: true,
                showCursor: true,
                cursorColor: const Color(0xFF28C840),
                cursorWidth: 2,
                selectionControls: materialTextSelectionControls,
                onChanged: (_) => setState(() {}),
                style: TextStyle(
                  color: const Color(0xFFE5E5E7),
                  fontFamily: 'monospace',
                  fontSize: _fontSize,
                  height: 1.35,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  contentPadding: EdgeInsets.all(14),
                ),
              ),
            ),
          ],
        ),
      );
}

class _RemotePreviewPage extends StatefulWidget {
  final String name;
  final Uint8List? bytes;
  final File? videoFile;
  final bool video;

  const _RemotePreviewPage({
    required this.name,
    this.bytes,
    this.videoFile,
    required this.video,
  });

  @override
  State<_RemotePreviewPage> createState() => _RemotePreviewPageState();
}

class _RemotePreviewPageState extends State<_RemotePreviewPage> {
  VideoPlayerController? _videoController;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.video) _initVideo();
  }

  Future<void> _initVideo() async {
    try {
      final file = widget.videoFile;
      if (file == null && widget.bytes == null) {
        throw StateError('Video tidak tersedia untuk diputar.');
      }
      late final File localFile;
      if (file != null) {
        localFile = file;
      } else {
        final temp = await getTemporaryDirectory();
        final safeName = widget.name.replaceAll(RegExp(r'[\\/]'), '_');
        localFile = File(
          '${temp.path}${Platform.pathSeparator}rfmonitor_$safeName',
        );
        await localFile.writeAsBytes(widget.bytes!, flush: true);
      }
      final controller = VideoPlayerController.file(localFile);
      _videoController = controller;
      await controller.initialize();
      if (mounted) setState(() {});
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    if (widget.videoFile != null) {
      widget.videoFile!.delete().catchError((error) {
        debugPrint('Unable to remove temporary video: $error');
        return widget.videoFile!;
      });
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(title: Text(widget.name)),
        body: Center(
          child: _error != null
              ? Text(
                  'Tidak bisa membuka media: $_error',
                  style: const TextStyle(color: Colors.white),
                )
              : widget.video
                  ? _buildVideo()
                  : InteractiveViewer(
                      child: Image.memory(
                        widget.bytes!,
                        fit: BoxFit.contain,
                      ),
                    ),
        ),
      );

  Widget _buildVideo() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const CircularProgressIndicator(color: AppColors.neonCyan);
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        AspectRatio(
          aspectRatio: controller.value.aspectRatio,
          child: VideoPlayer(controller),
        ),
        IconButton(
          color: Colors.white,
          onPressed: () => setState(
            () => controller.value.isPlaying
                ? controller.pause()
                : controller.play(),
          ),
          icon: Icon(
            controller.value.isPlaying
                ? Icons.pause_rounded
                : Icons.play_arrow_rounded,
          ),
        ),
      ],
    );
  }
}
