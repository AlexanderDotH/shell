pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls

StyledTextField {
    id: root

    property bool first: false
    property string label
    property bool password: false
    property string placeholder
    property bool trimValue: true

    signal committed(string value)

    function commit(): void {
        const value = root.trimValue ? root.text.trim() : root.text;
        root.committed(value);
    }

    Layout.fillWidth: true
    Layout.topMargin: first ? 0 : Tokens.spacing.extraSmall
    echoMode: root.password ? TextInput.Password : TextInput.Normal
    placeholderText: root.label
    supportingText: root.placeholder

    onEditingFinished: root.commit()
}
