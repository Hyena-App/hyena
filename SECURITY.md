# Security

Hyena removes files, so bugs that could make it delete the wrong thing are treated as security issues. Examples: a path escaping its approved root, a symlink being followed, a protected folder being cleaned, or the snapshot command accepting unexpected input.

Please report them privately through GitHub's **Report a vulnerability** button on the Security tab of this repository, not in a public issue. Include steps to reproduce and the macOS version.

## Built-in guardrails

Every removal passes `SafetyPolicy` (`Sources/HyenaCore/Safety.swift`) immediately before it happens. It refuses system locations, credentials and app data, personal folders (except for project builds), anything outside the cleaning category's own folders, folders containing a Git repository, and permanent deletion of anything that can't regenerate. A way around any of these is a security issue.
