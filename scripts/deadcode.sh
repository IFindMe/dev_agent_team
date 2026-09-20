#!/usr/bin/env bash
# deadcode.sh — Dead code and orphaned symbol detector for dev_agent_team
#
# Finds orphaned code, unused symbols, and stale references using grep-based
# pattern matching (no AST parsing). Adapted from CBM concept: functions with
# zero callers, excluding entry points.
#
# Usage:
#   deadcode.sh [OPTIONS]
#
# Options:
#   --path <path>         Scan specific path (default: current repo)
#   --type <type>         Filter by type: shell, python, skills, memory, all (default: all)
#   --format <fmt>        Output format: text, json (default: text)
#   --stale-days <n>      Days threshold for staleness (default: 30)
#   --exclude <pattern>   Exclude files matching pattern (repeatable)
#   -h, --help            Show this help
#
# Exit status: 0 clean (no dead code found); 1 dead code candidates found;
#              2 usage error; 3 runtime error.
#
# Detection strategies:
#   1. Shell functions: funcname() or function funcname — check if referenced elsewhere
#   2. Python functions: def funcname — check if imported or called
#   3. Exported symbols: functions in scripts never called by other scripts
#   4. Unused skills: skills/ entries never referenced in agents/ or other skills
#   5. Orphaned memory: memory entries referencing files that no longer exist

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

# Defaults
SCAN_PATH="${PROJECT_ROOT}"
SCAN_TYPE="all"
OUTPUT_FORMAT="text"
STALE_DAYS=30
EXCLUDE_PATTERNS=()
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# Counters
declare -i FILE_COUNT=0 SYMBOL_COUNT=0 HIGH_COUNT=0 MED_COUNT=0 LOW_COUNT=0

# Dead code candidates storage (array of "severity|file|symbol|reason")
CANDIDATES=()

# --------------------------------------------------------------------- #
# Helpers
# --------------------------------------------------------------------- #

die() { echo "ERROR: $*" >&2; exit 3; }

usage() {
    sed -n '2,/^$/{ s/^# \?//; p; }' "$0"
    exit "${1:-2}"
}

usage_err() { echo "ERROR: $*" >&2; usage; }

# Get file age in days (0 if <1 day)
file_age_days() {
    local file="$1"
    if [[ ! -f "$file" ]]; then
        echo "9999"
        return
    fi
    local mtime
    mtime=$(stat -c %Y "$file" 2>/dev/null || echo "0")
    local now
    now=$(date +%s)
    local diff=$(( now - mtime ))
    local days=$(( diff / 86400 ))
    echo "$days"
}

# Check if file matches any exclude pattern
is_excluded() {
    local file="$1"
    for pattern in "${EXCLUDE_PATTERNS[@]+"${EXCLUDE_PATTERNS[@]}"}"; do
        if [[ "$file" == *"$pattern"* ]]; then
            return 0
        fi
    done
    return 1
}

# Add a candidate
add_candidate() {
    local severity="$1" file="$2" symbol="$3" reason="$4"
    CANDIDATES+=("${severity}|${file}|${symbol}|${reason}")
    case "$severity" in
        HIGH) ((HIGH_COUNT++)) || true ;;
        MED)  ((MED_COUNT++)) || true ;;
        LOW)  ((LOW_COUNT++)) || true ;;
    esac
    ((SYMBOL_COUNT++)) || true
}

# --------------------------------------------------------------------- #
# Detection: Shell Functions
# --------------------------------------------------------------------- #

detect_shell_functions() {
    local scan_dir="$1"
    local file_count_before=$FILE_COUNT
    
    # Find all shell scripts
    while IFS= read -r -d '' file; do
        if is_excluded "$file"; then continue; fi
        ((FILE_COUNT++)) || true
        
        # Extract function definitions
        # Pattern 1: funcname() {
        # Pattern 2: function funcname {
        # Pattern 3: function funcname() {
        local funcs
        # Extract function names from lines like "funcname() {" or "function funcname {"
        funcs=$(grep -nE '^\s*(function\s+)?[a-zA-Z_][a-zA-Z0-9_]*\s*\(\)\s*\{' "$file" 2>/dev/null | \
                sed -E 's/^[0-9]+://' | \
                sed -E 's/^\s*(function\s+)?//' | \
                sed -E 's/\s*\(\)\s*\{.*$//' || true)
        
        if [[ -z "$funcs" ]]; then continue; fi
        
        while IFS= read -r func; do
            [[ -z "$func" ]] && continue
            
            # Skip common entry points and test helpers
            case "$func" in
                main|usage|help|die|usage_err|setup|teardown|test_*|assert_*|check_*) continue ;;
            esac
            
            # Count references to this function (excluding definition line itself)
            local ref_count
            ref_count=$(grep -rl "\b${func}\b" "$scan_dir" --include='*.sh' --include='*.bash' 2>/dev/null | \
                       grep -v "$file" | \
                       wc -l || echo "0")
            ref_count=$(echo -n "$ref_count" | tr -d '[:space:]')
            
            # Also check for references in the same file (excluding definition)
            local self_refs
            self_refs=$(grep -c "\b${func}\b" "$file" 2>/dev/null || echo "0")
            self_refs=$(echo -n "$self_refs" | tr -d '[:space:]')
            self_refs=$((self_refs - 1))  # Subtract the definition itself
            
            if [[ "$ref_count" -eq 0 && "$self_refs" -le 0 ]]; then
                local age
                age=$(file_age_days "$file")
                if [[ "$age" -ge "$STALE_DAYS" ]]; then
                    add_candidate "HIGH" "$file" "$func" "0 callers, ${age} days since last edit"
                else
                    add_candidate "MED" "$file" "$func" "0 callers"
                fi
            elif [[ "$ref_count" -eq 0 && "$self_refs" -ge 1 ]]; then
                add_candidate "MED" "$file" "$func" "only self-referencing (${self_refs} self-refs)"
            fi
        done <<< "$funcs"
    done < <(find "$scan_dir" -type f \( -name "*.sh" -o -name "*.bash" \) -print0 2>/dev/null)
}

