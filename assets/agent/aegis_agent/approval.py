"""Show approval requests from the task service, not from an untrusted client."""
import json
import os
import subprocess
import sys


def approve(kind: str, details: dict) -> bool:
    """Require a visible, local desktop confirmation for each new authority grant."""
    if kind not in {"scan", "investigate", "cloud"}:
        raise ValueError("Unknown approval kind")
    if not (os.environ.get("DISPLAY") or os.environ.get("WAYLAND_DISPLAY")):
        return False
    try:
        result = subprocess.run(
            [sys.executable, "-m", "aegis_agent.approval"],
            input=json.dumps({"kind": kind, "details": details}),
            text=True, capture_output=True, timeout=180, check=False,
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0


def main() -> int:
    from PyQt5.QtCore import Qt
    from PyQt5.QtWidgets import QApplication, QDialog, QDialogButtonBox, QLabel, QTextEdit, QVBoxLayout

    request = json.loads(sys.stdin.read(1_000_001))
    kind, details = request["kind"], request["details"]
    if kind == "cloud":
        title = "Approve this ChatGPT upload"
        explanation = "The exact text below will be sent to ChatGPT using your plan."
        content = details["prompt"]
    elif kind == "investigate":
        title = "Approve this active security task"
        explanation = "The agent may choose up to three allowed scan steps within this target and task."
        content = f"Target: {details['target']}\nTask: {details['task']}\nModel route: {details['route']}"
    elif kind == "scan":
        title = "Approve this active security scan"
        explanation = "This tool will run with your user permissions against the shown target."
        content = (f"Target: {details['target']}\nTask: {details['task']}\n"
                   f"Tool: {details['tool']}\nArguments: {json.dumps(details['args'])}")
    else:
        return 1

    app = QApplication(sys.argv)
    dialog = QDialog()
    dialog.setWindowTitle(title)
    dialog.resize(720, 420)
    layout = QVBoxLayout(dialog)
    label = QLabel(explanation)
    label.setTextFormat(Qt.PlainText)
    label.setWordWrap(True)
    layout.addWidget(label)
    preview = QTextEdit()
    preview.setReadOnly(True)
    preview.setPlainText(content)
    layout.addWidget(preview)
    buttons = QDialogButtonBox(QDialogButtonBox.Yes | QDialogButtonBox.No)
    buttons.button(QDialogButtonBox.No).setDefault(True)
    buttons.accepted.connect(dialog.accept)
    buttons.rejected.connect(dialog.reject)
    layout.addWidget(buttons)
    return 0 if dialog.exec_() == QDialog.Accepted else 1


if __name__ == "__main__":
    raise SystemExit(main())
