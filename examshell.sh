#!/usr/bin/env bash
###############################################################################
# examshell.sh
#
# A bash reimplementation of the 42 Porto "exam shell" experience, built on
# top of the exercise bank found in:
#   https://github.com/GTitonele/42porto-piscine-17/tree/main/exam-practice
#
# What it does, level by level, just like the real thing:
#   - picks ONE exam (exam-00 / exam-01 / exam-02 / final-exam), OR
#   - "real" mode: walks exam-00 -> exam-01 -> exam-02 -> final-exam back to
#     back, zero to advanced, one long increasing-difficulty curriculum
#   - runs a single global countdown timer for the whole session (or none,
#     with -t 0 / real mode's default, for untimed practice)
#   - walks the Levels in order (Level 00, 01, 02, ...) for each exam
#   - for each Level, draws ONE random exercise and shows its subject
#   - gives you a tiny in-shell menu to edit / load / compile / run / test
#   - enforces the subject's "Allowed functions" line at compile time
#     (like the moulinette does), by inspecting the binary's undefined
#     dynamic symbols
#   - automatically checks program exercises against subject examples and
#     runs dedicated C harnesses for function exercises
#   - when time is up (or you quit), prints a final report: how many
#     levels you cleared, and a session log with every attempt
#
# USAGE
#   ./examshell.sh [-d PATH_TO_exam-practice] [-e exam-00|exam-01|exam-02|final-exam|real|random] [-t MINUTES]
#
# EXAMPLES
#   ./examshell.sh                          # interactive prompts, random exam
#   ./examshell.sh -e exam-01               # run exam-01 specifically
#   ./examshell.sh -e final-exam -t 180     # final exam, 3h budget
#   ./examshell.sh -e real                  # Modo Real: zero -> avancado
#   ./examshell.sh -t 0                     # untimed practice, any mode
#   ./examshell.sh -d ~/repos/42porto-piscine-17/exam-practice -e random
#
# IN-EXERCISE COMMANDS
#   e  edit      open $EDITOR on the expected file
#   l  load      copy in a file you already wrote elsewhere ("enviar")
#   c  compile   strict flags + allowed-functions check, then auto-tests
#   t  test      re-run the automatic tests against the last compiled code
#   r  run       run the compiled binary manually, with your own arguments
#   s  subject   reprint the exercise statement
#   n  next      move on (only unlocked once compile + tests are clean)
#   k  skip      give up on this one, counts as not cleared
#   q  quit      end the session now
###############################################################################

set -u
shopt -s extglob

# ---------------------------------------------------------------------------
# Config & defaults
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
EXAM_ROOT="$SCRIPT_DIR/exam-practice"
EXAM_CHOICE=""
DURATION_MIN=""
REAL_MODE=0
EXIT_REQUESTED=0
SELECTED_LEVEL=""
SELECTED_EXERCISE=""
LANGUAGE="pt"
USER_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/examshell"
WORKDIR_ROOT="${HOME}/.examshell/sessions"
PROGRESS_FILE="$USER_CONFIG_DIR/progress"
SESSION_PROGRESS_FILE="$USER_CONFIG_DIR/session_state"
CC=${CC:-cc}
read -r -a COMPILER <<< "$CC"
CFLAGS="-Wall -Wextra -Werror -Wpedantic"
EDITOR_BIN="${EDITOR:-vi}"
REAL_ORDER=(exam-00 exam-01 exam-02 final-exam)

# Runtime artifacts and libc-internal symbols we never flag, even though
# they show up as "undefined" dynamic symbols in every binary.
IGNORE_SYMS="__libc_start_main __cxa_finalize __gmon_start__ _ITM_deregisterTMCloneTable _ITM_registerTMCloneTable __libc_csu_init __libc_csu_fini __stack_chk_fail __stack_chk_guard __errno_location __assert_fail"

if [[ -t 1 && -t 2 ]]; then
    BOLD=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
    YEL=$'\033[33m'; BLU=$'\033[34m'; CYA=$'\033[36m'; MAG=$'\033[35m'; RST=$'\033[0m'
else
    BOLD=''; DIM=''; RED=''; GRN=''; YEL=''; BLU=''; CYA=''; MAG=''; RST=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
die() { echo "${RED}$(tr_text 'Erro:' 'Error:')${RST} $*" >&2; exit 1; }

hr() { printf '%s\n' '────────────────────────────────────────────────────────────────────'; }

tr_text() {
    local pt="$1" en="$2"
    if [ "$LANGUAGE" = en ]; then printf '%s' "$en"; else printf '%s' "$pt"; fi
}

ui() {
    local key="$1"
    if [ "$LANGUAGE" = "en" ]; then
        case "$key" in
            title) printf 'EXAM SHELL · 42 EXAM PRACTICE' ;;
            choose_exam) printf 'Select an exam to begin:' ;;
            real_mode) printf 'Real Mode (all exams in sequence)' ;;
            random_exam) printf 'Random exam' ;;
            choose_exercise) printf 'Choose level/exercise' ;;
            settings) printf 'Settings' ;;
            update_available) printf 'Update from GitHub (%s new commits)' "$2" ;;
            up_to_date) printf 'Updates: up to date' ;;
            update_diverged) printf 'Update from GitHub (branches diverged)' ;;
            check_updates) printf 'Check for updates (GitHub unavailable)' ;;
            quit) printf 'Quit' ;;
            settings_title) printf 'Settings' ;;
            language) printf 'Language' ;;
            back) printf 'Back' ;;
            save_progress) printf 'Save progress' ;;
            reset_progress) printf 'Reset progress' ;;
            all_level) printf 'All exercises in this level' ;;
            choose_language) printf 'Choose a language:' ;;
            language_saved) printf 'Language set to English.' ;;
            invalid_option) printf 'Invalid option.' ;;
            exercise) printf 'EXERCISE' ;;
            paused) printf 'Time: paused' ;;
            unlimited) printf 'Time: unlimited' ;;
            time_warning) printf 'Time: %s · WARNING: 5 minutes or less remain' "$2" ;;
            time) printf 'Time: %s' "$2" ;;
            edit) printf 'Edit' ;;
            load) printf 'Load' ;;
            compile) printf 'Compile' ;;
            test) printf 'Test' ;;
            run) printf 'Run' ;;
            subject) printf 'Subject' ;;
            next) printf 'Next' ;;
            skip) printf 'Skip' ;;
            select_prompt) printf 'examshell > ' ;;
            *) printf '%s' "$key" ;;
        esac
    else
        case "$key" in
            title) printf 'EXAMSHELL · TREINO DE EXAMES 42' ;;
            choose_exam) printf 'Selecione um exame para começar:' ;;
            real_mode) printf 'Modo Real (todos em sequência)' ;;
            random_exam) printf 'Exame aleatório' ;;
            choose_exercise) printf 'Selecionar nível/exercício' ;;
            settings) printf 'Configurações' ;;
            update_available) printf 'Atualizar pelo GitHub (%s commits novos)' "$2" ;;
            up_to_date) printf 'Atualizações: em dia' ;;
            update_diverged) printf 'Atualizar pelo GitHub (branches divergentes)' ;;
            check_updates) printf 'Verificar atualizações (GitHub indisponível)' ;;
            quit) printf 'Sair do programa' ;;
            settings_title) printf 'Configurações' ;;
            language) printf 'Idioma' ;;
            back) printf 'Voltar' ;;
            save_progress) printf 'Salvar progresso' ;;
            reset_progress) printf 'Zerar progresso' ;;
            all_level) printf 'Todos os exercícios deste nível' ;;
            choose_language) printf 'Selecione um idioma:' ;;
            language_saved) printf 'Idioma definido como Português.' ;;
            invalid_option) printf 'Opção inválida.' ;;
            exercise) printf 'EXERCÍCIO' ;;
            paused) printf 'Tempo: pausado' ;;
            unlimited) printf 'Tempo: sem limite' ;;
            time_warning) printf 'Tempo: %s · AVISO: restam 5 min ou menos' "$2" ;;
            time) printf 'Tempo: %s' "$2" ;;
            edit) printf 'Editar' ;;
            load) printf 'Carregar' ;;
            compile) printf 'Compilar' ;;
            test) printf 'Testar' ;;
            run) printf 'Executar' ;;
            subject) printf 'Enunciado' ;;
            next) printf 'Próximo' ;;
            skip) printf 'Saltar' ;;
            select_prompt) printf 'examshell › ' ;;
            *) printf '%s' "$key" ;;
        esac
    fi
}

load_language() {
    local saved_language=""
    if [ -r "$USER_CONFIG_DIR/config" ]; then
        IFS='=' read -r _ saved_language < "$USER_CONFIG_DIR/config"
    fi
    case "$saved_language" in
        pt|en) LANGUAGE="$saved_language" ;;
    esac
}

