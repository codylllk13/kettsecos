import QtQuick 2.0;
import calamares.slideshow 1.0;

Presentation {
    id: presentation

    Timer {
        interval: 12000
        repeat: true
        onTriggered: presentation.goToNextSlide()
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#030805"
            Image {
                source: "logo.svg"
                width: 220
                height: 220
                fillMode: Image.PreserveAspectFit
                anchors.centerIn: parent
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#030805"
            Column {
                anchors.centerIn: parent
                spacing: 18
                Text {
                    text: "KETTSECOS"
                    color: "#00ff41"
                    font.pixelSize: 34
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "A Matrix-inspired security workstation"
                    color: "#d8ffe0"
                    font.pixelSize: 20
                    anchors.horizontalCenter: parent.horizontalCenter
                }
            }
        }
    }

    Slide {
        Rectangle {
            anchors.fill: parent
            color: "#030805"
            Column {
                anchors.centerIn: parent
                spacing: 18
                Text {
                    text: "YOUR SECURITY TOOLKIT"
                    color: "#00ff41"
                    font.pixelSize: 30
                    font.bold: true
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Text {
                    text: "Parrot Security Edition tools, KDE Plasma, and privacy-focused browsers."
                    color: "#d8ffe0"
                    font.pixelSize: 18
                    wrapMode: Text.WordWrap
                    width: 600
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }
    }
}
