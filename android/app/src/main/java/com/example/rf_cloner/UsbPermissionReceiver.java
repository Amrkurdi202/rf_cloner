package com.example.rf_cloner;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.hardware.usb.UsbDevice;
import android.hardware.usb.UsbManager;
import android.widget.Toast;

public class UsbPermissionReceiver extends BroadcastReceiver {
    @Override
    public void onReceive(Context context, Intent intent) {
        String action = intent.getAction();
        if ("com.example.rf_cloner.USB_PERMISSION".equals(action)) {
            UsbDevice device = intent.getParcelableExtra(UsbManager.EXTRA_DEVICE);
            if (device != null) {
                Toast.makeText(context, "USB Permission Granted for " + device.getDeviceName(), Toast.LENGTH_SHORT).show();
            } else {
                Toast.makeText(context, "USB Permission Denied", Toast.LENGTH_SHORT).show();
            }
        }
    }
}