save_language() {
    mkdir -p "$USER_CONFIG_DIR" || return 1
    (umask 077; printf 'language=%s\n' "$LANGUAGE" > "$USER_CONFIG_DIR/config")
}

save_progress_state() {
    mkdir -p "$USER_CONFIG_DIR" || return 1
    (umask 077; {
        printf 'exam=%s\n' "${EXAM_CHOICE:-}"
        printf 'real=%s\n' "${REAL_MODE:-0}"
        printf 'level=%s\n' "${SELECTED_LEVEL:-}"
        printf 'exercise=%s\n' "${SELECTED_EXERCISE:-}"
        printf 'language=%s\n' "${LANGUAGE:-pt}"
    } > "$PROGRESS_FILE")
}

load_saved_progress() {
    [ -r "$PROGRESS_FILE" ] || return 0
    while IFS= read -r line || [ -n "$line" ]; do
        case "$line" in
            exam=*) EXAM_CHOICE="${line#exam=}" ;;
            real=*) REAL_MODE="${line#real=}" ;;
            level=*) SELECTED_LEVEL="${line#level=}" ;;
            exercise=*) SELECTED_EXERCISE="${line#exercise=}" ;;
            language=*) LANGUAGE="${line#language=}" ;;
        esac
    done < "$PROGRESS_FILE"
}

reset_saved_progress() {
    rm -f -- "$PROGRESS_FILE" "$SESSION_PROGRESS_FILE"
    EXAM_CHOICE=""
    SELECTED_LEVEL=""
    SELECTED_EXERCISE=""
    REAL_MODE=0
}

save_session_progress() {
    local current_session_key
    if [ "$REAL_MODE" -eq 1 ]; then
        current_session_key="real"
    else
        current_session_key="${EXAM_CHOICE:-}"
    fi
    mkdir -p "$USER_CONFIG_DIR" || return 1
    : > "$SESSION_PROGRESS_FILE"
    {
        printf 'session=%s\n' "$current_session_key"
        for idx in "${!curriculum[@]}"; do
            local rec="${curriculum[$idx]}"
            local rec_exam="${rec%%$'\x1f'*}"
            local rec_level="${rec#*$'\x1f'}"
            local rec_ex="${level_exercises[$idx]:-}"
            local rec_status="${level_results[$idx]:-pending}"
            printf '%s\t%s\t%s\t%s\n' "$rec_exam" "$rec_level" "$rec_ex" "$rec_status"
        done
    } > "$SESSION_PROGRESS_FILE"
}

load_session_progress() {
    local current_session_key saved_session_key=""
    if [ "$REAL_MODE" -eq 1 ]; then
        current_session_key="real"
    else
        current_session_key="${EXAM_CHOICE:-}"
    fi
    [ -r "$SESSION_PROGRESS_FILE" ] || return 0
    while IFS='=' read -r key value; do
        [ -n "$key" ] || continue
        if [ "$key" = "session" ]; then
            saved_session_key="$value"
        fi
    done < "$SESSION_PROGRESS_FILE"
    [ "$saved_session_key" = "$current_session_key" ] || return 0

    local -a loaded_ex=() loaded_res=()
    local line rec_exam rec_level rec_ex rec_status
    while IFS=$'\t' read -r rec_exam rec_level rec_ex rec_status; do
        [ -n "$rec_exam" ] || continue
        loaded_ex+=("$rec_ex")
        loaded_res+=("$rec_status")
    done < <(tail -n +2 "$SESSION_PROGRESS_FILE")

    local idx
    for idx in "${!curriculum[@]}"; do
        if [ "$idx" -lt "${#loaded_ex[@]}" ]; then
            level_exercises[$idx]="${loaded_ex[$idx]}"
            level_results[$idx]="${loaded_res[$idx]:-pending}"
        fi
    done
}

settings_menu() {
    local choice language_choice
    while true; do
        clear_terminal
        section "$(ui settings_title)"
        printf '  [1] %s (%s)\n' "$(ui language)" "$([ "$LANGUAGE" = en ] && printf 'English' || printf 'Português')"
        printf '  [q] %s\n\n' "$(ui back)"
        read -r -p '› ' choice || { clear_terminal; return; }
        case "$choice" in
            1)
                clear_terminal
                section "$(ui choose_language)"
                printf '  [1] Português\n  [2] English\n  [q] %s\n' "$(ui back)"
                read -r -p '› ' language_choice || { clear_terminal; return; }
                case "$language_choice" in
                    1) LANGUAGE=pt ;;
                    2) LANGUAGE=en ;;
                    q|Q) clear_terminal; continue ;;
                    *) printf '%s\n' "$(ui invalid_option)"; continue ;;
                esac
                if ! save_language; then
                    printf '%s\n' "$(tr_text 'Não foi possível guardar a configuração.' 'Could not save the setting.')"
                else
                    printf '%s\n' "$(ui language_saved)"
                fi
                ;;
            q|Q) clear_terminal; return ;;
            *) printf '%s\n' "$(ui invalid_option)" ;;
        esac
        read -r -p "$(tr_text 'ENTER › ' 'Press ENTER › ')" _ || { clear_terminal; return; }
    done
}

section() {
    hr
    printf '%s%s%s\n' "$BOLD$BLU" "$1" "$RST"
    hr
}

need_bin() { command -v "$1" >/dev/null 2>&1 || die "$(tr_text "ferramenta obrigatória '$1' não encontrada no PATH" "required tool '$1' not found in PATH")"; }

usage() {
    if [ "$LANGUAGE" = en ]; then
        cat <<'EOF'
EXAM SHELL - 42 exam practice
Usage: ./examshell.sh [-d EXERCISE_BANK] [-e EXAM] [-t MINUTES] [-h]
  -d PATH     Use an exercise bank from another directory
  -e EXAM     Start exam-00, exam-01, exam-02, final-exam, real, or random
  -t MINUTES  Set the session duration; 0 means no time limit
  -h          Show this help
EOF
    else
        sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
    fi
    exit 0
}

parse_args() {
    while getopts "d:e:t:h" opt; do
        case "$opt" in
            d) EXAM_ROOT="$OPTARG" ;;
            e) EXAM_CHOICE="$OPTARG" ;;
            t) DURATION_MIN="$OPTARG" ;;
            h) usage ;;
            *) usage ;;
        esac
    done
    shift $((OPTIND - 1))
    [ "$#" -eq 0 ] || die "$(tr_text 'argumento inesperado: use -h para ajuda' 'unexpected argument: use -h for help') $1"
    if [ -n "$DURATION_MIN" ]; then
        [[ "$DURATION_MIN" =~ ^[0-9]+$ ]] || die "$(tr_text 'a duração deve ser um número inteiro de minutos igual ou maior que zero' 'duration must be a non-negative whole number of minutes')"
    fi
}

