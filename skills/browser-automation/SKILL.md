---
name: browser-automation
description: Browser automation patterns — web interaction, scraping, and testing
version: "1.0"
owner: Explorer
prerequisites: web technology available, target URL known
---

# Browser Automation

## When to use this skill

- Web content needs to be fetched and analyzed
- UI behavior needs to be verified
- API documentation needs to be read from web sources

## Core methodology

```text
IDENTIFY TARGET → SELECT TOOL → FETCH/INTERACT → ANALYZE → RECORD
```

## Patterns

### Content fetching
- Use `webfetch` tool for static content
- Prefer markdown format for readability
- Handle errors and timeouts gracefully

### Research
- Use `websearch` for finding information
- Use `webfetch` for reading specific pages
- Cite sources with URLs

### Verification
- Fetch expected content
- Compare with actual behavior
- Document discrepancies

## Common pitfalls

- Assuming content hasn't changed since last fetch
- Not handling rate limits
- Fetching more than needed (context bloat)
- Trusting web content without verification

## Exit criteria

- Content fetched and analyzed
- Sources cited
- Findings recorded
