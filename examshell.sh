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
WORKDIR_ROOT="${HOME}/.examshell/sessions"
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
die() { echo "${RED}Erro:${RST} $*" >&2; exit 1; }

hr() { printf '%s\n' '────────────────────────────────────────────────────────────────────'; }

section() {
    hr
    printf '%s%s%s\n' "$BOLD$BLU" "$1" "$RST"
    hr
}

need_bin() { command -v "$1" >/dev/null 2>&1 || die "required tool '$1' not found in PATH"; }

usage() {
    sed -n '2,45p' "$0" | sed 's/^# \{0,1\}//'
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
    [ "$#" -eq 0 ] || die "unexpected argument: $1 (use -h for help)"
    if [ -n "$DURATION_MIN" ]; then
        [[ "$DURATION_MIN" =~ ^[0-9]+$ ]] || die "duration must be a non-negative whole number of minutes"
    fi
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
        mapfile -t exams < <(list_exams)
        [ "${#exams[@]}" -gt 0 ] || die "não foram encontrados exames em '$EXAM_ROOT'"
        if [[ -t 1 ]]; then
            printf '\033[H\033[J'
        fi
        printf '%s┌────────────────────────────────────────┐%s\n' "$CYA" "$RST"
        printf '%s│%s           %s           %s│%s\n' "$CYA" "$YEL" 'EXAM SHELL - 42' "$CYA" "$RST"
        printf '%s└────────────────────────────────────────┘%s\n' "$CYA" "$RST"
        printf '\n Selecione um exame para começar:\n\n'
        local i=1
        for e in "${exams[@]}"; do printf '  %s[%02d]%s %s\n' "$GRN" "$i" "$RST" "$e"; i=$((i+1)); done
        printf '\n  %s[ m]%s Modo Real %s(todos em sequência)%s\n' "$MAG" "$RST" "$DIM" "$RST"
        printf '  %s[ r]%s Exame aleatório\n' "$MAG" "$RST"
        printf '  %s[ u]%s Atualizar pelo GitHub\n' "$MAG" "$RST"
        printf '  %s[ q]%s Sair do programa\n\n' "$RED" "$RST"
        while true; do
            printf '%s ❯ %s' "$CYA" "$RST"
            read -r pick
            if [ "$pick" != "u" ]; then break; fi
            update_project
            update_status=$?
            if [ "$update_status" -eq 2 ]; then
                echo "Reinicie o programa para usar a versão atualizada."
                EXIT_REQUESTED=1
                return 0
            fi
            printf '\n'
        done
        if [ "$pick" = "q" ]; then
            EXIT_REQUESTED=1
            echo "Até logo."
            return 0
        elif [ "$pick" = "r" ]; then
            EXAM_CHOICE="${exams[$((RANDOM % ${#exams[@]}))]}"
        elif [ "$pick" = "m" ]; then
            EXAM_CHOICE="real"
        elif [[ "$pick" =~ ^[0-9]+$ ]] && [ "$pick" -ge 1 ] && [ "$pick" -le "${#exams[@]}" ]; then
            EXAM_CHOICE="${exams[$((pick-1))]}"
        else
            die "opção inválida: '$pick'"
        fi
    elif [ "$EXAM_CHOICE" = "random" ]; then
        local -a exams=()
        mapfile -t exams < <(list_exams)
        [ "${#exams[@]}" -gt 0 ] || die "não foram encontrados exames em '$EXAM_ROOT'"
        EXAM_CHOICE="${exams[$((RANDOM % ${#exams[@]}))]}"
    fi

    if [ "$EXAM_CHOICE" = "real" ]; then
        REAL_MODE=1
        return
    fi
    [ -d "$EXAM_ROOT/$EXAM_CHOICE" ] || die "exam '$EXAM_CHOICE' not found under $EXAM_ROOT"
}

