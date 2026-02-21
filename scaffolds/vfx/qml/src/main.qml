import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    width: 640
    height: 480
    visible: true
    title: "${PROJECT_NAME} - VFX Platform"

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 20

        Text {
            text: "${PROJECT_NAME}"
            font.pixelSize: 32
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "USD Version: " + usdVersion
            font.pixelSize: 18
            color: "#666"
            Layout.alignment: Qt.AlignHCenter
        }

        Button {
            text: "DevEnv Ready"
            onClicked: console.log("Project ${PROJECT_NAME} is active")
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