run_preflight() {
    local -a missing=() fatal=() problems=() exam_dirs=() levels=() subjects=()
    local exam level subject line has_name has_expected has_project old_nullglob=0 old_globstar=0
    local level_count=0 exam_count=0
    local -a required=("${COMPILER[0]}" nm python3 timeout awk sort find sed grep tr xargs basename mkdir cp cat date)

    for bin in "${required[@]}"; do
        command -v "$bin" >/dev/null 2>&1 || missing+=("$bin")
    done
    command -v git >/dev/null 2>&1 || problems+=("$(tr_text 'git não encontrado; a verificação/atualização pelo GitHub ficará indisponível' 'git not found; GitHub update checks will be unavailable')")

    if [[ ! -d "$EXAM_ROOT" || ! -r "$EXAM_ROOT" ]]; then
        fatal+=("$(tr_text 'banco de exercícios' 'exercise bank') '$EXAM_ROOT' $(tr_text 'não existe ou não pode ser lido' 'does not exist or cannot be read')")
    else
        shopt -q nullglob && old_nullglob=1
        shopt -q globstar && old_globstar=1
        shopt -s nullglob globstar
        for exam in "$EXAM_ROOT"/*; do
            [[ -d "$exam" ]] || continue
            exam_dirs+=("$exam")
        done
        exam_count=${#exam_dirs[@]}
        if [ "$exam_count" -eq 0 ]; then
            fatal+=("$(tr_text 'não há pastas de exames em' 'no exam directories found in') '$EXAM_ROOT'")
        fi
        for exam in "${exam_dirs[@]}"; do
            levels=("$exam"/Level*)
            local valid_levels=0
            for level in "${levels[@]}"; do [[ -d "$level" ]] && valid_levels=$((valid_levels+1)); done
            if [ "$valid_levels" -eq 0 ]; then
                problems+=("${exam##*/}: $(tr_text 'não contém pastas' 'contains no directories matching') 'Level *'")
                continue
            fi
            level_count=$((level_count+valid_levels))
            for level in "${levels[@]}"; do
                [[ -d "$level" ]] || continue
                subjects=("$level"/**/*.subject.txt)
                if [ "${#subjects[@]}" -eq 0 ]; then
                    problems+=("${exam##*/}/${level##*/}: $(tr_text 'não contém enunciados' 'contains no subject files') *.subject.txt")
                    continue
                fi
                for subject in "${subjects[@]}"; do
                    if [[ ! -r "$subject" || ! -s "$subject" ]]; then
                        problems+=("$subject: $(tr_text 'vazio ou sem permissão de leitura' 'empty or not readable')")
                        continue
                    fi
                    has_name=0
                    has_expected=0
                    has_project=0
                    while IFS= read -r line || [ -n "$line" ]; do
                        [[ "$line" =~ ^Assignment[[:space:]]+name[[:space:]]*: ]] && has_name=1
                        [[ "$line" =~ ^Expected[[:space:]]+files[[:space:]]*: ]] && has_expected=1
                        [[ "$line" =~ ^project[[:space:]]+name[[:space:]]*: ]] && has_project=1
                    done < "$subject"
                    if { [ "$has_name" -eq 0 ] || [ "$has_expected" -eq 0 ]; } && [ "$has_project" -eq 0 ]; then
                        problems+=("$subject: $(tr_text 'faltam campos Assignment name e/ou Expected files; serão usados valores padrão' 'missing Assignment name and/or Expected files; defaults will be used')")
                    fi
                done
            done
        done
        [ "$old_nullglob" -eq 1 ] || shopt -u nullglob
        [ "$old_globstar" -eq 1 ] || shopt -u globstar
        [ "$level_count" -gt 0 ] || fatal+=("$(tr_text 'o banco não contém nenhum nível utilizável' 'the exercise bank contains no usable levels')")
    fi

    if [ "${#missing[@]}" -gt 0 ]; then
        printf '%s%s%s\n' "$RED$BOLD" "$(tr_text 'Verificação inicial: faltam dependências obrigatórias:' 'Preflight: required dependencies are missing:')" "$RST" >&2
        for line in "${missing[@]}"; do printf '  - %s\n' "$line" >&2; done
    fi
    if [ "${#fatal[@]}" -gt 0 ]; then
        printf '%s%s%s\n' "$RED$BOLD" "$(tr_text 'Não é possível iniciar: banco de exercícios inválido.' 'Cannot start: the exercise bank is invalid.')" "$RST" >&2
        for line in "${fatal[@]}"; do printf '  - %s\n' "$line" >&2; done
    fi
    if [ "${#problems[@]}" -gt 0 ]; then
        printf '%s%s (%s %s, %s %s):%s\n' "$YEL$BOLD" "$(tr_text 'Avisos da verificação inicial' 'Preflight warnings')" "$exam_count" "$(tr_text 'exame(s)' 'exam(s)')" "$level_count" "$(tr_text 'nível(is)' 'level(s)')" "$RST" >&2
        for line in "${problems[@]}"; do printf '  - %s\n' "$line" >&2; done
    elif [ "${#missing[@]}" -eq 0 ] && [ "${#fatal[@]}" -eq 0 ]; then
        printf '%s%s (%s %s, %s %s).%s\n' "$GRN" "$(tr_text 'Verificação inicial concluída: dependências e banco de exercícios prontos' 'Preflight complete: dependencies and exercise bank are ready')" "$exam_count" "$(tr_text 'exame(s)' 'exam(s)')" "$level_count" "$(tr_text 'nível(is)' 'level(s)')" "$RST"
    fi
    [ "${#missing[@]}" -eq 0 ] && [ "${#fatal[@]}" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Exam / level / exercise selection
# ---------------------------------------------------------------------------
list_exams() {
    find "$EXAM_ROOT" -mindepth 1 -maxdepth 1 -type d -print0 \
        | while IFS= read -r -d '' exam_dir; do
            printf '%s\n' "${exam_dir##*/}"
        done \
        | sort
}

choose_exam() {
    if [ -z "$EXAM_CHOICE" ]; then
        local -a exams=()
        local pick i update_status
        mapfile -t exams < <(list_exams)
        [ "${#exams[@]}" -gt 0 ] || die "$(tr_text 'não foram encontrados exames em' 'no exams were found in') '$EXAM_ROOT'"
        check_for_updates

        while true; do
            if [[ -t 1 ]]; then
                printf '\033[H\033[J'
            fi
            printf '%s┌────────────────────────────────────────┐%s\n' "$CYA" "$RST"
            printf '%s│%s           %s           %s│%s\n' "$CYA" "$YEL" 'EXAM SHELL - 42' "$CYA" "$RST"
            printf '%s└────────────────────────────────────────┘%s\n' "$CYA" "$RST"
            printf '\n %s\n\n' "$(ui choose_exam)"
            i=1
            for e in "${exams[@]}"; do printf '  %s[%02d]%s %s\n' "$GRN" "$i" "$RST" "$e"; i=$((i+1)); done
            printf '\n  %s[ m]%s %s\n' "$MAG" "$RST" "$(ui real_mode)"
            printf '  %s[ r]%s %s\n' "$MAG" "$RST" "$(ui random_exam)"
            printf '  %s[ s]%s %s\n' "$MAG" "$RST" "$(ui choose_exercise)"
            printf '  %s[ c]%s %s\n' "$MAG" "$RST" "$(ui settings)"
            printf '  %s[ p]%s %s\n' "$MAG" "$RST" "$(ui save_progress)"
            printf '  %s[ z]%s %s\n' "$YEL" "$RST" "$(ui reset_progress)"
            case "$UPDATE_STATE" in
                available)
                    printf '  %s[ u]%s %s\n' "$MAG" "$RST" "$(ui update_available "$UPDATE_COUNT")"
                    ;;
                current)
                    printf '  %s[ u]%s %s\n' "$MAG" "$RST" "$(ui up_to_date)"
                    ;;
                diverged)
                    printf '  %s[ u]%s %s\n' "$YEL" "$RST" "$(ui update_diverged)"
                    ;;
                *)
                    printf '  %s[ u]%s %s\n' "$YEL" "$RST" "$(ui check_updates)"
                    ;;
            esac
            printf '  %s[ q]%s %s\n\n' "$RED" "$RST" "$(ui quit)"
            printf '%s ❯ %s' "$CYA" "$RST"
            if ! read -r pick; then
                EXIT_REQUESTED=1
                printf "\n%s\n" "$(tr_text 'Entrada terminada. Até logo.' 'Input ended. Goodbye.')"
                return 0
            fi

            case "$pick" in
                q|Q|b|B)
                    EXIT_REQUESTED=1
                    echo "$(tr_text 'Até logo.' 'Goodbye.')"
                    return 0
                    ;;
                c)
                    settings_menu
                    ;;
                p|P)
                    if save_progress_state; then
                        echo "${GRN}$(tr_text 'Progresso salvo com sucesso.' 'Progress saved successfully.')${RST}"
                    else
                        echo "${RED}$(tr_text 'Não foi possível salvar o progresso.' 'Could not save progress.')${RST}"
                    fi
                    read -r -p "$(tr_text 'Pressione ENTER para continuar › ' 'Press ENTER to continue › ')" _ || true
                    ;;
                z|Z)
                    reset_saved_progress
                    echo "${YEL}$(tr_text 'Progresso zerado.' 'Progress reset.')${RST}"
                    read -r -p "$(tr_text 'Pressione ENTER para continuar › ' 'Press ENTER to continue › ')" _ || true
                    ;;
                u)
                    update_project
                    update_status=$?
                    if [ "$update_status" -eq 2 ]; then
                        echo "$(tr_text 'Reinicie o programa para usar a versão atualizada.' 'Restart the program to use the updated version.')"
                        EXIT_REQUESTED=1
                        return 0
                    fi
                    ;;
                r)
                    EXAM_CHOICE="${exams[$((RANDOM % ${#exams[@]}))]}"
                    break
                    ;;
                s)
                    if select_manual_exercise "${exams[@]}"; then
                        break
                    fi
                    ;;
                m)
                    EXAM_CHOICE="real"
                    break
                    ;;
                *)
                    if [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#exams[@]}" ]; then
                        EXAM_CHOICE="${exams[$((pick-1))]}"
                        break
                    fi
                    printf '%s\n\n' "${YEL}$(tr_text 'Opção inválida:' 'Invalid option:') '$pick'. $(tr_text 'Escolha uma das opções do menu.' 'Choose one of the menu options.')${RST}"
                    ;;
            esac
        done
    elif [ "$EXAM_CHOICE" = "random" ]; then
        local -a exams=()
        mapfile -t exams < <(list_exams)
        [ "${#exams[@]}" -gt 0 ] || die "$(tr_text 'não foram encontrados exames em' 'no exams were found in') '$EXAM_ROOT'"
        EXAM_CHOICE="${exams[$((RANDOM % ${#exams[@]}))]}"
    fi

    if [ "$EXAM_CHOICE" = "real" ]; then
        REAL_MODE=1
        return
    fi
    [ -d "$EXAM_ROOT/$EXAM_CHOICE" ] || die "$(tr_text 'exam' 'exam') '$EXAM_CHOICE' $(tr_text 'não encontrado em' 'not found under') $EXAM_ROOT"
}