update_project() {
    local remote_url branch
    if ! command -v git >/dev/null 2>&1; then
        echo "${RED}Não foi possível atualizar: o Git não está instalado.${RST}"
        return 1
    fi
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        echo "${RED}Não foi possível atualizar: esta cópia não está dentro de um repositório Git.${RST}"
        return 1
    fi
    remote_url="$(git -C "$SCRIPT_DIR" remote get-url origin 2>/dev/null)" || {
        echo "${RED}Não foi possível atualizar: o remoto 'origin' não está configurado.${RST}"
        return 1
    }
    case "$remote_url" in
        https://github.com/*|http://github.com/*|git@github.com:*|ssh://git@github.com/*) ;;
        *) echo "${RED}Não foi possível atualizar: 'origin' não aponta para GitHub.${RST}"
           return 1 ;;
    esac
    if [ -n "$(git -C "$SCRIPT_DIR" status --porcelain --untracked-files=normal)" ]; then
        echo "${YEL}Atualização cancelada: há alterações locais no projeto. Guarde ou descarte-as e tente novamente.${RST}"
        return 1
    fi
    branch="$(git -C "$SCRIPT_DIR" symbolic-ref --quiet --short HEAD)" || {
        echo "${RED}Não foi possível atualizar: HEAD não aponta para um branch.${RST}"
        return 1
    }

    echo "A procurar atualizações no GitHub..."
    if ! git -C "$SCRIPT_DIR" pull --ff-only origin "$branch"; then
        echo "${RED}A atualização falhou. Verifique a ligação, o acesso ao GitHub e se o branch pode avançar sem conflitos.${RST}"
        return 1
    fi
    echo "${GRN}Projeto sincronizado com o GitHub.${RST}"
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

# ---------------------------------------------------------------------------
# Subject parsing
# ---------------------------------------------------------------------------
subj_field() {
    # subj_field FILE "Field name"
    grep -m1 "^$2" "$1" | sed -E "s/^$2[[:space:]]*:[[:space:]]*//"
}

show_subject() {
    printf '%sEXERCÍCIO · %s%s\n' "$BOLD$CYA" "$(basename "$1" .subject.txt)" "$RST"
    hr
    cat "$1"
    hr
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
    [ "$DURATION_MIN" -eq 0 ] && return 1
    [ "$(seconds_left)" -le 0 ]
}

# ---------------------------------------------------------------------------
# Compile-time "allowed functions" enforcement, mimicking the moulinette
# ---------------------------------------------------------------------------
check_allowed_functions() {
    local binary="$1" allowed_raw="$2"
    # Normalise the allowed list: "None" / "" => nothing is allowed.
    local allowed_norm
    allowed_norm=$(echo "$allowed_raw" | tr ',' ' ' | tr -s ' ')
    if echo "$allowed_norm" | grep -qiw "none"; then
        allowed_norm=""
    fi

    local nm_output undefined
    if ! nm_output=$(nm --undefined-only "$binary" 2>/dev/null); then
        echo "${RED}Não foi possível verificar as funções usadas em '$binary'.${RST}"
        return 1
    fi
    undefined=$(printf '%s\n' "$nm_output" | awk '{print $NF}')

    local violations=()
    for raw_sym in $undefined; do
        [ -z "$raw_sym" ] && continue
        # nm prints versioned symbols as "name@GLIBC_x.y" (or "@@..."); strip
        # the version suffix before comparing against the allow/ignore lists.
        local sym="${raw_sym%%@*}"
        case " $IGNORE_SYMS " in *" $sym "*) continue ;; esac
        local ok=0
        for a in $allowed_norm; do
            [ "$sym" = "$a" ] && ok=1 && break
        done
        [ "$ok" -eq 0 ] && violations+=("$raw_sym")
    done

    if [ "${#violations[@]}" -gt 0 ]; then
        echo "${RED}${BOLD}Função(ões) não permitida(s):${RST} ${violations[*]}"
        echo "${DIM}Permitidas: ${allowed_raw:-nenhuma}${RST}"
        return 1
    fi
    echo "${GRN}Verificação de funções permitidas: OK${RST}"
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
            first_fail="teste $i: \`$inv\`"$'\n'"codigo de saida: $test_rc"$'\n'"esperado:"$'\n'"$exp_t"$'\n'"obtido:"$'\n'"$got_t"
        fi
    done

    if [ "$total" -eq 0 ]; then
        echo "${YEL}Este enunciado não tem exemplos que possam ser testados automaticamente.${RST}"
        echo "Confirme a solução com [r] Executar; avance depois com [n] Próximo."
        AUTO_TESTS_OK=0
        return
    fi

    if [ "$passed" -eq "$total" ]; then
        echo "${GRN}Testes dos exemplos: $passed/$total passaram.${RST}"
        echo "${DIM}Verificação parcial; não substitui a correção oficial.${RST}"
        AUTO_TESTS_OK=1
    else
        echo "${RED}${BOLD}Testes dos exemplos: $passed/$total passaram.${RST}"
        echo "${DIM}$first_fail${RST}"
        echo "${DIM}Verificação parcial; não substitui a correção oficial.${RST}"
        AUTO_TESTS_OK=0
    fi
}

