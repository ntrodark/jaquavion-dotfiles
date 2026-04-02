import Quickshell
import QtQuick
import "./"

ShellRoot {

   Variants {
        model: Quickshell.screens.slice(0, 1)
        Sidebar { screen: modelData }
    }
}
