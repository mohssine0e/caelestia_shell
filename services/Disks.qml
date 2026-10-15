pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import qs.services

Singleton {
    id: root

    property var drives: []
    readonly property bool hasRemovable: drives.length > 0
    readonly property int count: drives.length
    readonly property string primaryIcon: (drives.length > 0 && drives[0].icon) ? drives[0].icon : "usb"
    property bool isEjecting: false

    function refresh(): void {
        if (!listProc.running) {
            listProc.running = true;
        }
    }

    function eject(target): void {
        if (root.isEjecting) return;
        const drive = (typeof target === "object" && target !== null) ? target : drives.find(d => d.path === target || d.name === target);
        if (!drive) return;

        root.isEjecting = true;
        if (drive.type === "phone") {
            ejectProc.command = [
                "sh", "-c",
                "sync; gio mount -s mtp -f 2>&1; notify-send -a Storage -i phone 'Safe to Disconnect' '" + (drive.name || "Phone") + " safely unmounted.'"
            ];
        } else {
            const devPath = drive.path || "";
            ejectProc.command = [
                "sh", "-c",
                "sync; udisksctl unmount -b " + devPath + "* 2>/dev/null; udisksctl power-off -b " + devPath + " 2>/dev/null || eject " + devPath + " 2>/dev/null; notify-send -a Storage -i media-removable 'Safe to Remove' '" + (drive.name || "Device") + " can now be disconnected.'"
            ];
        }
        ejectProc.running = true;
    }

    function ejectAll(): void {
        if (!root.drives || root.drives.length === 0 || root.isEjecting) return;
        root.isEjecting = true;
        ejectProc.command = [
            "sh", "-c",
            "sync; gio mount -s mtp -f 2>/dev/null; for d in $(lsblk -rno PATH,TRAN,RM | awk '$2==\"usb\" || $3==\"1\"{print $1}'); do udisksctl unmount -b $d* 2>/dev/null; udisksctl power-off -b $d 2>/dev/null || eject $d 2>/dev/null; done; notify-send -a Storage -i media-removable 'Safe to Remove' 'All removable drives disconnected.'"
        ];
        ejectProc.running = true;
    }

    Process {
        id: listProc
        command: ["sh", "-c", "lsblk -J -o NAME,PATH,MODEL,SIZE,MOUNTPOINT,TRAN,RM,HOTPLUG,TYPE 2>/dev/null; echo '---GIO---'; gio mount -l 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.parseList(text);
            }
        }
    }

    function parseList(rawText) {
        if (!rawText) {
            root.drives = [];
            return;
        }

        const items = [];
        const parts = rawText.split("---GIO---");
        const jsonStr = parts[0] ? parts[0].trim() : "";
        const gioStr = parts[1] ? parts[1].trim() : "";

        // 1. Block devices from lsblk
        try {
            const data = JSON.parse(jsonStr);
            for (const dev of (data.blockdevices || [])) {
                if (dev.type !== "disk") continue;
                const tran = (dev.tran || "").toLowerCase();
                const rm = !!dev.rm || !!dev.hotplug;
                if (tran === "usb" || tran === "mmc" || rm) {
                    let isSystem = false;
                    let isMounted = !!dev.mountpoint;
                    const checkMount = (d) => {
                        if (d.mountpoint) isMounted = true;
                        if (d.mountpoint === "/" || d.mountpoint === "/efi" || d.mountpoint === "/boot") isSystem = true;
                        for (const c of (d.children || [])) checkMount(c);
                    };
                    checkMount(dev);
                    if (!isSystem) {
                        items.push({
                            name: (dev.model || dev.name || "USB Drive").trim(),
                            path: dev.path || ("/dev/" + dev.name),
                            size: dev.size || "",
                            icon: tran === "mmc" ? "sd_card" : "usb",
                            type: "disk",
                            is_mounted: isMounted
                        });
                    }
                }
            }
        } catch (e) {}

        // 2. Mobile phones / MTP from gio
        if (gioStr) {
            const lines = gioStr.split("\n");
            let lastVolume = "";
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i];
                const m = line.match(/^Volume\(\d+\):\s*(.+)/);
                if (m) {
                    lastVolume = m[1].trim();
                } else if (line.includes("GProxyVolumeMonitorMTP") && lastVolume) {
                    items.push({
                        name: lastVolume,
                        path: "mtp",
                        size: "Phone",
                        icon: "smartphone",
                        type: "phone",
                        is_mounted: true
                    });
                    lastVolume = "";
                }
            }
        }

        root.drives = items;
    }

    Process {
        id: ejectProc
        onExited: (code) => {
            root.isEjecting = false;
            root.refresh();
        }
    }

    // Direct system event monitoring using gio mount -o
    Process {
        id: monitorProc
        running: true
        command: ["gio", "mount", "-o"]
        stdout: SplitParser {
            onRead: data => {
                root.refresh();
            }
        }
        onExited: (code) => {
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        repeat: false
        onTriggered: {
            if (!monitorProc.running) {
                monitorProc.running = true;
            }
        }
    }

    // Lightweight periodic heartbeat
    Timer {
        interval: 3000
        repeat: true
        running: true
        onTriggered: root.refresh()
    }

    Component.onCompleted: {
        root.refresh();
    }
}
