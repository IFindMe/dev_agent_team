# Lesson: Skill Count Migration Requires 3 File Updates
Date: 2026-09-20
Tags: testing, migration, skill-count

## Situation
When adding new skills (e.g., 5 CBM integration skills), the skill count increases (13→18). This requires updating assertions in THREE test scripts AND all 14 agent prompts.

## What We Learned
1. `test-install.sh` — checks `find | wc -l` against hardcoded count
2. `test-runtime.sh` — checks `find | wc -l` against hardcoded count
3. `test-path-resolution.sh` — checks loop counter against hardcoded count + canonical sentence
4. All 14 `agents/*.md` — contain canonical sentence with skill count
5. `skills/SKILLS.md` — directory tree + agent-skill mapping table

## Pattern
When changing skill count, update ALL of these in one batch:
```bash
# Update test assertions
sed -i 's/= "OLD"/= "NEW"/g' scripts/test-install.sh scripts/test-runtime.sh scripts/test-path-resolution.sh

# Update canonical sentence in all agents
python3 -c "
import glob
for f in glob.glob('agents/*.md'):
    with open(f, 'r') as fh:
        content = fh.read()
    content = content.replace('(OLD skills)', '(NEW skills)')
    with open(f, 'w') as fh:
        fh.write(content)
"
```

## Evidence
- test-install.sh T03 failed with "dirs=18 (want 13)" after adding 5 skills
- test-path-resolution.sh T02 failed with "count=18" after adding 5 skills
- All 14 agent prompts needed `skills/ (13 skills)` → `skills/ (18 skills)`
- Fix required editing 17 files total (3 test scripts + 14 agent prompts)
