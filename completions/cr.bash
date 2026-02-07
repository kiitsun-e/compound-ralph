# Bash completion for Compound Ralph (cr)
# Source this file: source /path/to/compound-ralph/completions/cr.bash

_cr_completion() {
    local cur prev commands aliases
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    # Main commands
    commands="init converse research plan spec implement review fix test-gen init-tests compound design status learnings reset-context help version"

    # Command aliases
    aliases="conv res build run testgen tg init-e2e comp"

    case "$prev" in
        cr)
            COMPREPLY=( $(compgen -W "$commands $aliases --non-interactive --json --help --version" -- "$cur") )
            return 0
            ;;
        implement|build|run)
            COMPREPLY=( $(compgen -W "--json --non-interactive --help" -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
        review)
            COMPREPLY=( $(compgen -W "--design --design-only --url --team --team-model --dry-run --help" -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
        spec)
            COMPREPLY=( $(compgen -f -X '!*.md' -- "$cur") )
            return 0
            ;;
        fix)
            COMPREPLY=( $(compgen -W "code design --help" -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
        status)
            COMPREPLY=( $(compgen -W "--json --help" -- "$cur") )
            return 0
            ;;
        design)
            COMPREPLY=( $(compgen -W "--n --continue --help" -- "$cur") )
            return 0
            ;;
        test-gen|testgen|tg)
            COMPREPLY=( $(compgen -W "-o --output --example-tests --dry-run --all --help" -- "$cur") $(compgen -d -- "$cur") )
            return 0
            ;;
        init-tests|init-e2e)
            COMPREPLY=( $(compgen -W "--force -f --test-dir --help" -- "$cur") )
            return 0
            ;;
        learnings)
            COMPREPLY=( $(compgen -W "environment pattern gotcha fix discovery iteration_failure" -- "$cur") )
            return 0
            ;;
        reset-context)
            COMPREPLY=( $(compgen -d -- "$cur") )
            return 0
            ;;
        --url|--team-model|--test-dir|--example-tests)
            # These flags take a value; let default completion handle it
            return 0
            ;;
        --output|-o)
            COMPREPLY=( $(compgen -f -- "$cur") )
            return 0
            ;;
        --n)
            # Expects a number; no completion
            return 0
            ;;
        *)
            # For any subcommand, offer --help
            if [[ ${COMP_CWORD} -ge 2 ]]; then
                COMPREPLY=( $(compgen -W "--help" -- "$cur") )
            fi
            return 0
            ;;
    esac
}
complete -F _cr_completion cr
