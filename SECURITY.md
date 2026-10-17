# Security

Hyena removes files, so bugs that could make it delete the wrong thing are treated as security issues. Examples: a path escaping its approved root, a symlink being followed, a protected folder being cleaned, or the snapshot command accepting unexpected input.

Please report them privately through GitHub's **Report a vulnerability** button on the Security tab of this repository, not in a public issue. Include steps to reproduce and the macOS version.
