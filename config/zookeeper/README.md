# Zookeeper Upgrade Staging

This directory provides scaffolding for migrating the stack to an external Zookeeper ensemble. The files stay local and are ignored by the provisioning scripts until you supply real connection details.

## Files
- `zookeeper.env.example` — Template with placeholders for connection strings, chroot namespace, and optional TLS artifacts. Copy it to `~/<user>/peviitor/config/zookeeper.env` (the installers do this automatically) and update the values when the Zookeeper servers are ready.

## Next Steps
1. Confirm the Zookeeper ensemble endpoints and chroot path reserved for this stack.
2. Update the generated `zookeeper.env` file with the real endpoints, security flags, and certificates.
3. Extend the Solr bootstrap scripts to import these values (logic is pre-wired) and switch Solr to Cloud mode.

Until the connection details are supplied, Solr continues to run standalone, so the existing automation remains intact.