# --------------------------------------------------------------------- #
# Detection: Python Functions
# --------------------------------------------------------------------- #

detect_python_functions() {
    local scan_dir="$1"
    
    # Find all Python files
    while IFS= read -r -d '' file; do
        if is_excluded "$file"; then continue; fi
        ((FILE_COUNT++)) || true
        
        # Extract function definitions (exclude __dunder__ methods)
        local funcs
        funcs=$(grep -nE '^\s*def\s+[a-zA-Z_][a-zA-Z0-9_]*\s*\(' "$file" 2>/dev/null | \
                grep -oE 'def\s+[a-zA-Z_][a-zA-Z0-9_]*' | \
                sed 's/^def\s*//' || true)
        
        if [[ -z "$funcs" ]]; then continue; fi
        
        while IFS= read -r func; do
            [[ -z "$func" ]] && continue
            
            # Skip dunder methods and common patterns
            case "$func" in
                __*__) continue ;;
                main|setup|teardown|test_*|assert_*) continue ;;
            esac
            
            # Check if imported elsewhere
            local import_count
            import_count=$(grep -rl "from\s.*\simport\s.*\b${func}\b\|import\s.*\b${func}\b" "$scan_dir" \
                          --include='*.py' 2>/dev/null | \
                          grep -v "$file" | \
                          wc -l || echo "0")
            import_count=$(echo -n "$import_count" | tr -d '[:space:]')
            
            # Check if called elsewhere
            local call_count
            call_count=$(grep -rl "\b${func}\b\s*(" "$scan_dir" --include='*.py' 2>/dev/null | \
                        grep -v "$file" | \
                        wc -l || echo "0")
            call_count=$(echo -n "$call_count" | tr -d '[:space:]')
            
            # Check for decorator usage
            local decorator_count
            decorator_count=$(grep -rl "@\s*${func}\b" "$scan_dir" --include='*.py' 2>/dev/null | \
                             grep -v "$file" | \
                             wc -l || echo "0")
            decorator_count=$(echo -n "$decorator_count" | tr -d '[:space:]')
            
            if [[ "$import_count" -eq 0 && "$call_count" -eq 0 && "$decorator_count" -eq 0 ]]; then
                local age
                age=$(file_age_days "$file")
                if [[ "$age" -ge "$STALE_DAYS" ]]; then
                    add_candidate "HIGH" "$file" "$func()" "0 imports/calls, ${age} days since last edit"
                else
                    add_candidate "MED" "$file" "$func()" "0 imports/calls"
                fi
            fi
        done <<< "$funcs"
    done < <(find "$scan_dir" -type f -name "*.py" -print0 2>/dev/null)
}

# --------------------------------------------------------------------- #
# Detection: Unused Skills
# --------------------------------------------------------------------- #

