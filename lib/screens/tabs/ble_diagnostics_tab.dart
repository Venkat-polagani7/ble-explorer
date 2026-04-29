import 'dart:async';

import 'package:excel/excel.dart' hide Border;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart' hide License;
import 'package:flutter_blue_plus/flutter_blue_plus.dart' as fbp show License;
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../ble_theme.dart';
import '../../services/ble_log_service.dart';

// ══════════════════════════════════════════════════════════════
// DIAGNOSTICS TAB
// Repeated connection attempts to measure BLE reliability
// ══════════════════════════════════════════════════════════════

// ── Data models ───────────────────────────────────────────────

class BleRetryLog {
  final int retryNumber;
  final DateTime startTime;
  DateTime? endTime;
  Duration? duration;
  bool success = false;
  String stage = 'initialized';
  String error = '';
  String errorCode = '';
  int? rssi;
  final List<String> stageLogs = [];

  BleRetryLog({required this.retryNumber, required this.startTime});
}

class BleAttemptLog {
  final int attempt;
  final DateTime startTime;
  DateTime? endTime;
  Duration? duration;
  bool success = false;
  int? successRetryNumber;
  int totalRetries = 0;
  final List<BleRetryLog> retries = [];

  BleAttemptLog({required this.attempt, required this.startTime});

  String get resultSummary {
    if (success && successRetryNumber != null) {
      return 'SUCCESS on retry $successRetryNumber / $totalRetries';
    }
    return 'FAILED after $totalRetries retries';
  }
}

// ── Controller ────────────────────────────────────────────────

class _DiagController extends ChangeNotifier {
  bool _isRunning = false;
  bool get isRunning => _isRunning;

  String _currentStatus = 'Ready';
  String get currentStatus => _currentStatus;

  int _currentAttempt = 0;
  int get currentAttempt => _currentAttempt;

  int _currentRetry = 0;
  int get currentRetry => _currentRetry;

  String _lastError = '';
  String get lastError => _lastError;

  DateTime? _testStartTime;
  DateTime? get testStartTime => _testStartTime;

  final List<BleAttemptLog> logs = [];
  int successCount = 0;
  int firstSuccessAttempt = -1;
  int timeoutCount = 0;
  int gattErrorCount = 0;
  int otherErrorCount = 0;

  String _deviceRemoteId = '';
  int _maxAttempts = 0;
  int _retriesPerAttempt = 3;
  int _retryDelaySeconds = 2;
  int _connectionTimeoutSeconds = 10;
  bool _scanBeforeConnect = false;
  bool _stopRequested = false;
  BluetoothDevice? _currentDevice;

  Duration get totalDuration {
    if (_testStartTime == null) return Duration.zero;
    return DateTime.now().difference(_testStartTime!);
  }

  Duration get averageAttemptDuration {
    if (logs.isEmpty) return Duration.zero;
    final totalMs = logs.fold<int>(
        0, (sum, log) => sum + (log.duration?.inMilliseconds ?? 0));
    return Duration(milliseconds: totalMs ~/ logs.length);
  }

  double get successRate =>
      logs.isEmpty ? 0 : successCount / logs.length * 100;

  Future<void> startTest({
    required String deviceRemoteId,
    bool unlimitedRetries = true,
    int maxRetryCount = 10,
    int retriesPerAttempt = 3,
    int retryDelaySeconds = 2,
    int connectionTimeoutSeconds = 10,
    bool scanBeforeConnect = false,
    BleLogService? logger,
  }) async {
    if (_isRunning) return;
    _reset();
    _isRunning = true;
    _deviceRemoteId = deviceRemoteId.trim();
    _maxAttempts = unlimitedRetries ? 0 : maxRetryCount;
    _retriesPerAttempt = retriesPerAttempt.clamp(1, 100);
    _retryDelaySeconds = retryDelaySeconds;
    _connectionTimeoutSeconds = connectionTimeoutSeconds;
    _scanBeforeConnect = scanBeforeConnect;
    _testStartTime = DateTime.now();
    _currentStatus = 'Starting BLE connection test…';
    notifyListeners();
    logger?.info('Test started for $_deviceRemoteId', tag: 'DIAG');

    try {
      await _performConnectionTest(logger);
    } finally {
      _isRunning = false;
      _currentStatus = firstSuccessAttempt != -1
          ? 'Test completed — Connected after $firstSuccessAttempt attempts'
          : 'Test completed — No successful connection';
      logger?.info(_currentStatus, tag: 'DIAG');
      notifyListeners();
    }
  }

