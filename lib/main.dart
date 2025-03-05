import 'dart:convert';
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:usb_serial/usb_serial.dart'; // For Android

void main() {
  runApp(SerialApp());
}

class SerialApp extends StatefulWidget {
  @override
  _SerialAppState createState() => _SerialAppState();
}

class _SerialAppState extends State<SerialApp> {
  SerialPort? port;
  UsbPort? usbPort;
  SerialPortReader? reader;
  List<Map<String, String>> records = [];
  List<String> availablePorts = [];
  String? selectedPort;
  String _buffer = "";
  String? recordsFilePath;
  bool isPortOpen = false;

  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>(); // ✅ Added ScaffoldMessenger Key

  @override
  void initState() {
    super.initState();
    requestUSBPermissions().then((v) {
      _initStorage();
      _refreshPorts();
    }); // ✅ Request USB permissions on startup
  }

  Future<void> _initStorage() async {
    Directory directory = await getApplicationDocumentsDirectory();
    recordsFilePath = '${directory.path}/records.json';
    _loadRecords();
  }

  Future<void> _loadRecords() async {
    if (recordsFilePath == null) return;
    File file = File(recordsFilePath!);

    if (await file.exists()) {
      String content = await file.readAsString();
      List<dynamic> decoded = jsonDecode(content);

      setState(() {
        records = decoded
            .map((item) => {
                  "name": item["name"].toString(),
                  "data": item["data"].toString()
                })
            .toList();
      });
    }
  }

  Future<void> _saveRecords() async {
    if (recordsFilePath == null) return;
    File file = File(recordsFilePath!);
    await file.writeAsString(jsonEncode(records));
  }

  Future<void> _refreshPorts() async {
    if (Platform.isAndroid) {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      setState(() {
        availablePorts = devices.map((device) => device.deviceName).toList();
        if (!availablePorts.contains(selectedPort)) {
          selectedPort =
              availablePorts.isNotEmpty ? availablePorts.first : null;
        }
      });
    } else {
      setState(() {
        availablePorts = SerialPort.availablePorts;
        if (!availablePorts.contains(selectedPort)) {
          selectedPort =
              availablePorts.isNotEmpty ? availablePorts.first : null;
        }
      });
    }
  }

