#compdef cr

# Zsh completion for Compound Ralph (cr)
# Add to fpath: fpath=(/path/to/compound-ralph/completions $fpath)

_cr() {
    local -a commands
    commands=(
        'init:Initialize a project for Compound Ralph'
        'converse:Explore an idea through Socratic dialogue'
        'research:Deep investigation before planning'
        'plan:Create and deepen a feature plan'
        'spec:Convert a plan to SPEC.md format'
        'implement:Start autonomous implementation loop'
        'review:Run comprehensive code review'
        'fix:Convert review todos to fix spec'
        'test-gen:Generate E2E tests from spec'
        'init-tests:Set up WebdriverIO E2E testing'
        'compound:Extract and preserve learnings'
        'design:Proactive design improvement loop'
        'status:Show progress of all specs'
        'learnings:View project learnings'
        'reset-context:Reset context for stuck spec'
        'help:Show help'
        'version:Show version'
    )

    _arguments -C \
        '--non-interactive[Auto-confirm all prompts]' \
        '--json[Output machine-readable JSON]' \
        '1:command:->command' \
        '*::arg:->args'

    case $state in
        command)
            _describe 'command' commands
            # Also offer aliases for users who know them
            local -a aliases
            aliases=(
                'conv:Alias for converse'
                'res:Alias for research'
                'build:Alias for implement'
                'run:Alias for implement'
                'testgen:Alias for test-gen'
                'tg:Alias for test-gen'
                'init-e2e:Alias for init-tests'
                'comp:Alias for compound'
            )
            _describe 'alias' aliases
            ;;
        args)
            case $words[1] in
                init)
                    _arguments '1:project path:_directories'
                    ;;
                converse|conv)
                    _arguments '1:topic'
                    ;;
                research|res)
                    _arguments '1:topic'
                    ;;
                plan)
                    _arguments '1:feature description'
                    ;;
                implement|build|run)
                    _arguments \
                        '--json[Output JSON summary]' \
                        '--non-interactive[Auto-confirm prompts]' \
                        '--help[Show help]' \
                        '1:spec directory:_directories'
                    ;;
                review)
                    _arguments \
                        '--design[Include design review]' \
                        '--design-only[Only run design review]' \
                        '--url[Dev server URL]:url' \
                        '--team[Use agent teams for parallel review]' \
                        '--team-model[Model for teammates]:model' \
                        '--dry-run[Preview team structure without running]' \
                        '--help[Show help]' \
                        '1:spec directory:_directories'
                    ;;
                spec)
                    _arguments '1:plan file:_files -g "*.md"'
                    ;;
                fix)
                    _arguments \
                        '1:type:(code design)' \
                        '--help[Show help]' \
                        '2:spec directory:_directories'
                    ;;
                status)
                    _arguments \
                        '--json[Output JSON]' \
                        '--help[Show help]'
                    ;;
                design)
                    _arguments \
                        '--n[Force N iterations]:count' \
                        '--continue[Continue previous session]' \
                        '--help[Show help]' \
                        '1:dev server url'
                    ;;
                test-gen|testgen|tg)
                    _arguments \
                        '(-o --output)'{-o,--output}'[Output path]:file:_files' \
                        '--example-tests[Example tests directory]:dir:_directories' \
                        '--dry-run[Show generated code only]' \
                        '--all[Process all specs in directory]' \
                        '--help[Show help]' \
                        '1:spec file or directory:_files'
                    ;;
                init-tests|init-e2e)
                    _arguments \
                        '(-f --force)'{-f,--force}'[Overwrite existing config]' \
                        '--test-dir[Custom test directory]:dir:_directories' \
                        '--help[Show help]'
                    ;;
                compound|comp)
                    _arguments '1:feature name'
                    ;;
                learnings)
                    _arguments \
                        '1:category:(environment pattern gotcha fix discovery iteration_failure)' \
                        '2:limit'
                    ;;
                reset-context)
                    _arguments '1:spec directory:_directories'
                    ;;
                *)
                    _arguments '--help[Show help]'
                    ;;
            esac
            ;;
    esac
}

_cr