  void stopTest() {
    _stopRequested = true;
    _currentDevice?.disconnect().catchError((_) {});
    _currentStatus = 'Stopping test…';
    notifyListeners();
  }

  void reset() {
    if (_isRunning) stopTest();
    _reset();
    notifyListeners();
  }

  void _reset() {
    _isRunning = false;
    _stopRequested = false;
    _currentAttempt = 0;
    _currentRetry = 0;
    _currentStatus = 'Ready';
    _lastError = '';
    _testStartTime = null;
    logs.clear();
    successCount = 0;
    firstSuccessAttempt = -1;
    timeoutCount = 0;
    gattErrorCount = 0;
    otherErrorCount = 0;
    _currentDevice = null;
  }

  Future<void> _performConnectionTest(BleLogService? logger) async {
    int attempt = 0;

    while ((_maxAttempts == 0 || attempt < _maxAttempts) && !_stopRequested) {
      attempt++;
      _currentAttempt = attempt;

      final attemptLog = BleAttemptLog(
          attempt: attempt, startTime: DateTime.now());
      attemptLog.totalRetries = _retriesPerAttempt;

      _currentStatus = 'Attempt $attempt — starting retries…';
      notifyListeners();

      bool attemptSuccess = false;

      for (int retryNum = 1;
          retryNum <= _retriesPerAttempt && !_stopRequested;
          retryNum++) {
        _currentRetry = retryNum;
        _currentStatus =
            'Attempt $attempt — retry $retryNum / $_retriesPerAttempt';
        notifyListeners();

        final retryLog =
            BleRetryLog(retryNumber: retryNum, startTime: DateTime.now());
        bool retrySuccess = false;
        String retryError = '';

        try {
          retryLog.stage = 'scanning';
          retryLog.stageLogs.add('Scan started');

          if (_scanBeforeConnect) {
            final scanSub = FlutterBluePlus.onScanResults.listen((results) {
              for (final result in results) {
                if (result.device.remoteId.toString() == _deviceRemoteId) {
                  retryLog.rssi = result.rssi;
                  retryLog.stageLogs.add(
                      'Device found — RSSI: ${result.rssi} dBm');
                  logger?.debug(
                      'Pre-scan found device. RSSI: ${result.rssi} dBm',
                      tag: 'DIAG');
                }
              }
            });
            await FlutterBluePlus.startScan(
              withRemoteIds: [_deviceRemoteId],
              timeout: const Duration(seconds: 8),
              //withServices: [Guid('5d321206')],
            );
            await Future.delayed(const Duration(seconds: 9));
            await scanSub.cancel();
            await FlutterBluePlus.stopScan();
          }

          retryLog.stage = 'connecting';
          retryLog.stageLogs
              .add('Connection initiated to $_deviceRemoteId');
          logger?.info(
              'Attempt $attempt / Retry $retryNum — connecting…',
              tag: 'DIAG');

          _currentDevice = BluetoothDevice.fromId(_deviceRemoteId);
          await _currentDevice!.connect(
            license: fbp.License.free,
            timeout: Duration(seconds: _connectionTimeoutSeconds),
            autoConnect: false,
          );

          final connState =
              await _currentDevice!.connectionState.firstWhere(
            (state) => state == BluetoothConnectionState.connected,
            orElse: () => BluetoothConnectionState.disconnected,
          );

          if (connState != BluetoothConnectionState.connected) {
            throw Exception('Device did not reach connected state');
          }

          retryLog.stage = 'connection established';
          retryLog.stageLogs.add('Connection established successfully');
          retryLog.stage = 'discovering services';
          retryLog.stageLogs.add('Service discovery started');

          await _currentDevice!.discoverServices();

          retryLog.stage = 'services discovered';
          retrySuccess = true;
          logger?.success(
              'Attempt $attempt / Retry $retryNum — SUCCESS', tag: 'DIAG');
        } on Exception catch (e) {
          retryError = e.toString();
          retryLog.error = retryError;
          retryLog.stageLogs
              .add('Error at stage "${retryLog.stage}": $retryError');
          logger?.error(
              'Attempt $attempt / Retry $retryNum FAILED at ${retryLog.stage}: $retryError',
              tag: 'DIAG');

          final errLower = retryError.toLowerCase();
          if (errLower.contains('timeout') ||
              errLower.contains('timed out')) {
            timeoutCount++;
            retryLog.errorCode = 'TIMEOUT';
          } else if (errLower.contains('gatt') ||
              errLower.contains('133')) {
            gattErrorCount++;
            retryLog.errorCode = 'GATT';
          } else {
            otherErrorCount++;
            retryLog.errorCode = 'OTHER';
          }
        } finally {
          retryLog.endTime = DateTime.now();
          retryLog.duration =
              retryLog.endTime!.difference(retryLog.startTime);
          retryLog.success = retrySuccess;
          attemptLog.retries.add(retryLog);
          _lastError =
              retryError.isNotEmpty ? retryError : _lastError;

          if (_currentDevice != null) {
            await _currentDevice!.disconnect().catchError((_) {});
            _currentDevice = null;
          }
          notifyListeners();
        }

        if (retrySuccess) {
          attemptSuccess = true;
          attemptLog.successRetryNumber = retryNum;
          break;
        }

        if (!_stopRequested && retryNum < _retriesPerAttempt) {
          await Future.delayed(const Duration(milliseconds: 500));
        }
      }

      attemptLog.endTime = DateTime.now();
      attemptLog.duration =
          attemptLog.endTime!.difference(attemptLog.startTime);
      attemptLog.success = attemptSuccess;

      if (attemptSuccess) {
        successCount++;
        if (firstSuccessAttempt == -1) firstSuccessAttempt = attempt;
        _currentStatus =
            'Attempt $attempt succeeded on retry ${attemptLog.successRetryNumber}!';
      } else {
        _currentStatus =
            'Attempt $attempt failed after $_retriesPerAttempt retries';
      }

      logs.add(attemptLog);
      notifyListeners();

      if (!_stopRequested &&
          (_maxAttempts == 0 || attempt < _maxAttempts)) {
        _currentStatus =
            'Waiting ${_retryDelaySeconds}s before next attempt…';
        notifyListeners();
        await Future.delayed(Duration(seconds: _retryDelaySeconds));
      }
    }
  }

