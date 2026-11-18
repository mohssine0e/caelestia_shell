pragma Singleton

import QtQml

// Test stand-in for the Quickshell singleton: no environment, fixed shell path.
QtObject {
    function env(name) {
        return "";
    }

    function shellPath(path) {
        return "/nonexistent/" + path;
    }
}