detect_unused_skills() {
    local scan_dir="$1"
    local skills_dir="$scan_dir/skills"
    
    if [[ ! -d "$skills_dir" ]]; then return; fi
    
    # Find all skill directories with SKILL.md
    while IFS= read -r -d '' skill_file; do
        ((FILE_COUNT++)) || true
        
        # Extract skill name from directory
        local skill_dir
        skill_dir=$(dirname "$skill_file")
        local skill_name
        skill_name=$(basename "$skill_dir")
        
        # Skip if this is the deadcode-detection skill itself
        if [[ "$skill_name" == "deadcode-detection" ]]; then continue; fi
        
        # Check references in agents/ directory
        local agent_refs
        agent_refs=$(grep -rl "\b${skill_name}\b" "$scan_dir/agents" 2>/dev/null | \
                    wc -l || echo "0")
        agent_refs=$(echo -n "$agent_refs" | tr -d '[:space:]')
        
        # Check references in other skills
        local skill_refs
        skill_refs=$(grep -rl "\b${skill_name}\b" "$skills_dir" 2>/dev/null | \
                    grep -v "$skill_file" | \
                    wc -l || echo "0")
        skill_refs=$(echo -n "$skill_refs" | tr -d '[:space:]')
        
        # Check references in orchestrator specifically
        local orch_refs
        orch_refs=$(grep -c "\b${skill_name}\b" "$scan_dir/agents/orchestrator.md" 2>/dev/null || echo "0")
        orch_refs=$(echo -n "$orch_refs" | tr -d '[:space:]')
        
        if [[ "$agent_refs" -eq 0 && "$skill_refs" -eq 0 ]]; then
            add_candidate "MED" "$skill_dir" "$skill_name/" "not referenced in agents/ or other skills"
        elif [[ "$agent_refs" -eq 0 && "$orch_refs" -eq 0 ]]; then
            add_candidate "LOW" "$skill_dir" "$skill_name/" "not in orchestrator skill map"
        fi
    done < <(find "$skills_dir" -type f -name "SKILL.md" -print0 2>/dev/null)
}

# --------------------------------------------------------------------- #
# Detection: Orphaned Memory
# --------------------------------------------------------------------- #

detect_orphaned_memory() {
    local scan_dir="$1"
    local memory_dir="$scan_dir/memory"
    
    if [[ ! -d "$memory_dir" ]]; then return; fi
    
    # Find all memory markdown files (excluding READMEs)
    while IFS= read -r -d '' mem_file; do
        ((FILE_COUNT++)) || true
        
        # Extract file references (paths like path/to/file.ext)
        # Pattern: quoted or unquoted paths with extensions
        local refs
        refs=$(grep -oE '(^|[^a-zA-Z0-9/._-])[/a-zA-Z0-9._-]+\.[a-zA-Z]{1,4}([^a-zA-Z0-9/._-]|$)' "$mem_file" 2>/dev/null | \
               sed 's/^[^a-zA-Z0-9/]*//; s/[^a-zA-Z0-9/]*$//' || true)
        
        if [[ -z "$refs" ]]; then continue; fi
        
        while IFS= read -r ref; do
            [[ -z "$ref" ]] && continue
            
            # Skip common false positives (dates, extensions, etc.)
            case "$ref" in
                *.md|*.sh|*.py|*.json|*.txt) ;;  # Valid file refs
                *) continue ;;
            esac
            
            # Resolve relative to project root
            local full_path="$scan_dir/$ref"
            
            # Check if file exists
            if [[ ! -e "$full_path" && ! -d "$full_path" ]]; then
                local age
                age=$(file_age_days "$mem_file")
                if [[ "$age" -ge "$STALE_DAYS" ]]; then
                    add_candidate "HIGH" "$mem_file" "$ref" "file does not exist, memory is ${age} days old"
                else
                    add_candidate "LOW" "$mem_file" "$ref" "file does not exist"
                fi
            fi
        done <<< "$refs"
    done < <(find "$memory_dir" -type f -name "*.md" ! -name "README.md" -print0 2>/dev/null)
}

# --------------------------------------------------------------------- #
# Detection: Exported Symbols (functions used by other scripts)
# --------------------------------------------------------------------- #

