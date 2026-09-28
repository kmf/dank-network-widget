import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins

DesktopPluginComponent {
    id: root

    // Sparkline drawn behind a tile's label, in the style of the builtin
    // System Monitor widget: gradient area plus a brighter trace on top.
    component SpeedGraph: Canvas {
        id: graph

        property var series: []
        property real maxValue: 1
        property color traceColor: Theme.primary
        property real cornerRadius: 0
        property real headroom: 0.6

        onHeadroomChanged: requestPaint()

        renderStrategy: Canvas.Cooperative

        onSeriesChanged: requestPaint()
        onMaxValueChanged: requestPaint()
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)
            if (!series || series.length < 2)
                return

            ctx.beginPath()
            ctx.roundedRect(0, 0, width, height, cornerRadius, cornerRadius)
            ctx.clip()

            // Always plot against a full window so the trace scrolls in from
            // the right rather than stretching while history fills up.
            var step = width / (root.historySize - 1)
            var offset = width - step * (series.length - 1)
            // Peaks stop short of the top so the trace stays under the labels.
            var scale = height * headroom / maxValue

            var grad = ctx.createLinearGradient(0, 0, 0, height)
            grad.addColorStop(0, Theme.withAlpha(traceColor, 0.22))
            grad.addColorStop(1, Theme.withAlpha(traceColor, 0.04))

            ctx.fillStyle = grad
            ctx.beginPath()
            ctx.moveTo(offset, height)
            for (var i = 0; i < series.length; i++)
                ctx.lineTo(offset + step * i, height - series[i] * scale)
            ctx.lineTo(offset + step * (series.length - 1), height)
            ctx.closePath()
            ctx.fill()

            ctx.strokeStyle = Theme.withAlpha(traceColor, 0.5)
            ctx.lineWidth = 1.5
            ctx.beginPath()
            for (var j = 0; j < series.length; j++) {
                var x = offset + step * j
                var y = height - series[j] * scale
                j === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
            }
            ctx.stroke()
        }
    }

    minWidth: 280
    minHeight: 180

    property string selectedDevice: pluginData.selectedDevice ?? "eth0"
    property string selectedBitrate: pluginData.selectedBitrate ?? "Mbps"
    property real backgroundOpacity: (pluginData.backgroundOpacity ?? 80) / 100

    property real downloadSpeed: 0
    property real uploadSpeed: 0
    property var availableDevices: []
    property real prevRxBytes: 0
    property real prevTxBytes: 0

    // One sample per second, so this is a rolling 60s window.
    readonly property int historySize: 60
    property var rxHistory: []
    property var txHistory: []

    // Both graphs share a scale so download and upload stay visually comparable.
    readonly property real graphMax: {
        var peak = 0
        for (var i = 0; i < rxHistory.length; i++)
            peak = Math.max(peak, rxHistory[i])
        for (var j = 0; j < txHistory.length; j++)
            peak = Math.max(peak, txHistory[j])
        return peak > 0 ? peak : 1
    }

    function pushHistory(history, value) {
        var next = history.slice()
        next.push(value)
        if (next.length > root.historySize)
            next.shift()
        return next
    }

    function resetHistory() {
        root.rxHistory = []
        root.txHistory = []
        root.prevRxBytes = 0
        root.prevTxBytes = 0
        root.downloadSpeed = 0
        root.uploadSpeed = 0
    }

    // Samples are stored in the display unit, so a unit switch invalidates them.
    onSelectedBitrateChanged: resetHistory()

    readonly property color bgColor: Theme.withAlpha(Theme.surface, backgroundOpacity)
    readonly property color tileBg: Theme.withAlpha(Theme.surfaceContainerHigh, backgroundOpacity)

    Timer {
        id: refreshTimer
        interval: 1000
        running: true
        repeat: true
        onTriggered: updateNetworkStats()
    }

    function updateNetworkStats() {
        statsProcess.running = true
    }

    Process {
        id: statsProcess
        command: ["cat", "/proc/net/dev"]
        stdout: SplitParser {
            onRead: line => {
                var parts = line.trim().split(/\s+/)
                if (parts[0] === root.selectedDevice + ":") {
                    var rxBytes = parseInt(parts[1]) || 0
                    var txBytes = parseInt(parts[9]) || 0

                    if (root.prevRxBytes > 0) {
                        var rxDelta = Math.max(0, rxBytes - root.prevRxBytes)
                        var txDelta = Math.max(0, txBytes - root.prevTxBytes)

                        if (root.selectedBitrate === "Mbps") {
                            root.downloadSpeed = (rxDelta * 8) / 1000000
                            root.uploadSpeed = (txDelta * 8) / 1000000
                        } else if (root.selectedBitrate === "Kbps") {
                            root.downloadSpeed = (rxDelta * 8) / 1000
                            root.uploadSpeed = (txDelta * 8) / 1000
                        } else {
                            root.downloadSpeed = (rxDelta * 8) / 1000000000
                            root.uploadSpeed = (txDelta * 8) / 1000000000
                        }

                        root.rxHistory = root.pushHistory(root.rxHistory, root.downloadSpeed)
                        root.txHistory = root.pushHistory(root.txHistory, root.uploadSpeed)
                    }

                    root.prevRxBytes = rxBytes
                    root.prevTxBytes = txBytes
                }
            }
        }
    }

    function loadAvailableDevices() {
        devicesProcess.pending = []
        devicesProcess.running = true
    }

    function selectDevice(device) {
        if (!device || device === root.selectedDevice)
            return
        root.selectedDevice = device
        resetHistory()
        setData("selectedDevice", device)
    }

    Process {
        id: devicesProcess
        command: ["ls", "/sys/class/net"]

        property var pending: []

        stdout: SplitParser {
            onRead: line => {
                var device = line.trim()
                if (device && !devicesProcess.pending.includes(device)) {
                    devicesProcess.pending = devicesProcess.pending.concat([device])
                }
            }
        }
        onExited: {
            root.availableDevices = devicesProcess.pending.slice().sort()
        }
    }

    // Interfaces come and go (VPNs, docks, USB tethering), so rescan periodically.
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: loadAvailableDevices()
    }

    // Trigger and popup are sized from the widest name so nothing is elided.
    readonly property int deviceFieldWidth: Math.ceil(deviceMetrics.width) + 64

    TextMetrics {
        id: deviceMetrics

        font.pixelSize: Theme.fontSizeMedium
        text: {
            var longest = root.selectedDevice
            for (var i = 0; i < root.availableDevices.length; i++) {
                if (root.availableDevices[i].length > longest.length)
                    longest = root.availableDevices[i]
            }
            return longest
        }
    }

    Component.onCompleted: {
        loadAvailableDevices()
    }

    Rectangle {
        anchors.fill: parent
        radius: Theme.cornerRadius
        color: root.bgColor

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Theme.spacingM
            spacing: Theme.spacingS

            // Header row with device and unit selectors
            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingS

                DankDropdown {
                    Layout.preferredWidth: dropdownWidth
                    Layout.preferredHeight: 40

                    // Fit the widest interface name where the widget allows it;
                    // the popup is a separate surface, so it always shows names in full.
                    dropdownWidth: Math.max(100, Math.min(root.deviceFieldWidth, root.width - Theme.spacingM * 2 - unitLabel.implicitWidth - Theme.spacingS))
                    popupWidth: root.deviceFieldWidth
                    options: root.availableDevices
                    currentValue: root.selectedDevice
                    emptyText: I18n.tr("No devices")
                    enableFuzzySearch: root.availableDevices.length > 8
                    onValueChanged: value => root.selectDevice(value)
                }

                Item { Layout.fillWidth: true }

                StyledText {
                    id: unitLabel

                    text: root.selectedBitrate
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }

            // Download section
            Rectangle {
                id: downloadTile

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.cornerRadius
                color: root.tileBg

                SpeedGraph {
                    anchors.fill: parent
                    series: root.rxHistory
                    maxValue: root.graphMax
                    traceColor: Theme.primary
                    cornerRadius: downloadTile.radius
                }

                // Fades the graph out behind the labels so they stay readable
                // whatever the trace is doing.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.min(parent.width, Theme.spacingS * 2 + Theme.iconSize + downloadLabels.implicitWidth + Theme.spacingL)
                    radius: parent.radius

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, root.backgroundOpacity)
                        }
                        GradientStop {
                            position: 0.7
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, root.backgroundOpacity * 0.9)
                        }
                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "download"
                        size: Theme.iconSize
                        color: Theme.primary
                    }

                    ColumnLayout {
                        id: downloadLabels

                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Download"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: root.downloadSpeed.toFixed(2) + " " + root.selectedBitrate
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.primary
                        }
                    }
                }
            }

            // Upload section
            Rectangle {
                id: uploadTile

                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: Theme.cornerRadius
                color: root.tileBg

                SpeedGraph {
                    anchors.fill: parent
                    series: root.txHistory
                    maxValue: root.graphMax
                    traceColor: Theme.secondary
                    cornerRadius: uploadTile.radius
                }

                // Fades the graph out behind the labels so they stay readable
                // whatever the trace is doing.
                Rectangle {
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: Math.min(parent.width, Theme.spacingS * 2 + Theme.iconSize + uploadLabels.implicitWidth + Theme.spacingL)
                    radius: parent.radius

                    gradient: Gradient {
                        orientation: Gradient.Horizontal

                        GradientStop {
                            position: 0
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, root.backgroundOpacity)
                        }
                        GradientStop {
                            position: 0.7
                            color: Theme.withAlpha(Theme.surfaceContainerHigh, root.backgroundOpacity * 0.9)
                        }
                        GradientStop {
                            position: 1
                            color: "transparent"
                        }
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingS
                    spacing: Theme.spacingS

                    DankIcon {
                        name: "upload"
                        size: Theme.iconSize
                        color: Theme.secondary
                    }

                    ColumnLayout {
                        id: uploadLabels

                        Layout.fillWidth: true
                        spacing: 2

                        StyledText {
                            text: "Upload"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            text: root.uploadSpeed.toFixed(2) + " " + root.selectedBitrate
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: Theme.secondary
                        }
                    }
                }
            }
        }
    }
}
