"""AegisOS CLI for local-first tasks and explicitly approved scans."""
import argparse
from .providers import route_task, local_status
from .service import request_service
from .auth import login, logout, get_tokens


def run_prompt(prompt: str) -> str:
    try:
        cloud_signed_in = bool(get_tokens())
    except Exception:
        cloud_signed_in = False
    route = route_task(prompt, cloud_signed_in=cloud_signed_in)
    result = request_service({"action": "run", "prompt": prompt, "route": route})
    return result["result"]


def main():
    parser = argparse.ArgumentParser(prog="aegis-agent")
    sub = parser.add_subparsers(dest="command", required=True)
    run = sub.add_parser("run", help="Run a private assistant task")
    run.add_argument("prompt", nargs="+")
    sub.add_parser("history", help="Show local task history")
    sub.add_parser("status", help="Show local model readiness")
    sub.add_parser("login", help="Sign in with ChatGPT plan usage")
    sub.add_parser("logout", help="Remove ChatGPT sign-in tokens")
    scan = sub.add_parser("scan", help="Run one authorized, in-scope security tool")
    scan.add_argument("--target", required=True, help="One hostname, IP, or CIDR under your control")
    scan.add_argument("--task", required=True, help="Describe the authorized test")
    scan.add_argument("--tool", required=True, choices=("nmap", "whatweb", "sslscan"))
    scan.add_argument("--option", action="append", default=[], help="One supported tool option; repeat as needed")
    investigate = sub.add_parser("investigate", help="Let the agent choose up to three in-scope tools")
    investigate.add_argument("--target", required=True)
    investigate.add_argument("--task", required=True)
    investigate.add_argument("--route", choices=("local", "lan"), default="local")
    args = parser.parse_args()
    if args.command == "history":
        for row in request_service({"action": "history"})["history"]: print(f"{row[0]:.0f} [{row[2]}] {row[1]}\n{row[3]}\n")
        return
    if args.command == "status":
        state = local_status()
        print(("Ready" if state["available"] else "Unavailable") + ": " + state["model"])
        return
    if args.command == "login":
        print("Signed in:", login())
        return
    if args.command == "logout":
        revoked = logout()
        print("ChatGPT credentials removed" + (" and access revoked" if revoked else "; remote revocation was not confirmed"))
        return
    if args.command == "scan":
        print(request_service({"action": "scan", "scope": {"target": args.target, "task": args.task},
                               "tool": args.tool, "args": args.option + [args.target]})["result"])
        return
    if args.command == "investigate":
        response = request_service({"action": "investigate", "scope": {"target": args.target,
                                   "task": args.task}, "route": args.route})
        for step in response["steps"]:
            print(f"\n{step['tool']} {' '.join(step['args'])}\n{step['output']}")
        print("\n" + response["summary"])
        return
    prompt = " ".join(args.prompt)
    print(run_prompt(prompt))


if __name__ == "__main__": main()
