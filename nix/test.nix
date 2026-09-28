{ pkgs, module, package }:

pkgs.testers.runNixOSTest {
  name = "gmux-serve-agent";

  defaults = {
    imports = [ module ];
    services.gmux.package = package;
  };

  nodes.central = {
    networking.firewall.allowedTCPPorts = [ 8088 ];
    services.gmux.serve = {
      enable = true;
      web = "0.0.0.0:8088";
      settings.users = [
        {
          name = "alice";
          admin = true;
          tokens = [ "alicetest" ];
        }
      ];
    };
  };

  nodes.agent = {
    services.gmux.agent = {
      enable = true;
      name = "vm-agent";
      url = "ws://central:8088/api/agent/ws";
      tokenFile = "/run/gmux-agent-token";
      insecureTransport = true;
    };
  };

  testScript = ''
    import json

    central.wait_for_unit("gmux.service")
    central.wait_for_open_port(8088)
    api = "http://127.0.0.1:8088/api/agent-tokens?token=alicetest"
    minted = json.loads(central.succeed(
        f"curl -fsS -X POST -H 'Content-Type: application/json' -d '{{\"name\":\"vm-agent\"}}' '{api}'"
    ))
    status, out = central.execute("gmux upgrade 2>&1")
    assert status != 0 and "installed by nix" in out.lower(), f"upgrade under Nix: {status} {out!r}"
    bundle = central.succeed("curl -fsS http://127.0.0.1:8088/api/agent/bundle | tar -tz | sort").split()
    expected = sorted(
        "agent-binaries/gmux-" + t.replace("/", "-") + (".exe" if t.startswith("windows/") else "")
        for t in ${builtins.toJSON package.releaseTargets}
    )
    assert bundle == expected, f"bundle {bundle} != {expected}"

    agent.wait_for_unit("multi-user.target")
    agent.succeed(f"printf %s '{minted['token']}' > /run/gmux-agent-token && chmod 0400 /run/gmux-agent-token")
    agent.systemctl("restart gmux-agent.service")
    agent.wait_for_unit("gmux-agent.service")

    def online(_):
        tokens = json.loads(central.succeed(f"curl -fsS '{api}'"))["tokens"]
        return any(t["name"] == "vm-agent" and t["online"] for t in tokens)

    retry(online, timeout_seconds=60)
    agent.succeed("journalctl -u gmux-agent.service -o cat | grep -q 'agent-link: connected'")
  '';
}