UPDATE_STATE="unknown"
UPDATE_COUNT=0

check_for_updates() {
    local branch count
    UPDATE_STATE="unknown"
    UPDATE_COUNT=0
    command -v git >/dev/null 2>&1 || return 1
    git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 1
    branch="$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD)" || return 1
    git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null | grep -Eq '^(https?://github\.com/|git@github\.com:|ssh://git@github\.com/)' || return 1

    if ! GIT_TERMINAL_PROMPT=0 timeout 10s git -C "$SCRIPT_DIR" fetch --quiet origin "$branch"; then
        return 1
    fi
    count="$(git -C "$SCRIPT_DIR" rev-list --count HEAD..FETCH_HEAD 2>/dev/null)" || return 1
    if [ "$count" -eq 0 ]; then
        UPDATE_STATE="current"
    elif git -C "$SCRIPT_DIR" merge-base --is-ancestor HEAD FETCH_HEAD; then
        UPDATE_STATE="available"
        UPDATE_COUNT="$count"
    else
        UPDATE_STATE="diverged"
    fi
}

update_project() {
    local remote_url branch
    if ! command -v git >/dev/null 2>&1; then
        echo "${RED}$(tr_text 'Não foi possível atualizar: o Git não está instalado.' 'Cannot update: Git is not installed.')${RST}"
        return 1
    fi
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "${RED}$(tr_text 'Não foi possível atualizar: esta cópia não está dentro de um repositório Git.' 'Cannot update: this copy is not inside a Git repository.')${RST}"
        return 1
    fi
    remote_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)" || {
        echo "${RED}$(tr_text 'Não foi possível atualizar: o remoto origin não está configurado.' 'Cannot update: the origin remote is not configured.')${RST}"
        return 1
    }
    case "$remote_url" in
        https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*) ;;
        *) echo "${RED}$(tr_text 'Não foi possível atualizar: origin não aponta para GitHub.' 'Cannot update: origin does not point to GitHub.')${RST}"
           return 1 ;;
    esac
    branch="$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD)" || {
        echo "${RED}$(tr_text 'Não foi possível atualizar: HEAD não aponta para um branch.' 'Cannot update: HEAD is not on a branch.')${RST}"
        return 1
    }

    echo "$(tr_text 'A sincronizar com o GitHub...' 'Syncing with GitHub...')"
    if ! GIT_TERMINAL_PROMPT=0 timeout 60s git -C "$SCRIPT_DIR" pull --ff-only origin "$branch"; then
        echo "${RED}$(tr_text 'A atualização falhou. As alterações locais podem conflitar com as do GitHub; confira git status e resolva os conflitos antes de tentar novamente.' 'Update failed. Local changes may conflict with GitHub; check git status and resolve conflicts before trying again.')${RST}"
        return 1
    fi
    echo "${GRN}$(tr_text 'Projeto sincronizado com o GitHub.' 'Project synced with GitHub.')${RST}"
    return 2
}


default_duration_for() {
    case "$1" in
        real)       echo 0   ;;   # untimed by default: zero-to-advanced training
        final-exam) echo 180 ;;
        *)          echo 60  ;;
    esac
}

get_levels_for_exam() {
    # NUL-delimited so "Level 00" style names survive intact into the array.
    local exam="$1"
    find "$EXAM_ROOT/$exam" -mindepth 1 -maxdepth 1 -type d -name 'Level *' -print0 \
        | sort -zV
}

# Builds the full curriculum as NUL-separated "exam<US>leveldir" records,
# where <US> is ASCII unit separator (0x1F), safe because neither exam names
# nor paths contain it. Single-exam mode yields one exam's levels; real mode
# concatenates every exam in REAL_ORDER, in order, for a full zero-to-advanced
# progression.
build_curriculum() {
    if [ -n "$SELECTED_LEVEL" ]; then
        if [ -n "$SELECTED_EXERCISE" ]; then
            printf '%s\x1f%s\0' "$EXAM_CHOICE" "$SELECTED_EXERCISE"
            return
        fi
        local lvl="$SELECTED_LEVEL"
        while IFS= read -r -d '' ex; do
            printf '%s\x1f%s\0' "$EXAM_CHOICE" "$ex"
        done < <(find "$lvl" -type f -name '*.subject.txt' -print0 | sort -z)
        return
    fi
    local exams=()
    if [ "$REAL_MODE" -eq 1 ]; then
        exams=("${REAL_ORDER[@]}")
    else
        exams=("$EXAM_CHOICE")
    fi
    for ex in "${exams[@]}"; do
        [ -d "$EXAM_ROOT/$ex" ] || continue
        while IFS= read -r -d '' lvl; do
            printf '%s\x1f%s\0' "$ex" "$lvl"
        done < <(get_levels_for_exam "$ex")
    done
}

pick_exercise() {
    # Exercises live either directly inside "Level NN/name.subject.txt"
    # (exam-00/01/02) or one directory deeper, "Level NN/name/name.subject.txt"
    # (final-exam), so search recursively rather than assuming flat files.
    local level_dir="$1"
    local files=()
    while IFS= read -r -d '' f; do files+=("$f"); done < <(
        find "$level_dir" -type f -name '*.subject.txt' -print0
    )
    [ "${#files[@]}" -eq 0 ] && return 1
    echo "${files[$((RANDOM % ${#files[@]}))]}"
}

select_manual_exercise() {
    local -a exam_names=("$@") levels=() exercises=()
    local selection exam level exercise i

    while true; do
        clear_terminal
        section "$(tr_text 'Selecionar exame' 'Select an exam')"
        for i in "${!exam_names[@]}"; do printf '  [%02d] %s\n' "$((i+1))" "${exam_names[$i]}"; done
        printf '  [q] %s\n' "$(ui back)"
        printf '  ❯ '
        IFS= read -r selection || { clear_terminal; return 1; }
        if [ "$selection" = "q" ]; then clear_terminal; return 1; fi
        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#exam_names[@]}" ]; then
            exam="${exam_names[$((selection-1))]}"
            levels=()
            while IFS= read -r -d '' level; do levels+=("$level"); done < <(get_levels_for_exam "$exam")

            while true; do
                clear_terminal
                section "$(tr_text 'Níveis de' 'Levels for') $exam"
                if [ "${#levels[@]}" -eq 0 ]; then
                    echo "$(tr_text 'Não há níveis disponíveis para este exame.' 'No levels are available for this exam.')"
                fi
                for i in "${!levels[@]}"; do printf '  [%02d] %s\n' "$((i+1))" "$(basename "${levels[$i]}")"; done
                printf '  [q] %s\n' "$(ui back)"
                printf '  ❯ '
                IFS= read -r selection || { clear_terminal; return 1; }
                if [ "$selection" = "q" ] || [ "$selection" = "b" ] || [ "$selection" = "B" ]; then clear_terminal; continue 2; fi
                if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#levels[@]}" ]; then
                    level="${levels[$((selection-1))]}"
                    exercises=()
                    while IFS= read -r -d '' exercise; do exercises+=("$exercise"); done < <(
                        find "$level" -type f -name '*.subject.txt' -print0 | sort -z
                    )
                    exercise=""

                    while true; do
                        clear_terminal
                        section "$(tr_text 'Exercícios de' 'Exercises in') $(basename "$level")"
                        if [ "${#exercises[@]}" -eq 0 ]; then
                            echo "$(tr_text 'Não há exercícios neste nível.' 'There are no exercises at this level.')"
                        fi
                        for i in "${!exercises[@]}"; do printf '  [%02d] %s\n' "$((i+1))" "$(basename "${exercises[$i]}" .subject.txt)"; done
                        if [ "${#exercises[@]}" -gt 0 ]; then
                            printf '  [a] %s\n' "$(ui all_level)"
                            printf '  [r] %s\n' "$(tr_text 'Sortear neste nível' 'Pick randomly from this level')"
                        fi
                        printf '  [b] %s\n' "$(ui back)"
                        printf '  [q] %s\n' "$(ui quit)"
                        printf '  ❯ '
                        IFS= read -r selection || { clear_terminal; return 1; }
                        if [ "$selection" = "q" ] || [ "$selection" = "b" ] || [ "$selection" = "B" ]; then clear_terminal; continue 2; fi
                        if [ "$selection" = "a" ] || [ "$selection" = "A" ]; then
                            EXAM_CHOICE="$exam"
                            SELECTED_LEVEL="$level"
                            SELECTED_EXERCISE=""
                            return 0
                        fi
                        if [ "$selection" = "r" ] && [ "${#exercises[@]}" -gt 0 ]; then
                            exercise="${exercises[$((RANDOM % ${#exercises[@]}))]}"
                            break
                        fi
                        if [[ "$selection" =~ ^[0-9]+$ ]] && [ "$selection" -ge 1 ] && [ "$selection" -le "${#exercises[@]}" ]; then
                            exercise="${exercises[$((selection-1))]}"
                            break
                        fi
                        printf '%s%s%s\n' "$YEL" "$(tr_text 'Opção inválida. Escolha um número, a, r, b ou q para voltar.' 'Invalid option. Choose a number, a, r, b, or q to go back.')" "$RST"
                    done
                    break
                fi
                printf '%s%s%s\n' "$YEL" "$(tr_text 'Opção inválida. Escolha um número da lista ou q para voltar.' 'Invalid option. Choose a number from the list or q to go back.')" "$RST"
            done

            EXAM_CHOICE="$exam"
            SELECTED_LEVEL="$level"
            SELECTED_EXERCISE="$exercise"
            return 0
        fi
        printf '%s%s%s\n' "$YEL" "$(tr_text 'Opção inválida. Escolha um número da lista ou q para voltar.' 'Invalid option. Choose a number from the list or q to go back.')" "$RST"
    done
}

