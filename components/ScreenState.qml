import Quickshell

PersistentProperties {
    required property ShellScreen modelData

    // Drawer screen state
    property bool bar
    property bool osd
    property bool session
    property bool launcher
    property bool dashboard
    property bool utilities
    property bool sidebar
    property bool tasks

    // Dashboard state
    property int dashboardTab
    property date dashboardDate: new Date()
}