  Future<void> exportReport() async {
    final excel = Excel.createExcel();

    // ── Attempts sheet ──────────────────────────────────────
    final attSheet = excel['Attempts'];
    attSheet.appendRow([
      TextCellValue('Attempt'),
      TextCellValue('Start Time'),
      TextCellValue('End Time'),
      TextCellValue('Duration (s)'),
      TextCellValue('Success'),
      TextCellValue('Total Retries'),
      TextCellValue('Succeeded on Retry #'),
      TextCellValue('Result Summary'),
    ]);
    for (final log in logs) {
      attSheet.appendRow([
        IntCellValue(log.attempt),
        TextCellValue(
            DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(log.startTime)),
        TextCellValue(log.endTime != null
            ? DateFormat('yyyy-MM-dd HH:mm:ss.SSS').format(log.endTime!)
            : ''),
        DoubleCellValue(
            (log.duration?.inMilliseconds ?? 0).toDouble() / 1000),
        TextCellValue(log.success ? 'YES' : 'NO'),
        IntCellValue(log.totalRetries),
        log.successRetryNumber != null
            ? IntCellValue(log.successRetryNumber!)
            : TextCellValue('—'),
        TextCellValue(log.resultSummary),
      ]);
    }

    // ── Retry details sheet ─────────────────────────────────
    final retSheet = excel['Retry Details'];
    retSheet.appendRow([
      TextCellValue('Attempt'),
      TextCellValue('Retry #'),
      TextCellValue('Start Time'),
      TextCellValue('End Time'),
      TextCellValue('Duration (s)'),
      TextCellValue('Success'),
      TextCellValue('Stage'),
      TextCellValue('Error'),
      TextCellValue('Error Code'),
      TextCellValue('RSSI'),
      TextCellValue('Stage Logs'),
    ]);
    for (final attempt in logs) {
      for (final retry in attempt.retries) {
        retSheet.appendRow([
          IntCellValue(attempt.attempt),
          IntCellValue(retry.retryNumber),
          TextCellValue(DateFormat('yyyy-MM-dd HH:mm:ss.SSS')
              .format(retry.startTime)),
          TextCellValue(retry.endTime != null
              ? DateFormat('yyyy-MM-dd HH:mm:ss.SSS')
                  .format(retry.endTime!)
              : ''),
          DoubleCellValue(
              (retry.duration?.inMilliseconds ?? 0).toDouble() / 1000),
          TextCellValue(retry.success ? 'YES' : 'NO'),
          TextCellValue(retry.stage),
          TextCellValue(retry.error),
          TextCellValue(retry.errorCode),
          TextCellValue(retry.rssi?.toString() ?? ''),
          TextCellValue(retry.stageLogs.join(' | ')),
        ]);
      }
    }

    // ── Summary sheet ───────────────────────────────────────
    final sumSheet = excel['Summary'];
    sumSheet.appendRow(
        [TextCellValue('Metric'), TextCellValue('Value')]);
    void addRow(String k, CellValue v) =>
        sumSheet.appendRow([TextCellValue(k), v]);
    addRow('Total Attempts', IntCellValue(logs.length));
    addRow('Retries Per Attempt', IntCellValue(_retriesPerAttempt));
    addRow('Successful Attempts', IntCellValue(successCount));
    addRow('Success Rate',
        TextCellValue('${successRate.toStringAsFixed(1)}%'));
    addRow(
        'First Success at Attempt',
        firstSuccessAttempt != -1
            ? IntCellValue(firstSuccessAttempt)
            : TextCellValue('—'));
    addRow(
        'Total Duration',
        TextCellValue(
            '${totalDuration.inMinutes}m ${totalDuration.inSeconds.remainder(60)}s'));
    addRow('Avg Attempt Duration',
        TextCellValue('${averageAttemptDuration.inSeconds}s'));
    addRow('Timeout Failures', IntCellValue(timeoutCount));
    addRow('GATT Failures', IntCellValue(gattErrorCount));
    addRow('Other Failures', IntCellValue(otherErrorCount));

    final bytes = excel.encode();
    if (bytes == null) return;

    final xFile = XFile.fromData(
      Uint8List.fromList(bytes),
      name:
          'ble_diagnostics_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );

    await Share.shareXFiles(
      [xFile],
      text: firstSuccessAttempt != -1
          ? 'BLE Diagnostics — Connected at attempt $firstSuccessAttempt'
          : 'BLE Diagnostics — No successful connection',
    );
  }
}

// ── UI ────────────────────────────────────────────────────────

class BleDiagnosticsTab extends StatefulWidget {
  final BleLogService logService;
  final String? initialDeviceId;