# ---------------------------------------------------------------------------
# Subject parsing
# ---------------------------------------------------------------------------
subj_field() {
    # subj_field FILE "Field name"
    grep -m1 "^$2" "$1" | sed -E "s/^$2[[:space:]]*:[[:space:]]*//"
}

show_subject() {
    printf '%s%s · %s%s\n' "$BOLD$CYA" "$(ui exercise)" "$(basename "$1" .subject.txt)" "$RST"
    hr
    cat "$1"
    hr
}

clear_terminal() {
    if [[ -t 1 ]]; then
        printf '\033[2J\033[H'
    fi
}

# ---------------------------------------------------------------------------
# Timer. DURATION_MIN=0 means untimed: time_is_up() is always false and the
# display shows an infinity symbol instead of a countdown.
# ---------------------------------------------------------------------------
start_timer() {
    if [ "$DURATION_MIN" -eq 0 ]; then
        EXAM_END_EPOCH=0
    else
        EXAM_END_EPOCH=$(( $(date +%s) + DURATION_MIN * 60 ))
    fi
}

TIMER_STARTED=0

seconds_left() {
    [ "$DURATION_MIN" -eq 0 ] && { echo -1; return; }
    local left=$(( EXAM_END_EPOCH - $(date +%s) ))
    [ "$left" -lt 0 ] && left=0
    echo "$left"
}

fmt_secs() {
    local s="$1"
    [ "$s" -lt 0 ] && { echo "sem limite"; return; }
    printf '%02d:%02d:%02d' $((s/3600)) $(((s%3600)/60)) $((s%60))
}

time_is_up() {
    if [ "$DURATION_MIN" -eq 0 ] || [ "$TIMER_STARTED" -eq 0 ]; then
        return 1
    fi
    [ "$(seconds_left)" -le 0 ]
}

timer_status() {
    if [ "$TIMER_STARTED" -eq 0 ]; then
        printf '%s' "$(ui paused)"
        return
    fi
    local left
    left="$(seconds_left)"
    if [ "$left" -lt 0 ]; then
        printf '%s' "$(ui unlimited)"
    elif [ "$left" -le 300 ]; then
        printf '%s%s%s' "$YEL$BOLD" "$(ui time_warning "$(fmt_secs "$left")")" "$RST"
    else
        printf '%s' "$(ui time "$(fmt_secs "$left")")"
    fi
}

# Read a line while checking the countdown once per second. The timer display
# is rendered only with the exercise menu, never refreshed while waiting for
# input.
read_exercise_line() {
    local prompt="$1" result_var="$2"
    local buffer="" char rc prompt_shown=0 left

    if [ "$DURATION_MIN" -eq 0 ] || [[ ! -t 0 || ! -t 1 ]]; then
        IFS= read -r -p "$prompt" buffer || return 1
        printf -v "$result_var" '%s' "$buffer"
        return 0
    fi

    while true; do
        left="$(seconds_left)"
        [ "$left" -gt 0 ] || return 2
        if [ "$prompt_shown" -eq 0 ]; then
            printf '%s' "$prompt"
            prompt_shown=1
        fi
        IFS= read -r -s -n 1 -t 1 char
        rc=$?
        if [ "$rc" -gt 128 ]; then
            continue
        elif [ "$rc" -ne 0 ]; then
            printf '\n'
            return 1
        fi

        case "$char" in
            '')
                printf '\n'
                printf -v "$result_var" '%s' "$buffer"
                return 0
                ;;
            $'\177'|$'\b')
                if [ -n "$buffer" ]; then
                    buffer="${buffer%?}"
                    printf '\b \b'
                fi
                ;;
            $'\025')
                printf '\r\033[K%s' "$prompt"
                buffer=""
                ;;
            $'\004')
                if [ -z "$buffer" ]; then
                    printf '\n'
                    return 1
                fi
                ;;
            *)
                buffer+="$char"
                printf '%s' "$char"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Compile-time "allowed functions" enforcement, mimicking the moulinette
# ---------------------------------------------------------------------------
check_allowed_functions() {
    local binary="$1" allowed_raw="$2"
    # Normalise the allowed list: "None" / "" => nothing is allowed.
    local allowed_norm
    allowed_norm=$(printf '%s' "$allowed_raw" | tr ',' ' ' | tr -s ' ' | sed 's/[[:space:]]\+/ /g')
    allowed_norm=$(printf '%s' "$allowed_norm" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if echo "$allowed_norm" | grep -qiw "none"; then
        allowed_norm=""
    fi

    local nm_output undefined
    if ! nm_output=$(nm --undefined-only "$binary" 2>/dev/null); then
        echo "${RED}$(tr_text 'Não foi possível verificar as funções usadas em' 'Could not check functions used in') '$binary'.${RST}"
        return 1
    fi
    undefined=$(printf '%s\n' "$nm_output" | awk '{print $NF}')

    local violations=()
    for raw_sym in $undefined; do
        [ -z "$raw_sym" ] && continue
        # nm prints versioned symbols as "name@GLIBC_x.y" (or "@@..."); strip
        # the version suffix before comparing against the allow/ignore lists.
        local sym="${raw_sym%%@*}"
        sym="${sym##+([[:space:]])}"
        sym="${sym%%+([[:space:]])}"
        case " $IGNORE_SYMS " in *" $sym "*) continue ;; esac
        local ok=0
        for a in $allowed_norm; do
            local allowed_sym="${a%%@*}"
            allowed_sym="${allowed_sym##+([[:space:]])}"
            allowed_sym="${allowed_sym%%+([[:space:]])}"
            [ "$sym" = "$allowed_sym" ] && ok=1 && break
        done
        [ "$ok" -eq 0 ] && violations+=("$sym")
    done

    if [ "${#violations[@]}" -gt 0 ]; then
        echo "${RED}${BOLD}$(tr_text 'Função(ões) não permitida(s):' 'Disallowed function(s):')${RST} ${violations[*]}"
        echo "${DIM}$(tr_text 'Permitidas:' 'Allowed:') ${allowed_raw:-$(tr_text 'nenhuma' 'none')}${RST}"
        return 1
    fi
    echo "${GRN}$(tr_text 'Verificação de funções permitidas: OK' 'Allowed functions check: OK')${RST}"
    return 0
}

# ---------------------------------------------------------------------------
# Automatic tests, extracted straight from the subject's own "$>program"
# transcript. This is a best-effort checker, not the official moulinette:
# it can't verify things the transcript doesn't show (pointer addresses,
# randomness, interactive stdin not illustrated, etc). When a subject has
# no testable "$>...' examples at all, it says so and lets you move on
# after a manual [r]un check instead of blocking you forever.
# ---------------------------------------------------------------------------
extract_tests() {
    # extract_tests SUBJECT_FILE OUTDIR -> prints the number of tests found,
    # writing inv_N.txt (invocation line) / exp_N.txt (expected transcript)
    # pairs into OUTDIR for N in 1..count.
    local subject_file="$1" outdir="$2"
    awk -v outdir="$outdir" '
        BEGIN { n = 0; state = 0 }
        # Two transcript styles show up across the subjects: "$>./prog ..."
        # (most common) and a bare "./prog ..." / "./a.out ..." invocation
        # line with no "$>" prompt at all. Both are treated the same way.
        /^\$>/ || /^\.\// {
            line = $0
            if ($0 ~ /^\$>/) sub(/^\$>[[:space:]]*/, "", line)
            if (line == "") {
                # bare "$>" prompt: just closes the transcript, not a new
                # invocation, so leave it out of both the invocation and
                # the previous test'"'"'s expected output.
                next
            }
            if (state == 1) close(expfile)
            n++
            invfile = outdir "/inv_" n ".txt"
            expfile = outdir "/exp_" n ".txt"
            print line > invfile
            close(invfile)
            printf "" > expfile
            state = 1
            next
        }
        /^=+$/ {
            # a "====" divider (subject header/footer banner) always ends
            # the transcript, whether or not the author closed it with a
            # bare "$>" prompt first.
            if (state == 1) { close(expfile); state = 0 }
            next
        }
        state == 1 { print >> expfile }
        END { if (state == 1) close(expfile); print n }
    ' "$subject_file"
}

