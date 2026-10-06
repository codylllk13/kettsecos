"""Explicit scope checks for user-approved active security tasks."""
from dataclasses import dataclass
import ipaddress
import re
from urllib.parse import urlsplit


@dataclass(frozen=True)
class Scope:
    target: str
    task: str
    approved: bool = False

    def permits(self, candidate: str) -> bool:
        if not self.approved or not self.target.strip() or not self.task.strip() or not candidate or any(c in candidate for c in "\n\r\x00"):
            return False
        target = self.target.strip()
        candidate = candidate.strip()
        if target.startswith(("http://", "https://")):
            try:
                a, b = urlsplit(target), urlsplit(candidate if "://" in candidate else "https://" + candidate)
                if (b.scheme not in {"http", "https"} or a.username or a.password or
                    b.username or b.password or a.query or a.fragment or b.query or b.fragment or
                    not a.hostname or not b.hostname):
                    return False
                # Reject path forms that a browser or server could normalize outside
                # the approved subtree (including encoded traversal and backslashes).
                if any("%" in path or "\\" in path or
                       any(segment in {".", ".."} for segment in path.split("/"))
                       for path in (a.path, b.path)):
                    return False
                base_path = a.path.rstrip("/")
                path_ok = b.path == base_path or b.path.startswith(base_path + "/") if base_path else True
                default_port = 443 if a.scheme == "https" else 80
                return (a.scheme == b.scheme and a.hostname == b.hostname and
                        (a.port if a.port is not None else default_port) ==
                        (b.port if b.port is not None else default_port) and path_ok)
            except ValueError:
                return False
        try:
            network = ipaddress.ip_network(target, strict=False)
            try:
                candidate_network = ipaddress.ip_network(candidate, strict=False)
                return candidate_network.subnet_of(network)
            except ValueError:
                return ipaddress.ip_address(candidate) in network
        except ValueError:
            hostname = re.compile(r"(?=.{1,253}$)[A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?\Z")
            return bool(hostname.fullmatch(target) and hostname.fullmatch(candidate) and candidate.lower().rstrip(".") == target.lower().rstrip("."))


def validate_tool_args(tool: str, args: list[str], scope: Scope) -> None:
    """Accept a small allowlist of user-space tools and enforce approved targets."""
    allowed = {"nmap", "whatweb", "sslscan"}
    if tool not in allowed:
        raise PermissionError(f"Tool is not in the AegisOS user-space allowlist: {tool}")
    if not scope.approved:
        raise PermissionError("Active tools require approval of a target and task")
    if not args or any(not isinstance(a, str) or "\x00" in a or "\n" in a or "\r" in a for a in args):
        raise PermissionError("Invalid tool arguments")
    if tool == "nmap" and any("://" in a for a in args):
        raise PermissionError("nmap requires an approved hostname, IP address, or CIDR")
    if tool == "nmap":
        allowed_flags = {"-sV", "-sT", "-Pn", "-T2", "-T3", "--reason", "--open"}
        pending_port = False
        targets = []
        for arg in args:
            if pending_port:
                if not re.fullmatch(r"[0-9,-]+", arg): raise PermissionError("Invalid port selection")
                pending_port = False
            elif arg == "-p": pending_port = True
            elif arg.startswith("-p") and re.fullmatch(r"-p[0-9,-]+", arg): pass
            elif arg.startswith("-"):
                if arg not in allowed_flags: raise PermissionError("This nmap option is outside the approved task boundary")
            else: targets.append(arg)
        if pending_port: raise PermissionError("Missing port selection")
    else:
        targets = [a for a in args if not a.startswith("-")]
        if any(a.startswith("-") and a not in {"--no-colour", "--no-errors"} for a in args):
            raise PermissionError("This tool option is outside the approved task boundary")
    if len(targets) != 1 or not scope.permits(targets[0]):
        raise PermissionError("Every active scan must name a target inside the approved scope")
