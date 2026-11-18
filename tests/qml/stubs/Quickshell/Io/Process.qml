import QtQml

// Test stand-in for Quickshell.Io.Process: records the command, never runs anything.
QtObject {
    property var command: []
    property bool running: false
    property QtObject stdout
    signal exited(int exitCode)
}