run_auto_tests() {
    # run_auto_tests SUBJECT_FILE NAME WORKDIR BIN -> sets AUTO_TESTS_OK to
    # 1 (all testable examples passed, or none were testable) or 0 (at
    # least one testable example failed).
    local subject_file="$1" name="$2" work="$3" bin="$4"
    local tdir="$work/.tests"
    rm -rf "$tdir"; mkdir -p "$tdir"

    local n
    n=$(extract_tests "$subject_file" "$tdir")

    local passed=0 total=0 first_fail=""
    local i inv exp got
    for ((i = 1; i <= n; i++)); do
        inv=$(cat "$tdir/inv_$i.txt")
        exp=$(cat "$tdir/exp_$i.txt")
        # Drop a bare trailing "$>" prompt line: it's just the shell prompt
        # closing the transcript, not real program output.
        exp=$(printf '%s\n' "$exp" | sed -E '$ { /^\$>[[:space:]]*$/d }')

        # Examples with "[...]" are truncated by the author on purpose
        # (e.g. fizzbuzz's 1..100 list) and can't be matched automatically.
        case "$inv $exp" in *'[...]'*) continue ;; esac
        [ -z "$inv" ] && continue

        total=$((total+1))
        local name_esc bin_esc bin_quoted cmd
        name_esc=$(printf '%s' "$name" | sed 's/[.[\*^$/]/\\\\&/g')
        bin_quoted=$(printf '%q' "$bin")
        bin_esc=$(printf '%s' "$bin_quoted" | sed 's/[&/\\]/\\\\&/g')
        # The invocation may reference the exercise's own name ("./aff_a")
        # or the generic "./a.out" / "a.out" some subjects use instead;
        # either way, point it at the binary we actually just compiled.
        cmd=$(printf '%s' "$inv" \
            | sed -E "s#\\./?$name_esc\\b#$bin_esc#" \
            | sed -E "s#\\./?a\\.out\\b#$bin_esc#")

        local test_rc=0
        got=$(cd "$work" && timeout 5 bash -o pipefail -c "$cmd" 2>/dev/null) || test_rc=$?
        # Trim trailing blank lines on both sides before comparing.
        local got_t exp_t
        got_t=$(printf '%s\n' "$got" | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}')
        exp_t=$(printf '%s\n' "$exp" | sed -e ':a' -e '/^[[:space:]]*$/{$d;N;ba' -e '}')

        if [ "$got_t" = "$exp_t" ] && [ "$test_rc" -eq 0 ]; then
            passed=$((passed+1))
        elif [ -z "$first_fail" ]; then
            first_fail="$(tr_text 'teste' 'test') $i: \`$inv\`"$'\n'"$(tr_text 'código de saída:' 'exit code:') $test_rc"$'\n'"$(tr_text 'esperado:' 'expected:')"$'\n'"$exp_t"$'\n'"$(tr_text 'obtido:' 'got:')"$'\n'"$got_t"
        fi
    done

    if [ "$total" -eq 0 ]; then
        echo "${YEL}$(tr_text 'Este enunciado não tem exemplos que possam ser testados automaticamente.' 'This subject has no examples that can be tested automatically.')${RST}"
        echo "$(tr_text 'Confirme a solução com [r] Executar; avance depois com [n] Próximo.' 'Check your solution with [r] Run, then continue with [n] Next.')"
        AUTO_TESTS_OK=0
        return
    fi

    if [ "$passed" -eq "$total" ]; then
        echo "${GRN}$(tr_text 'Testes dos exemplos:' 'Example tests:') $passed/$total $(tr_text 'passaram.' 'passed.')${RST}"
        echo "${DIM}$(tr_text 'Verificação parcial; não substitui a correção oficial.' 'Partial check; this does not replace the official evaluation.')${RST}"
        AUTO_TESTS_OK=1
    else
        echo "${RED}${BOLD}$(tr_text 'Testes dos exemplos:' 'Example tests:') $passed/$total $(tr_text 'passaram.' 'passed.')${RST}"
        echo "${DIM}$first_fail${RST}"
        echo "${DIM}$(tr_text 'Verificação parcial; não substitui a correção oficial.' 'Partial check; this does not replace the official evaluation.')${RST}"
        AUTO_TESTS_OK=0
    fi
}