# ---------------------------------------------------------------------------
# One exercise "station": edit / load / compile / test / run / next / skip
# ---------------------------------------------------------------------------
run_exercise() {
    local subject_file="$1" work="$2" level_label="$3"
    local name expected allowed
    name=$(subj_field "$subject_file" "Assignment name")
    name="${name:-$(basename "$subject_file" .subject.txt)}"
    expected=$(subj_field "$subject_file" "Expected files")
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
        time_is_up && { echo "${RED}${BOLD}Tempo esgotado.${RST}"; return 2; }
        echo
        hr
        printf '%s%s%s  ·  %s  ·  Tempo: %s\n' "$BOLD$CYA" "$level_label" "$RST" "${name:-?}" "$(fmt_secs "$(seconds_left)")"
        echo "[e] Editar   [l] Carregar   [c] Compilar   [t] Testar"
        echo "[r] Executar [s] Enunciado  [n] Próximo    [k] Saltar   [q] Sair"
        if ! read -rp "examshell › " cmd; then
            echo
            echo "${YEL}Entrada encerrada; a sessão será finalizada.${RST}"
            return 3
        fi
        time_is_up && { echo "${RED}${BOLD}Tempo esgotado.${RST}"; return 2; }

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
                read -rp "Caminho do ficheiro para carregar: " src || src=""
                if [ -z "$src" ] || [ ! -f "$src" ]; then
                    echo "${YEL}Ficheiro não encontrado: $src${RST}"
                else
                    cp -- "$src" "$work/$first_file"
                    compiled_ok=0
                    object_only=0
                    function_tested=0
                    AUTO_TESTS_OK=0
                    rm -f -- "$bin"
                    echo "${GRN}Solução carregada. Use [c] Compilar para continuar.${RST}"
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
                                echo "${GRN}Testes da função '$name': passaram.${RST}"
                                echo "${DIM}Verificação parcial; não substitui a correção oficial.${RST}"
                                AUTO_TESTS_OK=1
                            else
                                echo "${RED}Testes da função '$name': falharam.${RST}"
                                [ -n "$function_output" ] && echo "$function_output"
                            fi
                        else
                            echo "${RED}Não foi possível ligar o executável de teste da função:${RST}"
                            cat "$work/compile.log"
                        fi
                    else
                        echo "${RED}Não foi possível compilar a função ou os testes:${RST}"
                        cat "$work/compile.log"
                    fi
                elif "${COMPILER[@]}" $CFLAGS "${srcs[@]}" -o "$bin" 2>"$work/compile.log"; then
                    echo "${GRN}Compilação concluída.${RST}"
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
                        echo "${GRN}Os ficheiros foram compilados.${RST}"
                        echo "${DIM}Ainda não há testes automáticos para a função '$name'.${RST}"
                        compiled_ok=1
                        object_only=1
                        AUTO_TESTS_OK=0
                    else
                        echo "${RED}Falha na compilação:${RST}"
                        cat "$work/compile.log"
                    fi
                else
                    echo "${RED}Falha na compilação:${RST}"
                    cat "$work/compile.log"
                fi
                ;;
            t|test)
                if [ "$function_tested" -eq 1 ] && [ -x "$bin" ]; then
                    local function_output
                    if function_output=$(timeout 5 "$bin" 2>&1); then
                        echo "${GRN}Testes da função '$name': passaram.${RST}"
                        echo "${DIM}Verificação parcial; não substitui a correção oficial.${RST}"
                        AUTO_TESTS_OK=1
                    else
                        echo "${RED}Testes da função '$name': falharam.${RST}"
                        [ -n "$function_output" ] && echo "$function_output"
                        AUTO_TESTS_OK=0
                    fi
                elif [ "$object_only" -eq 1 ]; then
                    echo "${YEL}Esta função não gera um programa executável para testar diretamente.${RST}"
                elif [ -x "$bin" ]; then
                    run_auto_tests "$subject_file" "$name" "$work" "$bin"
                else
                    echo "${YEL}Ainda não há programa compilado. Use [c] Compilar.${RST}"
                fi
                ;;
            r|run)
                if [ "$object_only" -eq 1 ] || [ "$function_tested" -eq 1 ]; then
                    echo "${YEL}Esta função não gera um programa executável para iniciar.${RST}"
                elif [ -x "$bin" ]; then
                    echo "${DIM}A executar — Ctrl-C interrompe o programa.${RST}"
                    local -a args=()
                    read -rp "Argumentos (opcional): " -a args || args=()
                    "$bin" "${args[@]}"
                    local run_rc=$?
                    echo
                    echo "${DIM}Código de saída: $run_rc${RST}"
                else
                    echo "${YEL}Ainda não há programa compilado. Use [c] Compilar.${RST}"
                fi
                ;;
            s|subject)
                show_subject "$subject_file"
                ;;
            n|next)
                if [ "$compiled_ok" -eq 1 ] && [ "$AUTO_TESTS_OK" -eq 1 ]; then
                    return 0
                else
                    read -rp "A compilação ou os testes ainda falham. Avançar mesmo assim? [s/N] " y
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
                echo "${YEL}Comando desconhecido. Escolha uma opção do menu.${RST}"
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
    parse_args "$@"
    [ "${#COMPILER[@]}" -gt 0 ] || die "CC must name a compiler"
    need_bin "${COMPILER[0]}"
    need_bin nm
    need_bin python3
    need_bin timeout
    need_bin awk
    need_bin sort
    need_bin find
    need_bin sed
    need_bin grep
    need_bin tr
    need_bin xargs
    need_bin basename
    need_bin mkdir
    need_bin cp
    need_bin cat
    need_bin date
    [ -d "$EXAM_ROOT" ] || die "exam-practice directory not found at '$EXAM_ROOT' (use -d to point at it)"

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

    section "EXAMSHELL · TREINO DE EXAMES 42"
    if [ "$REAL_MODE" -eq 1 ]; then
        printf '  Modo       %s\n' "Modo Real · ${REAL_ORDER[*]}"
    else
        printf '  Exame      %s\n' "$EXAM_CHOICE"
    fi
    printf '  Duração    %s\n' "$([ "$DURATION_MIN" -eq 0 ] && echo "sem limite" || echo "${DURATION_MIN} min")"
    printf '  Sessão     %s\n' "$session_dir"
    echo
    echo "  Sem rede, navegador ou páginas de manual durante o exame."
    read -rp "  Pressione ENTER para começar › " _

    start_timer
    {
        echo "exam=$EXAM_CHOICE real_mode=$REAL_MODE duration_min=$DURATION_MIN start=$(date -Iseconds)"
    } >> "$logfile"

    local curriculum=()
    while IFS= read -r -d '' rec; do curriculum+=("$rec"); done < <(build_curriculum)
    local total=${#curriculum[@]}
    [ "$total" -gt 0 ] || die "não foram encontrados níveis para '$EXAM_CHOICE' em '$EXAM_ROOT'"
    local cleared=0
    local current_exam=""

    for rec in "${curriculum[@]}"; do
        if time_is_up; then break; fi
        local rec_exam="${rec%%$'\x1f'*}"
        local lvl="${rec#*$'\x1f'}"

        if [ "$rec_exam" != "$current_exam" ]; then
            current_exam="$rec_exam"
            echo
            section "EXAME · $current_exam"
        fi

        local ex
        ex="$(pick_exercise "$lvl")" || { echo "${YEL}Sem exercícios neste nível; a sessão vai continuar.${RST}"; continue; }
        local work="$session_dir/${rec_exam}_$(basename "$lvl" | tr ' ' '_')"
        mkdir -p "$work"

        echo
        run_exercise "$ex" "$work" "$current_exam $(basename "$lvl")"
        rc=$?

        case $rc in
            0) cleared=$((cleared+1))
               echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=cleared" >> "$logfile" ;;
            1) echo "${YEL}Exercício saltado.${RST}"
               echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=skipped" >> "$logfile" ;;
            2) echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=timeout" >> "$logfile"
               break ;;
            3) echo "${RED}Sessão terminada pelo utilizador.${RST}"
               echo "$current_exam $(basename "$lvl") exercise=$(basename "$ex") result=quit" >> "$logfile"
               break ;;
        esac
    done

    echo
    if [ "$REAL_MODE" -eq 1 ]; then
        section "RELATÓRIO · MODO REAL"
    else
        section "RELATÓRIO · $EXAM_CHOICE"
    fi
    echo "Níveis concluídos : ${GRN}${cleared} / ${total}${RST}"
    if [ "$DURATION_MIN" -eq 0 ]; then
        echo "Tempo utilizado  : sem limite"
    else
        echo "Tempo utilizado  : $(fmt_secs $(( DURATION_MIN*60 - $(seconds_left) )))"
    fi
    echo "Registo da sessão: $logfile"
    hr
    echo "$(date -Iseconds) cleared=$cleared total=$total" >> "$logfile"
}

main "$@"
