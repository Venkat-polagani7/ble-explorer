import 'dart:async';
import 'package:nordic_dfu/nordic_dfu.dart';
import 'ble_log_service.dart';

enum DfuState { idle, starting, uploading, validating, completed, error, aborted }

class DfuService {
  final BleLogService logService;
  
  DfuState _state = DfuState.idle;
  int _progress = 0;
  String? _error;
  
  DfuState get state => _state;
  int get progress => _progress;
  String? get error => _error;

  final _updateController = StreamController<DfuState>.broadcast();
  Stream<DfuState> get updates => _updateController.stream;

  DfuService(this.logService);

  void _setState(DfuState newState) {
    _state = newState;
    _updateController.add(newState);
  }

  Future<void> startDfu(String deviceId, String filePath) async {
    if (_state != DfuState.idle && _state != DfuState.completed && _state != DfuState.error && _state != DfuState.aborted) {
      logService.warning('DFU already in progress', tag: 'DFU');
      return;
    }

    _progress = 0;
    _error = null;
    _setState(DfuState.starting);
    logService.info('Starting DFU on $deviceId using $filePath', tag: 'DFU');

    try {
      await NordicDfu().startDfu(
        deviceId,
        filePath,
        fileInAsset: false,
        dfuEventHandler: DfuEventHandler(
          onDeviceDisconnecting: (mac) {
            logService.info('DFU: Device disconnecting ($mac)', tag: 'DFU');
          },
          onProgressChanged: (deviceAddress, percent, speed, avgSpeed, currentPart, partsTotal) {
            _progress = percent;
            if (_state != DfuState.uploading) _setState(DfuState.uploading);
            _updateController.add(_state); // Push progress
          },
          onDfuProcessStarting: (mac) {
            _setState(DfuState.starting);
          },
          onEnablingDfuMode: (mac) {
            logService.info('DFU: Enabling DFU mode ($mac)', tag: 'DFU');
          },
          onFirmwareValidating: (mac) {
            _setState(DfuState.validating);
            logService.info('DFU: Validating firmware ($mac)', tag: 'DFU');
          },
          onDfuCompleted: (mac) {
            _setState(DfuState.completed);
            logService.success('DFU completed successfully! ($mac)', tag: 'DFU');
          },
          onDfuAborted: (mac) {
            _setState(DfuState.aborted);
            logService.warning('DFU aborted ($mac)', tag: 'DFU');
          },
          onError: (mac, code, type, message) {
            _error = 'Code $code: $message';
            _setState(DfuState.error);
            logService.error('DFU error: $_error ($mac)', tag: 'DFU');
          },
        ),
      );
    } catch (e) {
      _error = e.toString();
      _setState(DfuState.error);
      logService.error('DFU threw exception: $e', tag: 'DFU');
    }
  }

  Future<void> abortDfu() async {
    try {
      await NordicDfu().abortDfu();
      _setState(DfuState.aborted);
      logService.warning('DFU manually aborted', tag: 'DFU');
    } catch (e) {
      logService.error('Failed to abort DFU: $e', tag: 'DFU');
    }
  }

  void reset() {
    _state = DfuState.idle;
    _progress = 0;
    _error = null;
    _updateController.add(_state);
  }

  void dispose() {
    _updateController.close();
  }
}
