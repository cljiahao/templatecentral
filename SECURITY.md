# Security Policy

## Supported Versions

| Version | Supported           |
|---------|---------------------|
| 5.x     | Yes                 |
| 4.x     | Security fixes only |
| < 4.0   | No                  |

## Reporting a Vulnerability

**Do not open a public GitHub issue for security vulnerabilities.**

Report privately via [GitHub Security Advisories](https://github.com/cljiahao/templatecentral/security/advisories/new).

Include:
- Description of the vulnerability
- Steps to reproduce
- Affected versions
- Suggested fix (if known)

**Response timeline:** acknowledgement within 48 hours; fix or mitigation within 14 days for confirmed issues.

## Scope

templateCentral generates code. Insecure patterns in skill output (hardcoded secrets, missing auth, injection vectors) are in scope. Vulnerabilities in dependencies of a *scaffolded project* (not this plugin) should be reported to those dependencies' maintainers.
