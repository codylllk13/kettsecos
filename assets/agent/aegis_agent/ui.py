"""Minimal Qt task window for the local-first assistant."""
import sys
from PyQt5.QtWidgets import QApplication, QWidget, QVBoxLayout, QPlainTextEdit, QLineEdit, QPushButton, QLabel, QMessageBox, QComboBox
from .cli import run_prompt
from .providers import local_status
from .auth import login, logout, get_tokens
from .service import request_service


class AgentWindow(QWidget):
    def __init__(self):
        super().__init__()
        self.setWindowTitle("KettsecOS Security Assistant")
        self.setMinimumSize(760, 520)
        layout = QVBoxLayout(self)
        layout.addWidget(QLabel("Local-first AI · Matrix theme · User-space by default"))
        state = local_status()
        self.model_status = QLabel(("Local model ready: " if state["available"] else "Local model unavailable: ") + state["model"])
        layout.addWidget(self.model_status)
        self.cloud_button = QPushButton("Continue with ChatGPT")
        self.cloud_button.clicked.connect(self.connect_chatgpt)
        if get_tokens():
            self.cloud_button.setText("ChatGPT connected · sign out")
            self.cloud_button.clicked.disconnect()
            self.cloud_button.clicked.connect(self.disconnect_chatgpt)
        layout.addWidget(self.cloud_button)
        self.history = QPlainTextEdit(readOnly=True)
        self.history.setStyleSheet("background:#030805;color:#00ff41;font-family:monospace")
        layout.addWidget(self.history)
        self.input = QLineEdit()
        self.input.setPlaceholderText("Describe a task…")
        layout.addWidget(self.input)
        button = QPushButton("Run task")
        button.clicked.connect(self.run)
        layout.addWidget(button)
        layout.addWidget(QLabel("Authorized scan scope"))
        self.target = QLineEdit()
        self.target.setPlaceholderText("Target hostname, IP, CIDR, or URL")
        layout.addWidget(self.target)
        self.scope_task = QLineEdit()
        self.scope_task.setPlaceholderText("Task you are authorized to perform")
        layout.addWidget(self.scope_task)
        self.tool = QComboBox()
        self.tool.addItems(["nmap", "whatweb", "sslscan"])
        layout.addWidget(self.tool)
        scan_button = QPushButton("Review and approve scan")
        scan_button.clicked.connect(self.scan)
        layout.addWidget(scan_button)
        investigate_button = QPushButton("Investigate within this scope")
        investigate_button.clicked.connect(self.investigate)
        layout.addWidget(investigate_button)

    def run(self):
        prompt = self.input.text().strip()
        if not prompt: return
        state = local_status()
        self.model_status.setText(("Local model ready: " if state["available"] else "Local model unavailable: ") + state["model"])
        self.history.appendPlainText(f"You: {prompt}")
        self.input.clear()
        try:
            self.history.appendPlainText("Aegis: " + run_prompt(prompt))
        except Exception as exc: self.history.appendPlainText("Unavailable: " + str(exc))

    def connect_chatgpt(self):
        try:
            account = login()
            QMessageBox.information(self, "ChatGPT connected", f"Signed in as {account}. Each cloud task will show its exact prompt for approval.")
            self.cloud_button.setText("ChatGPT connected · sign out")
            self.cloud_button.clicked.disconnect()
            self.cloud_button.clicked.connect(self.disconnect_chatgpt)
        except Exception as exc:
            QMessageBox.warning(self, "ChatGPT sign-in failed", str(exc))

    def scan(self):
        target, task, tool = self.target.text().strip(), self.scope_task.text().strip(), self.tool.currentText()
        if not target or not task:
            QMessageBox.warning(self, "Scan scope required", "Enter the target and authorized task first.")
            return
        try:
            response = request_service({"action": "scan", "scope": {"target": target, "task": task}, "tool": tool, "args": [target]})
            self.history.appendPlainText("Scan output (untrusted data):\n" + response["result"])
        except Exception as exc:
            QMessageBox.warning(self, "Scan failed", str(exc))

    def investigate(self):
        target, task = self.target.text().strip(), self.scope_task.text().strip()
        if not target or not task:
            QMessageBox.warning(self, "Scan scope required", "Enter the target and authorized task first.")
            return
        try:
            response = request_service({"action": "investigate", "scope": {"target": target,
                                       "task": task}, "route": "local"})
            for step in response["steps"]:
                self.history.appendPlainText(f"{step['tool']} {' '.join(step['args'])}\n{step['output']}")
            self.history.appendPlainText("Aegis: " + response["summary"])
        except Exception as exc:
            QMessageBox.warning(self, "Investigation failed", str(exc))

    def disconnect_chatgpt(self):
        revoked = logout()
        QMessageBox.information(self, "ChatGPT signed out", "Local credentials removed." + (" Remote access revoked." if revoked else " Remote revocation was not confirmed."))
        self.cloud_button.setText("Continue with ChatGPT")
        self.cloud_button.clicked.disconnect()
        self.cloud_button.clicked.connect(self.connect_chatgpt)


def main():
    app = QApplication(sys.argv)
    window = AgentWindow()
    window.show()
    return app.exec_()


if __name__ == "__main__": raise SystemExit(main())
