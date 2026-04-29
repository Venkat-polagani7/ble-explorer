import re

with open('lib/screens/tabs/ble_scanner_tab.dart', 'r') as f:
    content = f.read()

# find _DeviceCardState class
start = content.find('class _DeviceCardState extends State<_DeviceCard>')
end = content.find('  @override\n  Widget build(BuildContext context) {')

old_code = content[start:end]

new_code = '''class _DeviceCardState extends State<_DeviceCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;
  late final AnimationController _animCtrl;
  late final Animation<double> _expandAnim;

  StreamSubscription<BluetoothConnectionState>? _connSub;
  BluetoothConnectionState _connState = BluetoothConnectionState.disconnected;

  // --- Real-time Monitoring ---
  final List<FlSpot> _rssiHistory = [];
  final List<FlSpot> _throughputHistory = [];
  int _bytesSinceLastCheck = 0;
  Timer? _metricsTimer;
  double _elapsedSeconds = 0;
  static const int _maxDataPoints = 60; // 1 minute at 1Hz

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 200));
    _expandAnim = CurvedAnimation(parent: _animCtrl, curve: Curves.easeInOut);
        
    if (widget.result.device.isConnected) {
      _connState = BluetoothConnectionState.connected;
      _startMetricsTimer();
    }
        
    _connSub = widget.result.device.connectionState.listen((s) {
      if (mounted) {
        setState(() => _connState = s);
        if (s == BluetoothConnectionState.connected) {
          _startMetricsTimer();
        } else {
          _stopMetricsTimer();
        }
      }
    });
  }

  void _startMetricsTimer() {
    _stopMetricsTimer();
    _metricsTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      if (!mounted || _connState != BluetoothConnectionState.connected) return;
      _elapsedSeconds++;
      
      try {
        final rssi = await widget.result.device.readRssi();
        if (mounted) {
          setState(() {
            _rssiHistory.add(FlSpot(_elapsedSeconds, rssi.toDouble()));
            if (_rssiHistory.length > _maxDataPoints) _rssiHistory.removeAt(0);
          });
        }
      } catch (_) {}

      if (mounted) {
        setState(() {
          _throughputHistory.add(FlSpot(_elapsedSeconds, _bytesSinceLastCheck.toDouble()));
          if (_throughputHistory.length > _maxDataPoints) _throughputHistory.removeAt(0);
          _bytesSinceLastCheck = 0;
        });
      }
    });
  }

  void _stopMetricsTimer() {
    _metricsTimer?.cancel();
    _metricsTimer = null;
  }

  @override
  void dispose() {
    _connSub?.cancel();
    _stopMetricsTimer();
    _animCtrl.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _animCtrl.forward();
    } else {
      _animCtrl.reverse();
    }
  }

  String get _name {
    final r = widget.result;
    if (r.device.platformName.isNotEmpty) return r.device.platformName;
    if (r.device.advName.isNotEmpty) return r.device.advName;
    if (r.advertisementData.advName.isNotEmpty) return r.advertisementData.advName;
    return 'Unknown Device';
  }

  String get _remoteId => widget.result.device.remoteId.toString();
  bool get _isUnknown => _name == 'Unknown Device';

  Color get _iconColor {
    if (_isUnknown && !widget.result.advertisementData.connectable) {
      return BleTheme.textMuted;
    }
    final colors = [
      BleTheme.accent, BleTheme.accentGreen, BleTheme.accentSecondary,
      Colors.pinkAccent, Colors.cyan, Colors.teal, Colors.amber.shade600, Colors.indigoAccent,
    ];
    final hash = _remoteId.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  IconData get _icon {
    final adv = widget.result.advertisementData;
    final uuids = adv.serviceUuids.map((u) => u.toString().toLowerCase()).toList();
    if (uuids.any((u) => u.contains('180d'))) return Icons.favorite_rounded;
    if (uuids.any((u) => u.contains('1812'))) return Icons.keyboard_rounded;
    if (uuids.any((u) => u.contains('180f'))) return Icons.battery_full_rounded;
    return Icons.bluetooth_rounded;
  }

'''

content = content.replace(old_code, new_code)

with open('lib/screens/tabs/ble_scanner_tab.dart', 'w') as f:
    f.write(content)

print("done")