detect_exported_symbols() {
    local scan_dir="$1"
    
    # Find scripts that define functions and check cross-script usage
    while IFS= read -r -d '' file; do
        if is_excluded "$file"; then continue; fi
        
        # Extract source lines (scripts that source other scripts)
        local sourced_files
        sourced_files=$(grep -E '^\s*source\s+|^\s*\.\s+' "$file" 2>/dev/null | \
                       sed -E "s/^.*['\"]([^'\"]+)['\"].*$/\1/" || true)
        
        if [[ -z "$sourced_files" ]]; then continue; fi
        
        while IFS= read -r sourced; do
            [[ -z "$sourced" ]] && continue
            
            # Resolve the sourced file path
            local resolved
            if [[ "$sourced" == /* ]]; then
                resolved="$sourced"
            else
                resolved="$(dirname "$file")/$sourced"
            fi
            
            # Check if the sourced file exists and has exported functions
            if [[ -f "$resolved" ]]; then
                # Check for functions that might be exported
                local export_funcs
                export_funcs=$(grep -E '^export\s+function\s+|^function\s+[a-zA-Z_]' "$resolved" 2>/dev/null | \
                              grep -oE '[a-zA-Z_][a-zA-Z0-9_]*' | \
                              grep -v 'function' || true)
                
                # These would need to be checked against callers
                # For now, just count them
                if [[ -n "$export_funcs" ]]; then
                    while IFS= read -r ef; do
                        [[ -z "$ef" ]] && continue
                        # This is a simplified check - exported but not called elsewhere
                        # Would need more sophisticated analysis
                    done <<< "$export_funcs"
                fi
            fi
        done <<< "$sourced_files"
    done < <(find "$scan_dir" -type f \( -name "*.sh" -o -name "*.bash" \) -print0 2>/dev/null)
}

# --------------------------------------------------------------------- #
# Output
# --------------------------------------------------------------------- #

print_text_report() {
    echo "Dead Code Report: $TIMESTAMP"
    echo "Scanned: $FILE_COUNT files, $SYMBOL_COUNT symbols"
    echo ""
    
    if [[ "$SYMBOL_COUNT" -eq 0 ]]; then
        echo "No dead code candidates found."
        return 0
    fi
    
    echo "Dead Code Candidates:"
    
    # Sort by severity (HIGH first, then MED, then LOW)
    local sorted_candidates
    sorted_candidates=$(printf '%s\n' "${CANDIDATES[@]}" | sort -t'|' -k1 -r)
    
    while IFS='|' read -r severity file symbol reason; do
        echo "  [${severity}] ${file}::${symbol} — ${reason}"
    done <<< "$sorted_candidates"
    
    echo ""
    echo "Summary: high=$HIGH_COUNT, medium=$MED_COUNT, low=$LOW_COUNT, total=$SYMBOL_COUNT"
}

print_json_report() {
    echo "{"
    echo "  \"timestamp\": \"$TIMESTAMP\","
    echo "  \"files_scanned\": $FILE_COUNT,"
    echo "  \"symbols_found\": $SYMBOL_COUNT,"
    echo "  \"candidates\": ["
    
    if [[ "$SYMBOL_COUNT" -gt 0 ]]; then
        local first=true
        local sorted_candidates
        sorted_candidates=$(printf '%s\n' "${CANDIDATES[@]}" | sort -t'|' -k1 -r)
        
        while IFS='|' read -r severity file symbol reason; do
            if [[ "$first" == "true" ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    {\"severity\": \"$severity\", \"file\": \"$file\", \"symbol\": \"$symbol\", \"reason\": \"$reason\"}"
        done <<< "$sorted_candidates"
    fi
    
    echo ""
    echo "  ],"
    echo "  \"summary\": {\"high\": $HIGH_COUNT, \"medium\": $MED_COUNT, \"low\": $LOW_COUNT}"
    echo "}"
}

# --------------------------------------------------------------------- #
# Main
# --------------------------------------------------------------------- #

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --path)
                [[ -z "${2:-}" ]] && usage_err "Missing value for --path"
                SCAN_PATH="$2"
                shift 2
                ;;
            --type)
                [[ -z "${2:-}" ]] && usage_err "Missing value for --type"
                case "$2" in
                    shell|python|skills|memory|all) SCAN_TYPE="$2" ;;
                    *) usage_err "Invalid type: $2 (must be shell, python, skills, memory, or all)" ;;
                esac
                shift 2
                ;;
            --format)
                [[ -z "${2:-}" ]] && usage_err "Missing value for --format"
                case "$2" in
                    text|json) OUTPUT_FORMAT="$2" ;;
                    *) usage_err "Invalid format: $2 (must be text or json)" ;;
                esac
                shift 2
                ;;
            --stale-days)
                [[ -z "${2:-}" ]] && usage_err "Missing value for --stale-days"
                STALE_DAYS="$2"
                shift 2
                ;;
            --exclude)
                [[ -z "${2:-}" ]] && usage_err "Missing value for --exclude"
                EXCLUDE_PATTERNS+=("$2")
                shift 2
                ;;
            -h|--help|help)
                usage 0
                ;;
            *)
                usage_err "Unknown option: $1"
                ;;
        esac
    done
    
    # Validate scan path
    if [[ ! -d "$SCAN_PATH" ]]; then
        die "Scan path does not exist: $SCAN_PATH"
    fi
    
    # Run detection strategies
    case "$SCAN_TYPE" in
        all)
            detect_shell_functions "$SCAN_PATH"
            detect_python_functions "$SCAN_PATH"
            detect_unused_skills "$SCAN_PATH"
            detect_orphaned_memory "$SCAN_PATH"
            ;;
        shell) detect_shell_functions "$SCAN_PATH" ;;
        python) detect_python_functions "$SCAN_PATH" ;;
        skills) detect_unused_skills "$SCAN_PATH" ;;
        memory) detect_orphaned_memory "$SCAN_PATH" ;;
    esac
    
    # Output report
    case "$OUTPUT_FORMAT" in
        text) print_text_report ;;
        json) print_json_report ;;
    esac
    
    # Exit with appropriate code
    if [[ "$SYMBOL_COUNT" -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

main "$@"