  Future<void> _openPort() async {
    if (Platform.isAndroid) {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      UsbDevice? device = devices.isNotEmpty
          ? devices.firstWhere((d) => d.deviceName == selectedPort, orElse: () => devices.first)
          : null;

      if (device == null) {
        print("Error: USB device not found.");
        return;
      }

      usbPort = await device.create();
      if (await usbPort!.open()) {
        await usbPort!.setDTR(true);
        await usbPort!.setRTS(true);
        await usbPort!.setPortParameters(
            9600, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

        usbPort!.inputStream?.listen(_onDataReceived);

        print("Opened USB serial port: $selectedPort");
        setState(() {
          isPortOpen = true;
        });
      } else {
        print("Error: Failed to open USB port.");
      }
    } else {
      if (selectedPort == null || !availablePorts.contains(selectedPort)) {
        print("Error: Selected port is not available.");
        setState(() {
          isPortOpen = false;
        });
        return;
      }

      try {
        port = SerialPort(selectedPort!);

        if (!port!.openReadWrite()) {
          print("Error: Failed to open port $selectedPort.");
          setState(() {
            isPortOpen = false;
          });
          return;
        }

        port!.config = SerialPortConfig()
          ..baudRate = 9600
          ..bits = 8
          ..parity = SerialPortParity.none
          ..stopBits = 1;

        reader = SerialPortReader(port!);
        reader!.stream.listen(_onDataReceived);

        print("Opened port: $selectedPort");

        setState(() {
          isPortOpen = true;
        });
      } catch (e) {
        print("Exception opening port: $e");
        _closePort();
      }
    }
  }

  void _closePort() {
    if (Platform.isAndroid) {
      usbPort?.close();
    } else {
      if (port != null && port!.isOpen) {
        port!.close();
      }
    }
    print("Closed port: ${port!.name}");
    setState(() {
      port = null;
      isPortOpen = false;
    });
  }

  void _onDataReceived(Uint8List data) {
    String response = utf8.decode(data);
    _buffer += response;

    while (_buffer.contains("\n")) {
      int newlineIndex = _buffer.indexOf("\n");
      String completeMessage = _buffer.substring(0, newlineIndex).trim();
      _buffer = _buffer.substring(newlineIndex + 1);

      if (completeMessage.isNotEmpty) {
        print("Received: $completeMessage");

        // Check if the received command is already saved
        String? existingRecordName;
        for (var record in records) {
          if (record["data"] == completeMessage) {
            existingRecordName = record["name"];
            break;
          }
        }

        if (existingRecordName != null) {
          // ✅ Use GlobalKey to show SnackBar
          _scaffoldMessengerKey.currentState?.showSnackBar(
            SnackBar(
              content: Text("Already saved as: $existingRecordName"),
              duration: Duration(seconds: 2),
            ),
          );
        } else {
          // Save the new record if not already saved
          setState(() {
            records.add({
              "name": "Record ${records.length + 1}",
              "data": completeMessage
            });
          });
          _saveRecords();
        }
      }
    }
  }

  void _sendCommand(String command) {
    var isAndroid = Platform.isAndroid;
    if (isAndroid) {
      if (usbPort == null) {
        print("USB Serial port is closed.");
        return;
      }
    } else {
      if (port == null || !port!.isOpen) {
        print("Serial port is closed.");
        return;
      }
    }
    List<int> bytes = utf8.encode(command + "\n");
    if (isAndroid) {
      usbPort!.write(Uint8List.fromList(bytes));
    } else {
      port!.write(Uint8List.fromList(bytes));
    }
    print("Sent: $command");
  }

  void _renameRecord(int index, String newName) {
    setState(() {
      records[index]["name"] = newName;
    });
    _saveRecords();
  }

  void _deleteRecord(int index) {
    setState(() {
      records.removeAt(index);
    });
    _saveRecords();
  }

  void _resendData(String data) {
    _sendCommand(data);
  }

  Future<void> requestUSBPermissions() async {
    if (Platform.isAndroid) {
      await Permission.storage.request(); // Required for USB access
      await Permission.manageExternalStorage
          .request(); // Required on Android 10+
    }
    if (await Permission.storage.isGranted ||
        await Permission.manageExternalStorage.isGranted) {
      print("✅ USB Serial Communication Permissions Granted!");
    } else {
      print("❌ Permissions Denied. USB Serial Communication may not work.");
    }
  }

  @override
  void dispose() {
    _closePort();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: _scaffoldMessengerKey,
      // ✅ Assign ScaffoldMessenger Key
      home: Scaffold(
        appBar: AppBar(
          title: Text("RF Cloner"),
          actions: [
            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Icon(
                Icons.circle,
                color: isPortOpen ? Colors.green : Colors.grey,
                size: 16,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButton<String>(
                      isExpanded: true,
                      value: availablePorts.contains(selectedPort)
                          ? selectedPort
                          : null,
                      hint: Text("Select Serial Port"),
                      items: availablePorts.map((port) {
                        return DropdownMenuItem(
                          value: port,
                          child: Text(port),
                        );
                      }).toList(),
                      onChanged: availablePorts.isNotEmpty
                          ? (value) {
                              setState(() {
                                selectedPort = value;
                              });
                            }
                          : null,
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.refresh),
                    onPressed: _refreshPorts,
                  ),
                  ElevatedButton(
                    onPressed: _openPort,
                    child: Text("Open Port"),
                  ),
                  ElevatedButton(
                    onPressed: _closePort,
                    child: Text("Close Port"),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white30),
                  ),
                ],
              ),
            ),
            ElevatedButton(
              onPressed: isPortOpen ? () => _sendCommand("rec") : null,
              child: Text("Receive Hex Data"),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: records.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text(records[index]["name"]!),
                    subtitle: Text(records[index]["data"]!),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit),
                          onPressed: () {
                            TextEditingController controller =
                                TextEditingController(
                                    text: records[index]["name"]);
                            showDialog(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: Text("Rename Record"),
                                content: TextField(controller: controller),
                                actions: [
                                  TextButton(
                                    onPressed: () {
                                      _renameRecord(index, controller.text);
                                      Navigator.pop(context);
                                    },
                                    child: Text("Save"),
                                  )
                                ],
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: Icon(Icons.send),
                          color: isPortOpen ? Colors.blue : Colors.grey,
                          onPressed: isPortOpen
                              ? () => _resendData(records[index]["data"]!)
                              : null,
                        ),
                        IconButton(
                          icon: Icon(Icons.delete),
                          color: Colors.red,
                          onPressed: () => _deleteRecord(index),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
