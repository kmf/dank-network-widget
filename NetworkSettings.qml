import QtQuick
import qs.Common
import qs.Modules.Plugins

PluginSettings {
    id: root
    pluginId: "networkSpeedWidget"

    StringSetting {
        settingKey: "selectedDevice"
        label: I18n.tr("Network Device")
        description: I18n.tr("Network interface to monitor (e.g., eth0, wlan0)")
        placeholder: "eth0"
        defaultValue: "eth0"
    }

    SelectionSetting {
        settingKey: "selectedBitrate"
        label: I18n.tr("Speed Unit")
        description: I18n.tr("Unit for displaying network speeds")
        options: [
            { label: "Kilobits per second (Kbps)", value: "Kbps" },
            { label: "Megabits per second (Mbps)", value: "Mbps" },
            { label: "Gigabits per second (Gbps)", value: "Gbps" }
        ]
        defaultValue: "Mbps"
    }

    SliderSetting {
        settingKey: "backgroundOpacity"
        label: I18n.tr("Background Opacity")
        defaultValue: 80
        minimum: 0
        maximum: 100
        unit: "%"
    }
}