  const BleDiagnosticsTab({
    super.key, 
    required this.logService,
    this.initialDeviceId,
  });

  @override
  State<BleDiagnosticsTab> createState() => _BleDiagnosticsTabState();
}

class _BleDiagnosticsTabState extends State<BleDiagnosticsTab>
    with AutomaticKeepAliveClientMixin {
  late final _DiagController _ctrl;
  
  @override
  bool get wantKeepAlive => true;

  final _deviceIdCtrl = TextEditingController();
  final _maxRetriesCtrl = TextEditingController(text: '10');
  final _retriesPerAttemptCtrl = TextEditingController(text: '3');
  final _retryDelayCtrl = TextEditingController(text: '2');
  final _connTimeoutCtrl = TextEditingController(text: '10');

  bool _unlimitedRetries = true;
  int _maxRetryCount = 10;
  int _retriesPerAttempt = 3;
  int _retryDelaySeconds = 2;
  int _connectionTimeoutSeconds = 10;
  bool _scanBeforeConnect = false;

  final ScrollController _scrollCtrl = ScrollController();

  @override
  void initState() {
    super.initState();
    if (widget.initialDeviceId != null) {
      final id = widget.initialDeviceId!.contains('|') 
          ? widget.initialDeviceId!.split('|').first 
          : widget.initialDeviceId!;
      _deviceIdCtrl.text = id;
    }
    _ctrl = _DiagController();
    _ctrl.addListener(() {
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollCtrl.hasClients) {
            _scrollCtrl.animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _deviceIdCtrl.dispose();
    _maxRetriesCtrl.dispose();
    _retriesPerAttemptCtrl.dispose();
    _retryDelayCtrl.dispose();
    _connTimeoutCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _startTest() {
    final id = _deviceIdCtrl.text.trim();
    if (id.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        backgroundColor: BleTheme.accentOrange,
        content: Text('Enter a device MAC / Remote ID first.',
            style: TextStyle(color: Colors.white)),
      ));
      return;
    }
    _ctrl.startTest(
      deviceRemoteId: id,
      unlimitedRetries: _unlimitedRetries,
      maxRetryCount: _maxRetryCount,
      retriesPerAttempt: _retriesPerAttempt,
      retryDelaySeconds: _retryDelaySeconds,
      connectionTimeoutSeconds: _connectionTimeoutSeconds,
      scanBeforeConnect: _scanBeforeConnect,
      logger: widget.logService,
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildInputCard(),
          const SizedBox(height: 12),
          _buildControlCard(),
          const SizedBox(height: 12),
          _buildStatsRow(),
          const SizedBox(height: 12),
          _buildLogsCard(),
        ],
      ),
    );
  }

