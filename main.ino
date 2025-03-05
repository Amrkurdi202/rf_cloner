#define SUPPRESS_ERROR_MESSAGE_FOR_BEGIN
#define NO_LED_FEEDBACK  // Disable LED feedback
#define NO_PRINT         // Disable any printing from IRremote
#include <IRremote.h>

#define IR_RECEIVE_PIN 2  // Receiver Pin
#define IR_SEND_PIN 3     // Transmitter Pin

uint16_t address = 0;
uint16_t command = 0;
bool recordMode = true;  // Starts in record mode
bool newSignal = false;  // Flag to indicate a new IR signal was received

void setup() {
  Serial.begin(9600);

  IrReceiver.begin(IR_RECEIVE_PIN, ENABLE_LED_FEEDBACK);                          
  IrSender.begin(IR_SEND_PIN, ENABLE_LED_FEEDBACK, USE_DEFAULT_FEEDBACK_LED_PIN);
}

void loop() {
  // Check for serial input
  if (Serial.available() > 0) {
    String input = Serial.readStringUntil('\n');
    input.trim();

    if (input.equalsIgnoreCase("rec")) {
      recordMode = true;
    } else {
      recordMode = false;

      // Try to parse address and command
      int splitIndex = input.indexOf(' '); // Expecting "AABB CCDD" (Hex format)
      if (splitIndex != -1) {
        String addressStr = input.substring(0, splitIndex);
        String commandStr = input.substring(splitIndex + 1);

        address = strtol(addressStr.c_str(), NULL, 16);
        command = strtol(commandStr.c_str(), NULL, 16);

        IrSender.sendNEC(address, command, 2);  // Send NEC signal
      }
    }
  }

  // IR Receiver logic (Recording mode)
  if (recordMode) {
    if (IrReceiver.decode()) {
      if (IrReceiver.decodedIRData.protocol == NEC) {
        uint16_t newAddress = IrReceiver.decodedIRData.address;
        uint16_t newCommand = IrReceiver.decodedIRData.command;

        // Only update and send if it's a new signal
        if (newAddress != address || newCommand != command) {
          address = newAddress;
          command = newCommand;
          newSignal = true;
        }
      }
      IrReceiver.resume();  // Get ready for next signal
    }
  }

  // Send IR data once when a new signal is received
  if (newSignal) {
    Serial.print(address, HEX);
    Serial.print(" ");
    Serial.println(command, HEX);
    newSignal = false; // Prevent duplicate sending
  }
}//
