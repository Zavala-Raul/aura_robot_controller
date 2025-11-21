import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

class RobotService {
  BluetoothConnection? _connection;
  bool get isConnected => _connection != null && _connection!.isConnected;

  // El comando actual de movimiento ('S' = Stop por defecto)
  String _currentMoveCommand = 'S'; 
  Timer? _heartbeatTimer;

  // Conectar al HC-06
  Future<bool> connectToDevice(String address) async {
    try {
      _connection = await BluetoothConnection.toAddress(address);
      _startHeartbeat(); // Inicia el latido en cuanto conecta
      return true;
    } catch (e) {
      print("Error conectando: $e");
      return false;
    }
  }

  void disconnect() {
    _heartbeatTimer?.cancel();
    _connection?.close();
    _connection = null;
  }

  // --- LÓGICA DEL CORAZÓN (HEARTBEAT) ---
  // Tu Arduino tiene un timeout de 500ms. 
  // Enviaremos el comando de movimiento cada 200ms para mantenerlo vivo.
  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(Duration(milliseconds: 200), (timer) {
      if (isConnected) {
        _sendRaw(_currentMoveCommand);
      }
    });
  }

  // --- COMANDOS PÚBLICOS ---

  // 1. Para Motores (Se repite automáticamente por el Heartbeat)
  // Usa: 'F', 'B', 'L', 'R', 'S'
  void setMoveCommand(String cmd) {
    _currentMoveCommand = cmd;
    // Opcional: enviar inmediatamente para respuesta instantánea
    if(isConnected) _sendRaw(cmd); 
  }

  // 2. Para el Brazo (Se envía UNA sola vez, no se repite)
  // Ejemplo: moverBrazo('a', 90) envía "a90"
  void moveArm(String eje, int angulo) {
    if (!isConnected) return;
    String command = "$eje$angulo\n"; // \n es vital para que tu Arduino sepa que terminó el numero
    _sendRaw(command);
  }

  // Función interna para enviar bytes
  void _sendRaw(String text) {
    try {
      _connection!.output.add(Uint8List.fromList(utf8.encode(text)));
      _connection!.output.allSent;
    } catch (e) {
      print("Error enviando: $e"); // Aquí sabrás si se desconectó
    }
  }
}