  Widget _buildInputCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle('Target Device', Icons.bluetooth),
          const SizedBox(height: 12),
          _darkField(
            controller: _deviceIdCtrl,
            hint: '00:11:22:33:44:55',
            label: 'MAC / Remote ID',
            icon: Icons.bluetooth,
            suffix: IconButton(
              icon: const Icon(Icons.paste_rounded,
                  color: BleTheme.textMuted, size: 18),
              onPressed: () async {
                final d = await Clipboard.getData('text/plain');
                if (d?.text != null) _deviceIdCtrl.text = d!.text!.trim();
              },
              tooltip: 'Paste',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _toggleRow(
                  label: 'Unlimited attempts',
                  value: _unlimitedRetries,
                  onChanged: (v) => setState(() => _unlimitedRetries = v),
                ),
              ),
              if (!_unlimitedRetries) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: _darkField(
                    controller: _maxRetriesCtrl,
                    hint: '10',
                    label: 'Max attempts',
                    icon: Icons.repeat,
                    keyboardType: TextInputType.number,
                    onChanged: (v) =>
                        _maxRetryCount = int.tryParse(v) ?? 10,
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          _darkField(
            controller: _retriesPerAttemptCtrl,
            hint: '3',
            label: 'Retries per attempt',
            icon: Icons.replay,
            keyboardType: TextInputType.number,
            onChanged: (v) =>
                _retriesPerAttempt = int.tryParse(v) ?? 3,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _darkField(
                  controller: _retryDelayCtrl,
                  hint: '2',
                  label: 'Retry delay (s)',
                  icon: Icons.timer_outlined,
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      _retryDelaySeconds = int.tryParse(v) ?? 2,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _darkField(
                  controller: _connTimeoutCtrl,
                  hint: '10',
                  label: 'Conn timeout (s)',
                  icon: Icons.hourglass_bottom,
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      _connectionTimeoutSeconds = int.tryParse(v) ?? 10,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _toggleRow(
            label: 'Scan before connect (captures RSSI)',
            value: _scanBeforeConnect,
            onChanged: (v) => setState(() => _scanBeforeConnect = v),
          ),
        ],
      ),
    );
  }

  Widget _buildControlCard() {
    return _card(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: AnimBtn(
                  label: 'START',
                  icon: Icons.play_arrow_rounded,
                  color: BleTheme.accentGreen,
                  enabled: !_ctrl.isRunning,
                  onTap: _startTest,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: AnimBtn(
                  label: 'STOP',
                  icon: Icons.stop_rounded,
                  color: BleTheme.accentRed,
                  enabled: _ctrl.isRunning,
                  onTap: _ctrl.stopTest,
                ),
              ),
              const SizedBox(width: 10),
              AnimBtn(
                label: 'RESET',
                icon: Icons.refresh,
                color: BleTheme.textSecondary,
                enabled: !_ctrl.isRunning,
                onTap: _ctrl.reset,
                compact: true,
              ),
              const SizedBox(width: 6),
              AnimBtn(
                label: 'XLS',
                icon: Icons.download_rounded,
                color: BleTheme.accentOrange,
                enabled: _ctrl.logs.isNotEmpty,
                onTap: _ctrl.exportReport,
                compact: true,
              ),
            ],
          ),
          if (_ctrl.isRunning) ...[
            const SizedBox(height: 14),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const LinearProgressIndicator(
                  backgroundColor: BleTheme.surfaceBorder,
                  valueColor:
                      AlwaysStoppedAnimation(BleTheme.accent),
                ),
                const SizedBox(height: 8),
                Text(
                  _ctrl.currentStatus,
                  style: const TextStyle(
                      color: BleTheme.textSecondary, fontSize: 12),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final total = _ctrl.logs.length;
    return Row(
      children: [
        _statChip('Total', total.toString(), BleTheme.textSecondary),
        const SizedBox(width: 8),
        _statChip('OK', _ctrl.successCount.toString(), BleTheme.accentGreen),
        const SizedBox(width: 8),
        _statChip(
            'Timeout', _ctrl.timeoutCount.toString(), BleTheme.accentOrange),
        const SizedBox(width: 8),
        _statChip(
            'GATT', _ctrl.gattErrorCount.toString(), BleTheme.accentRed),
        const SizedBox(width: 8),
        _statChip(
            'Rate',
            total == 0
                ? '—'
                : '${_ctrl.successRate.toStringAsFixed(0)}%',
            BleTheme.accent),
      ],
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: TextStyle(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(label,
                style: const TextStyle(
                    color: BleTheme.textMuted, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  Widget _buildLogsCard() {
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _sectionTitle('Attempt Log', Icons.format_list_bulleted),
              const Spacer(),
              Text('${_ctrl.logs.length} attempt(s)',
                  style: const TextStyle(
                      color: BleTheme.textMuted, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 10),
          if (_ctrl.firstSuccessAttempt != -1)
            Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: BleTheme.accentGreen.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                    color: BleTheme.accentGreen.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: BleTheme.accentGreen, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'First success on attempt #${_ctrl.firstSuccessAttempt}',
                    style: const TextStyle(
                      color: BleTheme.accentGreen,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          if (_ctrl.logs.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text('No attempts yet',
                    style: TextStyle(
                        color: BleTheme.textMuted, fontSize: 13)),
              ),
            )
          else
            SizedBox(
              height: 440,
              child: ListView.builder(
                controller: _scrollCtrl,
                itemCount: _ctrl.logs.length,
                itemBuilder: (_, i) =>
                    _AttemptTile(log: _ctrl.logs[i]),
              ),
            ),
        ],
      ),
    );
  }

  // ── helpers ────────────────────────────────────────────────

  Widget _card({required Widget child}) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BleTheme.cardDecoration,
        child: child,
      );

  Widget _sectionTitle(String label, IconData icon) => Row(
        children: [
          Icon(icon, size: 16, color: BleTheme.accent),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                color: BleTheme.textPrimary,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              )),
        ],
      );

  Widget _darkField({
    required TextEditingController controller,
    required String hint,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    ValueChanged<String>? onChanged,
    Widget? suffix,
  }) =>
      TextField(
        controller: controller,
        keyboardType: keyboardType,
        onChanged: onChanged,
        style: const TextStyle(color: BleTheme.textPrimary, fontSize: 13),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(
              color: BleTheme.textSecondary, fontSize: 12),
          hintText: hint,
          hintStyle:
              const TextStyle(color: BleTheme.textMuted, fontSize: 12),
          prefixIcon: Icon(icon, color: BleTheme.textMuted, size: 18),
          suffixIcon: suffix,
          filled: true,
          fillColor: BleTheme.bg,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BleTheme.surfaceBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BleTheme.surfaceBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: BleTheme.accent),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          isDense: true,
        ),
      );

