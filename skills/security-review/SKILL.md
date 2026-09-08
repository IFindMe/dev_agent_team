---
name: security-review
description: Security review methodology — identifying and assessing security implications of changes
version: "1.0"
owner: Reviewer
prerequisites: implementation completed, scope understood
---

# Security Review

## When to use this skill

- Changes involving authentication, authorization, or access control
- Changes to data handling, storage, or transmission
- Changes to external API interactions
- Changes to shell execution or system commands
- Any change where security implications are uncertain

## Core methodology

```text
IDENTIFY CHANGE → ASSESS ATTACK SURFACE → CHECK VALIDATION → CHECK AUTH → CHECK DATA → CHECK DEPS → VERDICT
```

## Security review checklist

### Input validation
- [ ] All external inputs validated and sanitized
- [ ] No SQL injection, command injection, or path traversal
- [ ] File uploads validated (type, size, content)

### Authentication & authorization
- [ ] Authentication checks are present and correct
- [ ] Authorization checks enforce least privilege
- [ ] No bypasses or backdoors

### Data protection
- [ ] Sensitive data is not logged or exposed
- [ ] Secrets are not hardcoded
- [ ] Data at rest and in transit is protected appropriately

### Error handling
- [ ] Errors do not leak sensitive information
- [ ] Stack traces are not exposed to users
- [ ] Graceful degradation on security failures

### Dependencies
- [ ] Dependencies are from trusted sources
- [ ] No known vulnerabilities in dependencies
- [ ] Dependency versions are pinned

### Shell & system
- [ ] Shell commands use safe execution patterns
- [ ] File permissions are appropriate
- [ ] Temporary files are handled securely

## Common pitfalls

- Assuming "it's internal" means "it's safe"
- Trusting user input without validation
- Hardcoding credentials (even "temporary" ones)
- Logging sensitive data
- Not considering the attack surface

## Exit criteria

- All checklist items addressed
- Findings categorized: CRITICAL / HIGH / MEDIUM / LOW / INFO
- Risk assessment for each finding
- Remediation plan for non-INFO findings