# ---------------------------------------------------------------------------
# One exercise "station": edit / load / compile / test / run / next / skip
# ---------------------------------------------------------------------------
run_exercise() {
    local subject_file="$1" work="$2" level_label="$3"
    local name expected allowed cmd
    name=$(subj_field "$subject_file" "Assignment name")
    if [ -z "$name" ]; then
        name=$(subj_field "$subject_file" "project name")
        name="${name##*/}"
        name="${name%.c}"
    fi
    name="${name:-$(basename "$subject_file" .subject.txt)}"
    expected=$(subj_field "$subject_file" "Expected files")
    if [ -z "$expected" ]; then
        expected=$(subj_field "$subject_file" "project name")
        expected="${expected##*/}"
    fi
    expected="${expected:-${name}.c}"
    allowed=$(subj_field "$subject_file" "Allowed functions")

    show_subject "$subject_file"

    # Parse comma-separated expected filenames and reject paths before use.
    local -a expected_files=()
    local expected_item
    IFS=',' read -r -a expected_files <<< "$expected"
    for i in "${!expected_files[@]}"; do
        expected_item="${expected_files[$i]}"
        expected_item="${expected_item##+([[:space:]])}"
        expected_item="${expected_item%%+([[:space:]])}"
        [ -n "$expected_item" ] || die "empty filename in Expected files for '$name'"
        [[ "$expected_item" != */* && "$expected_item" != . && "$expected_item" != .. ]] \
            || die "Expected files must contain filenames, not paths: '$expected_item'"
        expected_files[$i]="$expected_item"
    done

    # Stub out the expected file(s) if they don't exist yet.
    local first_file="" f
    for f in "${expected_files[@]}"; do
        [ -z "$first_file" ] && first_file="$f"
        [ -f "$work/$f" ] || cat > "$work/$f" <<EOF
/* ${name:-exercise} — expected file: $f */
/* Allowed functions: ${allowed:-None} */

EOF
    done

    local compiled_ok=0 object_only=0 function_tested=0
    AUTO_TESTS_OK=0
    local bin="$work/a.out"

    while true; do
        time_is_up && { echo "${RED}${BOLD}$(tr_text 'Tempo esgotado.' 'Time is up.')${RST}"; return 2; }
        echo
        hr
        printf '%s%s%s  ·  %s  ·  %s\n' "$BOLD$CYA" "$level_label" "$RST" "${name:-?}" "$(timer_status)"
        printf '[e] %s   [l] %s   [c] %s   [t] %s\n' "$(ui edit)" "$(ui load)" "$(ui compile)" "$(ui test)"
        printf '[r] %s [s] %s [n] %s [k] %s [q] %s\n' "$(ui run)" "$(ui subject)" "$(ui next)" "$(ui skip)" "$(ui quit)"
        if [ "$TIMER_STARTED" -eq 0 ]; then
            TIMER_STARTED=1
            start_timer
        fi
        local input_status=0
        read_exercise_line "$(ui select_prompt)" cmd || input_status=$?
        if [ "$input_status" -eq 1 ]; then
            echo
            echo "${YEL}$(tr_text 'Entrada encerrada; a sessão será finalizada.' 'Input ended; the session will close.')${RST}"
            return 3
        elif [ "$input_status" -eq 2 ]; then
            echo "${RED}${BOLD}$(tr_text 'Tempo esgotado.' 'Time is up.')${RST}"
            return 2
        fi
        time_is_up && { echo "${RED}${BOLD}$(tr_text 'Tempo esgotado.' 'Time is up.')${RST}"; return 2; }
        clear_terminal

        case "$cmd" in
            e|edit)
                "$EDITOR_BIN" "$work/$first_file"
                compiled_ok=0
                object_only=0
                function_tested=0
                AUTO_TESTS_OK=0
                rm -f -- "$bin"
                ;;
            l|load)
                local src
                read_exercise_line "$(tr_text 'Caminho do ficheiro para carregar: ' 'File path to load: ')" src || src=""
                if [ -z "$src" ] || [ ! -f "$src" ]; then
                    echo "${YEL}$(tr_text 'Ficheiro não encontrado:' 'File not found:') $src${RST}"
                else
                    cp -- "$src" "$work/$first_file"
                    compiled_ok=0
                    object_only=0
                    function_tested=0
                    AUTO_TESTS_OK=0
                    rm -f -- "$bin"
                    echo "${GRN}$(tr_text 'Solução carregada. Use [c] Compilar para continuar.' 'Solution loaded. Use [c] Compile to continue.')${RST}"
                fi
                ;;
            c|compile)
                compiled_ok=0
                object_only=0
                function_tested=0
                AUTO_TESTS_OK=0
                local -a srcs=() objects=()
                for f in "${expected_files[@]}"; do srcs+=("$work/$f"); done
                local object_dir="$work/.objects"
                local harness="$work/.function_tests.c" harness_supported=0
                local object_index=0 object failed_object=0 function_output
                rm -f -- "$bin"
                mkdir -p "$object_dir"

                if python3 "$SCRIPT_DIR/function_tests.py" "$name" "$harness"; then
                    harness_supported=1
                fi

                if [ "$harness_supported" -eq 1 ]; then
                    # Compile the student's files separately so the allowed-function
                    # check excludes calls made only by this test harness.
                    for f in "${srcs[@]}"; do
                        object="$object_dir/$object_index.o"
                        if ! "${COMPILER[@]}" $CFLAGS -Dmain=examshell_student_main -I "$work" -c "$f" -o "$object" 2>"$work/compile.log"; then
                            failed_object=1
                            break
                        fi
                        objects+=("$object")
                        object_index=$((object_index+1))
                    done
                    if [ "$failed_object" -eq 0 ]; then
                        for object in "${objects[@]}"; do
                            if ! check_allowed_functions "$object" "$allowed"; then
                                failed_object=1
                                break
                            fi
                        done
                    fi
                    if [ "$failed_object" -eq 0 ] && "${COMPILER[@]}" $CFLAGS -I "$work" -c "$harness" -o "$object_dir/harness.o" 2>"$work/compile.log"; then
                        objects+=("$object_dir/harness.o")
                        if "${COMPILER[@]}" "${objects[@]}" -o "$bin" 2>>"$work/compile.log"; then
                            function_tested=1
                            compiled_ok=1
                            if function_output=$(timeout 5 "$bin" 2>&1); then
                                echo "${GRN}$(tr_text 'Testes da função' 'Function tests for') '$name': $(tr_text 'passaram.' 'passed.')${RST}"
                                echo "${DIM}$(tr_text 'Verificação parcial; não substitui a correção oficial.' 'Partial check; this does not replace the official evaluation.')${RST}"
                                AUTO_TESTS_OK=1
                            else
                                echo "${RED}$(tr_text 'Testes da função' 'Function tests for') '$name': $(tr_text 'falharam.' 'failed.')${RST}"
                                [ -n "$function_output" ] && echo "$function_output"
                            fi
                        else
                            echo "${RED}$(tr_text 'Não foi possível ligar o executável de teste da função:' 'Could not link the function test executable:')${RST}"
                            cat "$work/compile.log"
                        fi
                    else
                        echo "${RED}$(tr_text 'Não foi possível compilar a função ou os testes:' 'Could not compile the function or its tests:')${RST}"
                        cat "$work/compile.log"
                    fi
                elif "${COMPILER[@]}" $CFLAGS "${srcs[@]}" -o "$bin" 2>"$work/compile.log"; then
                    echo "${GRN}$(tr_text 'Compilação concluída.' 'Compilation complete.')${RST}"
                    if check_allowed_functions "$bin" "$allowed"; then
                        run_auto_tests "$subject_file" "$name" "$work" "$bin"
                        compiled_ok=1
                    else
                        AUTO_TESTS_OK=0
                    fi
                elif grep -Eq "undefined reference to .main.|undefined symbol: main" "$work/compile.log"; then
                    object_index=0
                    failed_object=0
                    objects=()
                    for f in "${srcs[@]}"; do
                        object="$object_dir/$object_index.o"
                        if ! "${COMPILER[@]}" $CFLAGS -I "$work" -c "$f" -o "$object" 2>"$work/compile.log"; then
                            failed_object=1
                            break
                        fi
                        objects+=("$object")
                        object_index=$((object_index+1))
                    done
                    if [ "$failed_object" -eq 0 ] && [ "$object_index" -gt 0 ]; then
                        for object in "${objects[@]}"; do
                            if ! check_allowed_functions "$object" "$allowed"; then
                                failed_object=1
                                break
                            fi
                        done
                    fi
                    if [ "$failed_object" -eq 0 ] && [ "$object_index" -gt 0 ]; then
                        echo "${GRN}$(tr_text 'Os ficheiros foram compilados.' 'Files compiled.')${RST}"
                        echo "${DIM}$(tr_text 'Ainda não há testes automáticos para a função' 'There are no automated tests for function') '$name'.${RST}"
                        compiled_ok=1
                        object_only=1
                        AUTO_TESTS_OK=0
                    else
                        echo "${RED}$(tr_text 'Falha na compilação:' 'Compilation failed:')${RST}"
                        cat "$work/compile.log"
                    fi
                else
                    echo "${RED}$(tr_text 'Falha na compilação:' 'Compilation failed:')${RST}"
                    cat "$work/compile.log"
                fi
                ;;
            t|test)
                if [ "$function_tested" -eq 1 ] && [ -x "$bin" ]; then
                    local function_output
                    if function_output=$(timeout 5 "$bin" 2>&1); then
                        echo "${GRN}$(tr_text 'Testes da função' 'Function tests for') '$name': $(tr_text 'passaram.' 'passed.')${RST}"
                        echo "${DIM}$(tr_text 'Verificação parcial; não substitui a correção oficial.' 'Partial check; this does not replace the official evaluation.')${RST}"
                        AUTO_TESTS_OK=1
                    else
                        echo "${RED}$(tr_text 'Testes da função' 'Function tests for') '$name': $(tr_text 'falharam.' 'failed.')${RST}"
                        [ -n "$function_output" ] && echo "$function_output"
                        AUTO_TESTS_OK=0
                    fi
                elif [ "$object_only" -eq 1 ]; then
                    echo "${YEL}$(tr_text 'Esta função não gera um programa executável para testar diretamente.' 'This function does not produce an executable that can be tested directly.')${RST}"
                elif [ -x "$bin" ]; then
                    run_auto_tests "$subject_file" "$name" "$work" "$bin"
                else
                    echo "${YEL}$(tr_text 'Ainda não há programa compilado. Use [c] Compilar.' 'There is no compiled program yet. Use [c] Compile.')${RST}"
                fi
                ;;
            r|run)
                if [ "$object_only" -eq 1 ] || [ "$function_tested" -eq 1 ]; then
                    echo "${YEL}$(tr_text 'Esta função não gera um programa executável para iniciar.' 'This function does not produce an executable that can be run.')${RST}"
                elif [ -x "$bin" ]; then
                    echo "${DIM}$(tr_text 'A executar — Ctrl-C interrompe o programa.' 'Running — Ctrl-C stops the program.')${RST}"
                    local -a args=()
                    local args_line=""
                    read_exercise_line "$(tr_text 'Argumentos (opcional): ' 'Arguments (optional): ')" args_line || args_line=""
                    local -a args=()
                    read -r -a args <<< "$args_line"
                    "$bin" "${args[@]}"
                    local run_rc=$?
                    echo
                    echo "${DIM}$(tr_text 'Código de saída:' 'Exit code:') $run_rc${RST}"
                else
                    echo "${YEL}$(tr_text 'Ainda não há programa compilado. Use [c] Compilar.' 'There is no compiled program yet. Use [c] Compile.')${RST}"
                fi
                ;;
            s|subject)
                show_subject "$subject_file"
                ;;
            n|next)
                if [ "$compiled_ok" -eq 1 ] && [ "$AUTO_TESTS_OK" -eq 1 ]; then
                    return 0
                else
                    read_exercise_line "$(tr_text 'A compilação ou os testes ainda falham. Avançar mesmo assim? [s/N] ' 'Compilation or tests are still failing. Continue anyway? [y/N] ')" y || y=""
                    [[ "$y" == [sS] || "$y" == [yY] ]] && return 0
                fi
                ;;
            k|skip)
                return 1
                ;;
            q|quit)
                return 3
                ;;
            *)
                echo "${YEL}$(tr_text 'Comando desconhecido. Escolha uma opção do menu.' 'Unknown command. Choose an option from the menu.')${RST}"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    load_language
    load_saved_progress
    parse_args "$@"
    [ "${#COMPILER[@]}" -gt 0 ] || die "CC must name a compiler"
    run_preflight || return 1

    choose_exam
    [ "$EXIT_REQUESTED" -eq 1 ] && return 0
    if [ "$REAL_MODE" -eq 1 ]; then
        for exam in "${REAL_ORDER[@]}"; do
            [ -d "$EXAM_ROOT/$exam" ] || die "required exam '$exam' not found under '$EXAM_ROOT'"
        done
    fi
    [ -n "$DURATION_MIN" ] || DURATION_MIN=$(default_duration_for "$EXAM_CHOICE")

    local session_id
    session_id="$(date +%Y%m%d-%H%M%S)-${EXAM_CHOICE}"
    local session_dir="$WORKDIR_ROOT/$session_id"
    mkdir -p "$session_dir"
    local logfile="$session_dir/session.log"

    section "$(ui title)"
    if [ "$REAL_MODE" -eq 1 ]; then
        if [ "$LANGUAGE" = en ]; then
            printf '  Mode       %s\n' "Real Mode · ${REAL_ORDER[*]}"
        else
            printf '  Modo       %s\n' "Modo Real · ${REAL_ORDER[*]}"
        fi
    else
        printf '  %s      %s\n' "$([ "$LANGUAGE" = en ] && printf 'Exam' || printf 'Exame')" "$EXAM_CHOICE"
    fi
    printf '  %s    %s\n' "$([ "$LANGUAGE" = en ] && printf 'Duration' || printf 'Duração')" "$([ "$DURATION_MIN" -eq 0 ] && { [ "$LANGUAGE" = en ] && echo unlimited || echo 'sem limite'; } || echo "${DURATION_MIN} min")"
    printf '  %s     %s\n' "$(tr_text 'Sessão' 'Session')" "$session_dir"
    echo
    if [ "$LANGUAGE" = en ]; then
        echo "  No network, browser, or man pages during the exam."
        read -rp "  Press ENTER to begin › " _
    else
        echo "  Sem rede, navegador ou páginas de manual durante o exame."
        read -rp "  $(tr_text 'Pressione ENTER para começar › ' 'Press ENTER to begin › ')" _
    fi

    {
        echo "exam=$EXAM_CHOICE real_mode=$REAL_MODE duration_min=$DURATION_MIN start=$(date -Iseconds)"
    } >> "$logfile"

    local curriculum=()
    while IFS= read -r -d '' rec; do curriculum+=("$rec"); done < <(build_curriculum)
    local total=${#curriculum[@]}
    [ "$total" -gt 0 ] || die "$(tr_text 'não foram encontrados níveis para' 'no levels were found for') '$EXAM_CHOICE' $(tr_text 'em' 'in') '$EXAM_ROOT'"
    local -a level_exercises=() level_results=()
    local idx=0 rec_exam lvl ex current_exam=""
    local cleared=0 skipped=0

    # Pick each exercise up front so the final report can name pending work.
    for rec in "${curriculum[@]}"; do
        lvl="${rec#*$'\x1f'}"
        if [ -n "$SELECTED_EXERCISE" ]; then
            ex="$SELECTED_EXERCISE"
        else
            ex="$(pick_exercise "$lvl")" || ex=""
        fi
        level_exercises+=("$ex")
        level_results+=(pending)
    done

    if [ -r "$SESSION_PROGRESS_FILE" ]; then
        load_session_progress
    fi

    for idx in "${!curriculum[@]}"; do
        if [ "${level_results[$idx]:-pending}" = "completed" ]; then
            cleared=$((cleared+1))
        elif [ "${level_results[$idx]:-pending}" = "skipped" ]; then
            skipped=$((skipped+1))
        fi
    done

    for idx in "${!curriculum[@]}"; do
        if [ "${level_results[$idx]:-pending}" = "completed" ] || [ "${level_results[$idx]:-pending}" = "skipped" ]; then
            continue
        fi
        if time_is_up; then break; fi
        rec="${curriculum[$idx]}"
        rec_exam="${rec%%$'\x1f'*}"
        lvl="${rec#*$'\x1f'}"
        ex="${level_exercises[$idx]}"

        if [ "$rec_exam" != "$current_exam" ]; then
            current_exam="$rec_exam"
            echo
            section "EXAME · $current_exam"
        fi

        if [ -z "$ex" ]; then
            echo "${YEL}$(tr_text 'Sem exercícios neste nível; a sessão vai continuar.' 'No exercises at this level; the session will continue.')${RST}"
            continue
        fi
        local work="$session_dir/${rec_exam}_$(basename "$lvl" | tr ' ' '_')"
        mkdir -p "$work"

        echo
        run_exercise "$ex" "$work" "$current_exam $(basename "$lvl")"
        rc=$?

        case $rc in
            0)
                level_results[$idx]=completed
                cleared=$((cleared+1))
                echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=cleared" >> "$logfile"
                ;;
            1)
                level_results[$idx]=skipped
                skipped=$((skipped+1))
                echo "${YEL}$(tr_text 'Exercício saltado.' 'Exercise skipped.')${RST}"
                echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=skipped" >> "$logfile"
                ;;
            2)
                echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=timeout" >> "$logfile"
                break
                ;;
            3)
                echo "${RED}$(tr_text 'Sessão terminada pelo utilizador.' 'Session ended by the user.')${RST}"
                echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=quit" >> "$logfile"
                break
                ;;
        esac
        save_session_progress
    done

    save_session_progress

    local -a completed_items=() skipped_items=() pending_items=()
    local item_label
    for idx in "${!curriculum[@]}"; do
        rec="${curriculum[$idx]}"
        rec_exam="${rec%%$'\x1f'*}"
        lvl="${rec#*$'\x1f'}"
        ex="${level_exercises[$idx]}"
        if [ -n "$ex" ]; then
            item_label="$rec_exam · $(basename "$lvl") · $(basename "$ex" .subject.txt)"
        else
            item_label="$rec_exam · $(basename "$lvl") · sem exercício disponível"
        fi
        case "${level_results[$idx]}" in
            completed) completed_items+=("$item_label") ;;
            skipped) skipped_items+=("$item_label") ;;
            pending) pending_items+=("$item_label") ;;
        esac
    done

    echo
    if [ "$REAL_MODE" -eq 1 ]; then
        section "$(tr_text 'RELATÓRIO · MODO REAL' 'REPORT · REAL MODE')"
    else
        section "$(tr_text 'RELATÓRIO ·' 'REPORT ·') $EXAM_CHOICE"
    fi
    if [ "$LANGUAGE" = en ]; then
        printf 'Total levels        : %s\n' "$total"
        printf 'Completed           : %s / %s\n' "$cleared" "$total"
        printf 'Skipped             : %s\n' "$skipped"
        printf 'Pending             : %s\n' "${#pending_items[@]}"
    else
        printf 'Total de níveis     : %s\n' "$total"
        printf 'Concluídos          : %s / %s\n' "$cleared" "$total"
        printf 'Saltados            : %s\n' "$skipped"
        printf 'Pendentes           : %s\n' "${#pending_items[@]}"
    fi
    printf '\n%s%s%s\n' "$GRN$BOLD" "$(tr_text 'Concluídos' 'Completed')" "$RST"
    if [ "${#completed_items[@]}" -eq 0 ]; then echo "  $(tr_text 'Nenhum' 'None')"; else for item_label in "${completed_items[@]}"; do printf '  ✓ %s\n' "$item_label"; done; fi
    printf '\n%s%s%s\n' "$YEL$BOLD" "$(tr_text 'Saltados' 'Skipped')" "$RST"
    if [ "${#skipped_items[@]}" -eq 0 ]; then echo "  $(tr_text 'Nenhum' 'None')"; else for item_label in "${skipped_items[@]}"; do printf '  - %s\n' "$item_label"; done; fi
    printf '\n%s%s%s\n' "$CYA$BOLD" "$(tr_text 'Pendentes' 'Pending')" "$RST"
    if [ "${#pending_items[@]}" -eq 0 ]; then echo "  $(tr_text 'Nenhum' 'None')"; else for item_label in "${pending_items[@]}"; do printf '  · %s\n' "$item_label"; done; fi
    if [ "$DURATION_MIN" -eq 0 ]; then
        echo "$(tr_text 'Tempo utilizado  : sem limite' 'Time used        : unlimited')"
    else
        echo "$(tr_text 'Tempo utilizado  :' 'Time used        :') $(fmt_secs $(( DURATION_MIN*60 - $(seconds_left) )))"
    fi
    echo "$(tr_text 'Registo da sessão:' 'Session log:') $logfile"
    hr
    echo "$(date -Iseconds) cleared=$cleared skipped=$skipped pending=${#pending_items[@]} total_levels=$total" >> "$logfile"
}

main "$@"