  Widget _toggleRow({
    required String label,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) =>
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    color: BleTheme.textSecondary, fontSize: 13)),
          ),
          Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: BleTheme.accent),
        ],
      );
}

// ═══════════════════════════════════════════════════
// ATTEMPT TILE
// ═══════════════════════════════════════════════════

class _AttemptTile extends StatelessWidget {
  final BleAttemptLog log;

  const _AttemptTile({required this.log});

  @override
  Widget build(BuildContext context) {
    final color = log.success ? BleTheme.accentGreen : BleTheme.accentRed;
    final durStr =
        '${((log.duration?.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)}s';

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          leading: Icon(
              log.success ? Icons.check_circle : Icons.error_rounded,
              color: color,
              size: 20),
          title: Text(
            'Attempt #${log.attempt}',
            style: const TextStyle(
              color: BleTheme.textPrimary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          subtitle: Text('${log.resultSummary}  •  $durStr',
              style: TextStyle(color: color, fontSize: 11)),
          children: [
            if (log.retries.isEmpty)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('No retry data',
                    style: TextStyle(
                        color: BleTheme.textMuted, fontSize: 12)),
              )
            else
              ...log.retries.map((r) => _RetryTile(retry: r)),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _RetryTile extends StatelessWidget {
  final BleRetryLog retry;

  const _RetryTile({required this.retry});

  @override
  Widget build(BuildContext context) {
    final color =
        retry.success ? BleTheme.accentGreen : BleTheme.accentRed;
    final dur =
        '${((retry.duration?.inMilliseconds ?? 0) / 1000).toStringAsFixed(2)}s';

    return Container(
      margin: const EdgeInsets.only(left: 14, right: 8, bottom: 6),
      decoration: BoxDecoration(
        color: BleTheme.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          tilePadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
          leading: Icon(
            retry.success
                ? Icons.check_circle_outline
                : Icons.cancel_outlined,
            color: color,
            size: 16,
          ),
          title: Text('Retry #${retry.retryNumber}',
              style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600)),
          subtitle: Text(
            '$dur  •  ${retry.stage}'
                '${retry.rssi != null ? "  •  ${retry.rssi} dBm" : ""}',
            style: const TextStyle(
                color: BleTheme.textMuted, fontSize: 10),
          ),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (retry.error.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.error_outline,
                            size: 12, color: BleTheme.accentRed),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(retry.error,
                              style: const TextStyle(
                                  color: BleTheme.accentRed,
                                  fontSize: 11)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text('Code: ${retry.errorCode}',
                        style: const TextStyle(
                          color: BleTheme.accentOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        )),
                    const SizedBox(height: 6),
                  ],
                  const Text('Stage Logs:',
                      style: TextStyle(
                        color: BleTheme.textSecondary,
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                      )),
                  ...retry.stageLogs.map(
                    (s) => Padding(
                      padding: const EdgeInsets.only(left: 6, top: 2),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('• ',
                              style: TextStyle(
                                  color: BleTheme.textMuted,
                                  fontSize: 11)),
                          Expanded(
                            child: Text(s,
                                style: const TextStyle(
                                    color: BleTheme.textSecondary,
                                    fontSize: 11)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
