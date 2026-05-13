import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Io

ShellRoot {
    IpcHandler {
        id: mkvStream
        target: "mkv-stream"

        function toggleVisibility() {
            if (window.visible) {
                window.visible = false
            } else {
                window.visible = true
                urlInput.forceActiveFocus()
            }
        }
    }

    component MatrixRain : Item {
        Canvas {
            id: canvas
            anchors.fill: parent
            property var drops: []
            property var chars: "ｦｱｳｴｵｶｷｸｹｺｻｼｽｾｿﾀﾂﾃﾅﾆﾇﾈﾊﾋﾎﾏﾐﾑﾒﾓﾔﾕﾗﾘﾜ0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ".split("")
            onPaint: {
                var ctx = getContext("2d");
                ctx.fillStyle = "rgba(10, 15, 10, 0.15)";
                ctx.fillRect(0, 0, width, height);
                ctx.fillStyle = "#b0ac63";
                ctx.font = "14px monospace";
                for (var i = 0; i < drops.length; i++) {
                    var text = chars[Math.floor(Math.random() * chars.length)];
                    ctx.fillText(text, i * 16, drops[i] * 14);
                    if (drops[i] * 14 > height && Math.random() > 0.975) drops[i] = 0;
                    drops[i]++;
                }
            }
            Timer { interval: 55; running: parent.visible; repeat: true; onTriggered: canvas.requestPaint() }
            Component.onCompleted: {
                var columnCount = Math.floor(canvas.width / 16) || 60;
                drops = new Array(columnCount);
                for (var x = 0; x < drops.length; x++) drops[x] = Math.random() * (canvas.height / 14);
            }
        }
    }

    property int barCount: 47
    property real currentVolume: 0.7
    property bool visualizerActive: false
    property var searchResults: []
    property int loadingTime: 0
    property bool isLoading: false

    function getCleanThumb(url, thumb) {
        if (!url) return "";
        let videoId = "";
        if (url.includes("v=")) videoId = url.split("v=")[1].split("&")[0];
        else if (url.includes("youtu.be/")) videoId = url.split("youtu.be/")[1].split("?")[0];
        if (videoId !== "") return "https://img.youtube.com/vi/" + videoId + "/mqdefault.jpg";
            return thumb;
    }

    PanelWindow {
        id: window // Ensure this ID matches the function above
        screen: Quickshell.screens[0]
        implicitWidth: 1080
        implicitHeight: 700
        visible: true
        margins.left: (screen.width - implicitWidth) / 2
        margins.top: (screen.height - implicitHeight) / 2
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        onVisibleChanged: if (visible) urlInput.forceActiveFocus();

        Rectangle {
            anchors.fill: parent
            color: "#282828"
            radius: 20
            border.color: "#ebdbb2"
            border.width: 3

            Rectangle {
                id: vizArea
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: controlsArea.top
                anchors.margins: 25
                color: "#0a0f0a"
                radius: 18
                border.color: "#504945"
                border.width: 2

                Row {
                    anchors.fill: parent
                    anchors.margins: 15
                    spacing: 0

                    ListView {
                        id: resultsList
                        width: parent.width * 0.5
                        height: parent.height
                        visible: searchResults.length > 0
                        model: searchResults
                        spacing: 12
                        clip: true
                        delegate: Rectangle {
                            id: resultItem
                            width: resultsList.width - 20
                            height: 100
                            color: resultMouse.pressed ? "#32302f" : "#1d2021"
                            radius: 8
                            border.color: "#b0ac63"

                            Row {
                                anchors.fill: parent;
                                anchors.margins: 10; spacing: 12
                                anchors.verticalCenterOffset: resultMouse.pressed ? 2 : 0

                                Image {
                                    id: thumb
                                    width: 120;
                                    height: parent.height - 20
                                    source: getCleanThumb(modelData.url, modelData.thumbnail)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    Rectangle { anchors.fill: parent; color: "#3c3836"; visible: thumb.status !== Image.Ready }
                                }
                                Column {
                                    width: parent.width - 145
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 4

                                    Text {
                                        width: parent.width
                                        text: modelData.title; color: "#ebdbb2"; font.pixelSize: 14;
                                        elide: Text.ElideRight; font.bold: true
                                    }

                                    TextEdit {
                                        width: parent.width
                                        text: modelData.url
                                        color: "#b0ac63"
                                        font.pixelSize: 11
                                        readOnly: true
                                        selectByMouse: true
                                        selectionColor: "#ebdbb2"
                                        selectedTextColor: "#282828"
                                    }

                                    Text { text: "Click to Play"; color: "#7c6f64"; font.pixelSize: 10; font.italic: true }
                                }
                            }
                            MouseArea {
                                id: resultMouse
                                anchors.fill: parent
                                propagateComposedEvents: true
                                onClicked: {
                                    playUrl(modelData.url);
                                    urlInput.text = modelData.url;
                                }
                            }
                        }
                    }

                    Item {
                        id: vizContainer
                        width: searchResults.length > 0 ? parent.width * 0.5 : parent.width
                        height: parent.height
                        MatrixRain { anchors.fill: parent; visible: !isLoading && !visualizerActive }
                        Column {
                            anchors.centerIn: parent; visible: isLoading; spacing: 5
                            Text { text: "Loading Song..."; color: "#ebdbb2"; font.pixelSize: 18; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                            Text { text: loadingTime + "s"; color: "#b0ac63"; font.pixelSize: 32; font.bold: true; anchors.horizontalCenter: parent.horizontalCenter }
                        }
                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter;
                            anchors.bottom: parent.bottom; anchors.bottomMargin: 10; spacing: 3
                            visible: visualizerActive && !isLoading
                            Repeater {
                                id: bars
                                model: barCount
                                Rectangle { width: 7; height: 0; color: "#b0ac63"; radius: 3; anchors.bottom: parent.bottom
                                    Behavior on height { NumberAnimation { duration: 50; easing.type: Easing.OutQuad } }
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                id: controlsArea
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 20
                width: parent.width; height: 210; color: "transparent"
                Column {
                    anchors.centerIn: parent; spacing: 18
                    Rectangle {
                        width: 720; height: 52; color: "#3c3836"; radius: 12; border.color: "#ebdbb2"; border.width: 2
                        Row {
                            anchors.fill: parent; anchors.margins: 16; spacing: 15
                            Text { text: "🔊"; color: "#ebdbb2"; font.pixelSize: 24; anchors.verticalCenter: parent.verticalCenter }
                            Slider {
                                id: volumeSlider; width: 520; anchors.verticalCenter: parent.verticalCenter
                                from: 0.0; to: 1.0; value: currentVolume; live: true
                                onValueChanged: if (Pipewire.defaultAudioSink?.audio) Pipewire.defaultAudioSink.audio.volume = value
                            }
                            Text {
                                text: Math.round(volumeSlider.value * 100) + "%"; color: "#ebdbb2"; font.pixelSize: 20; font.bold: true; width: 55; horizontalAlignment: Text.AlignRight;
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    Rectangle {
                        width: 720; height: 52; color: "#3c3836"; radius: 10; border.color: "#ebdbb2"; border.width: 2
                        TextInput { id: urlInput; anchors.fill: parent; anchors.margins: 14; verticalAlignment: Text.AlignVCenter; color: "#ebdbb2"; font.pixelSize: 21; onAccepted: handleInput(text) }
                    }
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter; spacing: 25
                        Rectangle {
                            id: searchBtn
                            width: 150; height: 50; radius: 10
                            color: searchMouse.pressed ? "#8f8b52" : "#b0ac63"
                            Text { anchors.centerIn: parent; text: "Search"; font.bold: true; font.pixelSize: 20; color: "#282828"; anchors.verticalCenterOffset: searchMouse.pressed ? 2 : 0 }
                            MouseArea { id: searchMouse; anchors.fill: parent; onClicked: handleInput(urlInput.text) }
                        }
                        Rectangle {
                            id: stopBtn
                            width: 150; height: 50; radius: 10
                            color: stopMouse.pressed ? "#cc241d" : "#fb4934"
                            Text { anchors.centerIn: parent; text: "STOP"; font.bold: true; font.pixelSize: 20; color: "#ebdbb2"; anchors.verticalCenterOffset: stopMouse.pressed ? 2 : 0 }
                            MouseArea { id: stopMouse; anchors.fill: parent; onClicked: { Quickshell.execDetached(["pkill", "-9", "-f", "mpv"]); visualizerActive = false; isLoading = false; } }
                        }
                    }
                }
            }
        }
    }

    Timer { id: countdown; interval: 1000; repeat: true; onTriggered: loadingTime++ }

    function handleInput(text) {
        let input = text.trim();
        if (input === "") return;
        if (input.startsWith("http") || input.includes("youtube.com") || input.includes("youtu.be")) {
            playUrl(input);
            findSimilar(input);
        } else {
            performSearch(input);
        }
        urlInput.text = "";
    }

    function playUrl(url) {
        if (!url) return;
        isLoading = true; loadingTime = 0; countdown.start();
        Quickshell.execDetached(["pkill", "-9", "-f", "mpv"]);
        processExtractor.command = ["yt-dlp", "-f", "ba/best", "-g", "--no-warnings", "--no-playlist", url];
        processExtractor.running = true;
    }

    function findSimilar(url) {
        titleFetcher.command = ["yt-dlp", "--get-title", "--no-warnings", url];
        titleFetcher.running = true;
    }

    Process { id: titleFetcher; stdout: StdioCollector { onStreamFinished: { let songTitle = this.text.trim(); if (songTitle !== "") performSearch(songTitle); } } }
    Process { id: processExtractor; stdout: StdioCollector { onStreamFinished: { let directUrl = this.text.trim(); if (directUrl.startsWith("http")) { Quickshell.execDetached(["mpv", "--no-video", "--force-window=no", directUrl]); visualizerActive = true; isLoading = false; countdown.stop(); } } } }

    Process {
        id: searchProcess
        stdout: StdioCollector {
            onStreamFinished: {
                let rawLines = this.text.trim().split("\n");
                let results = [];
                for (let line of rawLines) {
                    let parts = line.split(">>SEP<<");
                    if (parts.length >= 3) {
                        results.push({ title: parts[0].trim(), url: parts[1].trim(), thumbnail: parts[2].trim() });
                    }
                }
                searchResults = results;
            }
        }
    }

    function performSearch(query) {
        searchResults = [];
        searchProcess.command = ["yt-dlp", "--flat-playlist", "--print", "%(title)s>>SEP<<%(webpage_url)s>>SEP<<%(thumbnail)s", "ytsearch10:" + query];
        searchProcess.running = true;
    }

    PwObjectTracker { objects: Pipewire.defaultAudioSink ? [Pipewire.defaultAudioSink] : [] }
    PwNodePeakMonitor { id: peakMonitor; node: Pipewire.defaultAudioSink; enabled: visualizerActive }
    Timer {
        interval: 40; running: true; repeat: true
        onTriggered: {
            if (!visualizerActive || !bars || isLoading) return;
            let maxPeak = 0;
            if (peakMonitor.peaks.length > 0) for (let i = 0; i < peakMonitor.peaks.length; i++) if (peakMonitor.peaks[i] > maxPeak) maxPeak = peakMonitor.peaks[i];
            let volFactor = Math.max(0.45, currentVolume);
            for (let i = 0; i < bars.count; i++) {
                let bar = bars.itemAt(i);
                if (bar) bar.height = Math.min((maxPeak * 350 + Math.random() * 40) * volFactor, 280);
            }
        }
    }
}
